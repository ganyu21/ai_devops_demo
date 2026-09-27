#!/bin/bash
# 把 lab/ 下的数字员工资产装到本机 QoderWake：
#   1) 五个角色的描述（GitHub 口径）
#   2) fileGuard 黑名单追加（与现有清单合并，不整份替换）
#   3) 构建 SOP JSON（发布与绑定不在这里做，见下面的输出提示）
#
# 幂等：重复跑只是把同样的内容再写一遍。
# 用法：lab/install.sh [--check]     --check 只核对现状，不写任何东西
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QW="${QODERWAKE_BIN:-$HOME/.qoderwake/qoderwake}"
NODE="${NODE_BIN:-/opt/homebrew/bin/node}"
CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

[ -x "$QW" ] || { echo "x 找不到 QoderWake CLI：$QW"; exit 1; }

# Waker ID 会随 store 重建而变，所以按名字解析，不写死 ID。
resolve_id() {
  "$QW" waker list --json 2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
# CLI 的 --json 有的命令返回顶层数组、有的返回 {data:...}，两种都要吃下。
items = d if isinstance(d, list) else (d.get('data') or d.get('wakers') or d.get('agents') or d.get('items') or [])
if isinstance(items, dict):
    items = items.get('wakers') or items.get('agents') or items.get('items') or []
for a in items:
    if a.get('name') == '$1':
        print(a.get('agentId') or a.get('id'))
        break
"
}

echo "== 1) 角色描述 =="
for role in lead pm dev qa devops; do
  case $role in
    lead) name=Lead-Waker;; pm) name=PM-Waker;; dev) name=Dev-Waker;;
    qa) name=QA-Waker;; devops) name=DevOps-Waker;;
  esac
  id="$(resolve_id "$name")"
  if [ -z "$id" ]; then echo "  x 找不到 $name，跳过"; continue; fi
  if [ "$CHECK" = 1 ]; then
    # 描述文本含引号与反引号，一律走文件路径传参，不要把内容拼进 python 源码里。
    cur="$("$QW" waker get --waker-id "$id" --json 2>/dev/null | python3 -c "
import sys, json, os, re
a = json.load(sys.stdin); a = a.get('data', a)
norm = lambda s: re.sub(r'\s+', '', s)
have = norm(a.get('description') or '')
# 与写入时同样展开 ~/，否则永远报不一致。
want = norm(re.sub(r'~/', os.path.expanduser('~') + '/', open(sys.argv[1], encoding='utf-8').read()))
print('一致' if want and want == have else f'不一致（装机 {len(want)} 字 / 现网 {len(have)} 字）')
" "$HERE/wakers/desc-$role.txt" 2>/dev/null)"
    printf '  %-14s %s  %s\n' "$name" "$id" "${cur:-读取失败}"
  else
    # 仓库里的描述用 ~/ 写路径（公开仓不该带机器用户名），装到 daemon 时展开成绝对路径：
    # Waker 的会话工作目录是自己的沙箱，相对路径与 ~ 都可能落错地方。
    rendered="/tmp/desc-$id.txt"
    python3 -c "
import os, re, sys
src = open(sys.argv[1], encoding='utf-8').read()
open(sys.argv[2], 'w', encoding='utf-8').write(re.sub(r'~/', os.path.expanduser('~') + '/', src))
" "$HERE/wakers/desc-$role.txt" "$rendered"
    "$QW" waker update description --waker-id "$id" --file "$rendered" >/dev/null 2>&1 \
      && echo "  ok $name ($id) 描述已更新" || echo "  x $name ($id) 更新失败"
    rm -f "$rendered"
  fi
done

echo "== 2) fileGuard 黑名单 =="
ADDITIONS="$HERE/guard/file-guard-additions.json"
for name in Lead-Waker PM-Waker Dev-Waker QA-Waker DevOps-Waker; do
  id="$(resolve_id "$name")"
  [ -z "$id" ] && { echo "  x 找不到 $name"; continue; }
  merged="$(python3 - "$id" "$ADDITIONS" "$CHECK" <<'PY'
import json, os, subprocess, sys
wid, additions_file, check = sys.argv[1], sys.argv[2], sys.argv[3]
cfg = json.load(open(additions_file))
expand = lambda ps: [os.path.expandvars(p) for p in ps]
add = expand(cfg.get('add') or [])
# remove 是对象形式（{path, why}）：why 里带着公开仓卫生扫描的放行标记与理由，
# 因为「要摘掉的条目」本身就是已退役口径的字面量。
drop = set(expand([r['path'] if isinstance(r, dict) else r for r in (cfg.get('remove') or [])]))
out = subprocess.run([os.path.expanduser('~/.qoderwake/qoderwake'), 'permission', 'get',
                      '--waker-id', wid, '--format', 'json'], capture_output=True, text=True)
# 注意：permission get 的 --json 会打表格，只有 --format json 才真给 JSON。
try:
    d = json.loads(out.stdout); d = d.get('data', d)
except Exception:
    print('READ_FAIL'); raise SystemExit
fg = d.get('fileGuard') or {}
cur = list(fg.get('sensitiveFiles') or [])
missing = [p for p in add if p not in cur]
stale = [p for p in cur if p in drop]
home = os.path.expanduser('~')
short = lambda ps: [p.replace(home, '~') for p in ps]
if check == '1':
    parts = ['已在册' if not missing else '缺 ' + str(len(missing)) + ' 条: ' + ','.join(short(missing))]
    if stale:
        parts.append('待摘 ' + str(len(stale)) + ' 条: ' + ','.join(short(stale)))
    print('；'.join(parts))
    raise SystemExit
merged = [p for p in cur if p not in drop] + missing
section = dict(fg); section['sensitiveFiles'] = merged
section.setdefault('enabled', True)
print(json.dumps(section, ensure_ascii=False))
PY
)"
  if [ "$CHECK" = 1 ]; then
    printf '  %-14s %s\n' "$name" "$merged"
  elif [ "$merged" = "READ_FAIL" ]; then
    echo "  x $name 读不到现有 permission 配置，跳过（不整份覆盖，避免冲掉本机已有条目）"
  else
    printf '%s' "$merged" > /tmp/fg-$id.json
    "$QW" permission patch file-guard --waker-id "$id" --json-file /tmp/fg-$id.json >/dev/null 2>&1 \
      && echo "  ok $name 黑名单已合并" || echo "  x $name patch 失败"
    rm -f /tmp/fg-$id.json
  fi
done

echo "== 3) SOP JSON =="
if [ "$CHECK" = 1 ]; then
  [ -f "$HERE/sop/github-lab-group-delivery.json" ] && echo "  ok 已构建" || echo "  - 尚未构建"
else
  "$NODE" "$HERE/sop/build-sop.js" "${SOP_VERSION:-1.0.0}" 2>&1 | sed 's/^/  /'
fi

cat <<'EOF'

下一步（不在本脚本里做，因为它们会改动共享状态）：
  # 1. 发布 SOP（版本号取自 lab/env.sh 的 LAB_SOP_VERSION；release 一旦发布不可变，改了正文只能升版本）
  source lab/env.sh
  qoderwake sop validate lab/sop/github-lab-group-delivery.json
  qoderwake sop publish  --file lab/sop/github-lab-group-delivery.json

  # 2a. 群还不存在时：建群并同时绑定 SOP 与五个角色
  qoderwake group create --title "$LAB_GROUP_TITLE" \
      --waker "$LAB_WAKER_LEAD" --waker "$LAB_WAKER_PM" --waker "$LAB_WAKER_DEV" \
      --waker "$LAB_WAKER_QA" --waker "$LAB_WAKER_DEVOPS" \
      --sop "${LAB_SOP_ID}@${LAB_SOP_VERSION}" \
      --param "${LAB_SOP_ID}.delivery_lead=${LAB_WAKER_LEAD}" \
      --param "${LAB_SOP_ID}.product_manager=${LAB_WAKER_PM}" \
      --param "${LAB_SOP_ID}.engineering_executor=${LAB_WAKER_DEV}" \
      --param "${LAB_SOP_ID}.qa_reviewer=${LAB_WAKER_QA}" \
      --param "${LAB_SOP_ID}.ci_gate_keeper=${LAB_WAKER_DEVOPS}"

  # 2b. 群已存在、只是版本落后时：用这条重绑（它会先打印当前绑定，并要求输入 yes）
  ./lab/scripts/qw-group.sh rebind

绑定之后必须先预热再验证（绑定 SOP ≠ Waker 读得到正文）：
  ./lab/scripts/qw-group.sh smoke     # 预热消息，第 3 问就是版本判据
  ./lab/scripts/qw-group.sh watch 10  # 看回复
跳过预热就上真需求，五个角色会照着 SOP 标题即兴发挥，而且看起来一切正常。
EOF
