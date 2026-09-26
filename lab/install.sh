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
add = json.load(open(additions_file))['add']
add = [os.path.expandvars(p) for p in add]
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
if check == '1':
    print(('已在册' if not missing else '缺 ' + str(len(missing)) + ' 条: ' + ','.join(
        p.replace(os.path.expanduser('~'), '~') for p in missing)))
    raise SystemExit
merged = cur + missing
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
  qoderwake sop validate lab/sop/github-lab-group-delivery.json
  qoderwake sop publish  --file lab/sop/github-lab-group-delivery.json
  qoderwake group create --title "GitHub 靶仓交付团队" \
      --waker Lead-Waker --waker PM-Waker --waker Dev-Waker --waker QA-Waker --waker DevOps-Waker \
      --sop github-lab-group-delivery@<版本> \
      --param github-lab-group-delivery.delivery_lead=Lead-Waker \
      --param github-lab-group-delivery.product_manager=PM-Waker \
      --param github-lab-group-delivery.engineering_executor=Dev-Waker \
      --param github-lab-group-delivery.qa_reviewer=QA-Waker \
      --param github-lab-group-delivery.ci_gate_keeper=DevOps-Waker

绑定之后必须先预热再验证（绑定 SOP ≠ Waker 读得到正文）：
  发一条预热消息触发物化 → 再发一条验证消息，要求引用 SOP 正文原文。
  跳过预热就上真需求，五个角色会照着 SOP 标题即兴发挥，而且看起来一切正常。
EOF
