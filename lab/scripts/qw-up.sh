#!/bin/bash
# 一键核对/拉起演练环境。开课前跑一次，跑完一轮再跑一次。
#
# 它只做两类事：**核对**（默认）与**拉起 daemon**（未运行时）。除此之外不改任何共享状态——
# 发布 SOP、建群、绑角色、装描述都由 lab/install.sh 与 qw-group.sh 负责，
# 因为那些动作会让正在跑的角色读到与开场时不同的事实源。
#
# 用法：
#   lab/scripts/qw-up.sh            核对全部，daemon 未运行则拉起
#   lab/scripts/qw-up.sh status     只核对，不启动任何东西
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../env.sh
. "$HERE/../env.sh"

# HERE 是 lab/scripts，不是 lab/。资产清单与守卫扫描都是相对 lab/ 写的，
# 用 HERE 去拼会全部落到 lab/scripts/ 下、全部判为「缺失」，
# 而退役表述守卫更糟：它扫不到任何文件，于是报一个假的「ok」。
LABDIR="$(cd "$HERE/.." && pwd)"
REPO="$(cd "$LABDIR/.." && pwd)"
STATUS_ONLY=0
[ "${1:-}" = "status" ] && STATUS_ONLY=1
FAIL=0
warn() { echo "  !  $1"; FAIL=$((FAIL + 1)); }
bad()  { echo "  x  $1"; FAIL=$((FAIL + 1)); }

echo "== 1) QoderWake daemon（:${QW_DAEMON_PORT}）=="
if lab_daemon_up; then
  echo "  ok 运行中（pid $(lsof -nP -iTCP:"$QW_DAEMON_PORT" -sTCP:LISTEN -t 2>/dev/null | head -1)）"
elif [ "$STATUS_ONLY" = 1 ]; then
  echo "  -  未运行（status 模式不启动）"; FAIL=$((FAIL + 1))
else
  echo "  !  未运行，尝试启动"
  "$QW" start 2>&1 | tail -3 | sed 's/^/     /'
  lab_daemon_up && echo "  ok 已启动" || bad "启动失败"
fi

echo "== 2) 仓内资产自检 =="
# 这份清单就是「演练所需的全部可版本化资产」。缺任何一项都意味着仓不自洽——
# 本演练的一条硬要求是：除了 token 的值和已安装的软件，不依赖任何仓外配套。
for f in env.sh install.sh README.md \
         guard/file-guard-additions.json \
         sop/sop-body.md sop/build-sop.js sop/github-lab-group-delivery.json \
         scripts/github-lab.sh scripts/gh-askpass.sh \
         scripts/qw-api.sh scripts/qw-render.js scripts/qw-group.sh \
         scripts/qw-up.sh scripts/qw-backup.sh scripts/check-public-hygiene.sh \
         wakers/desc-lead.txt wakers/desc-pm.txt wakers/desc-dev.txt \
         wakers/desc-qa.txt wakers/desc-devops.txt; do
  p="$LABDIR/$f"
  if [ -f "$p" ]; then
    case "$f" in scripts/*.sh) [ -x "$p" ] || warn "$f 存在但没有执行位（git 里要 100755，否则学员 clone 下来跑不动）";; esac
    echo "  ok  lab/$f"
  else
    bad "缺失 lab/$f"
  fi
done
for f in AGENTS.md .github/workflows/gate.yml docs/实验手册-v4-学员版.md .devflow/README.md; do
  [ -f "$REPO/$f" ] && echo "  ok  $f" || bad "缺失 $f"
done
# 门禁迁到 Actions 后，仓根那个流水线定义文件已删除。它若又出现，说明有人把已退役的 CI 口径带回来了。
# 标记必须与命中在**同一行**（扫描器逐行过滤），加在邻近行不生效。
[ -f "$REPO/Jenkinsfile" ] && warn "Jenkinsfile 又出现了——门禁在 .github/workflows/gate.yml，这个文件是已退役口径"  # hygiene-allow: 这条检查的目的就是点名那个已退役文件

echo "== 3) 凭据（只核对存在性与权限，绝不打印内容）=="
# 取权限位。stat -f '%Lp' 是 BSD/macOS 语法，GNU/Linux 是 stat -c '%a'。
# 两者都试，都拿不到就**明说跳过了**——不要拿着空值去和 600 比，
# 那会输出一句「权限是 ，应为 600」，读的人以为权限坏了，其实是脚本不认识这台机器。
perm_of() {
  stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1" 2>/dev/null || echo ""
}
if [ -f "$GITHUB_WAKER_TOKEN_FILE" ]; then
  perm="$(perm_of "$GITHUB_WAKER_TOKEN_FILE")"
  dperm="$(perm_of "$(dirname "$GITHUB_WAKER_TOKEN_FILE")")"
  size=$(wc -c < "$GITHUB_WAKER_TOKEN_FILE" 2>/dev/null | tr -d ' ')
  echo "  ok  ${GITHUB_WAKER_TOKEN_FILE/#$HOME/~}  ${size} 字节  文件权限 ${perm:-未知}  目录权限 ${dperm:-未知}"
  if [ -z "$perm" ] || [ -z "$dperm" ]; then
    warn "本机 stat 既不认 -f '%Lp' 也不认 -c '%a'，权限核对已跳过（不代表通过）。手工核对：ls -l 该文件与其目录，应为 600 / 700"
  else
    [ "$perm" = "600" ] || warn "token 文件权限是 ${perm}，应为 600"
    [ "$dperm" = "700" ] || warn "token 所在目录权限是 ${dperm}，应为 700"
  fi
  # 值绝不能进 git。这条检查很便宜，而一旦漏了就是公开仓里的一次凭据泄漏。
  #
  # 但前缀取不到时**必须放弃核对，不能继续 grep**：git grep -e "" 会匹配每一个文件、
  # 退出码 0，于是这条检查会反过来断言「token 前缀出现在仓库内容里、立即轮换该令牌」——
  # 一次读文件失败（EDR 按访问扫描挡住、权限被改、文件正被重写）就会把人支去轮换一张
  # 好好的凭据，顺带让这条检查从此不被信任。空 pattern 把检查的含义整个反转，
  # 这与「本该防静默放行的检查自己静默放行」是同一族错误。
  prefix="$(head -c 20 "$GITHUB_WAKER_TOKEN_FILE" 2>/dev/null)"
  if [ "${#prefix}" -lt 16 ]; then
    warn "取不到足够长的 token 前缀（拿到 ${#prefix} 字），**跳过**「值是否进了 git」的核对——这不代表通过。手工核对：git grep -c 该令牌前 20 字"
  elif git -C "$REPO" grep -qIl -e "$prefix" 2>/dev/null; then
    bad "token 前缀出现在仓库内容里 —— 立即轮换该令牌并从历史中处置"
  else
    echo "  ok  token 前缀未出现在仓库任何被跟踪文件里"
  fi
else
  bad "缺 token 文件：${GITHUB_WAKER_TOKEN_FILE/#$HOME/~}（用 GITHUB_WAKER_TOKEN_FILE 覆盖路径）"
fi

echo "== 4) 角色描述与 fileGuard（委托 install.sh --check）=="
CHK="$("$LABDIR/install.sh" --check 2>&1)"
printf '%s\n' "$CHK" | sed 's/^/  /'
# install.sh --check 的结论必须计入总数，否则本节报的「不一致」会被上面的「全部通过」盖掉。
# 过渡期（仓内资产已改、daemon 还没重装/重绑）这里本来就该是红的——那是真信号不是故障，
# 但它得出现在计数里，人才会去处理。
D=$(printf '%s\n' "$CHK" | grep -c '不一致' || true)
G=$(printf '%s\n' "$CHK" | grep -cE '缺 [0-9]+ 条|待摘 [0-9]+ 条' || true)
[ "${D:-0}" = 0 ] || warn "${D} 个角色的描述与仓内不一致 → 跑 lab/install.sh 重装"
[ "${G:-0}" = 0 ] || warn "${G} 个角色的 fileGuard 黑名单与仓内不一致 → 跑 lab/install.sh 合并"
printf '%s\n' "$CHK" | grep -q '读取失败\|READ_FAIL' && bad "有角色的 permission 配置读不到，本节结论不完整"

echo "== 5) 群与 SOP 绑定 =="
if G="$(lab_group 2>/dev/null)"; then
  echo "  ok  群「${LAB_GROUP_TITLE}」 group=${G}"
  "$HERE/qw-group.sh" sop 2>&1 | sed 's/^/  /'
else
  bad "找不到标题为「${LAB_GROUP_TITLE}」的群。建群命令见 lab/install.sh 末尾输出。"
fi

echo "== 6) 靶仓工作树占用 =="
lab_worktrees
echo "  ⚠ 同一个分支不能被两个 worktree 同时 checkout。操作员要在 main 上做事，"
echo "    先确认没有 Waker 的 worktree 占着它；占用时改用独立 worktree，不要「从当前分支切一个新的」——"
echo "    那会把某个 Waker 尚未推送的半成品带进你的提交（这个事故真实发生过）。"

echo "== 7) 活体产物退役表述守卫 =="
# 动机是一次真实事故：文档已撤回一个**不存在**的机制说法，但它仍活在正被注入 worker 的
# 角色描述与 SOP 正文里；而「描述一致性检查」只会证明线上等于文件，文件本身错的时候照样报一致。
# 所以要扫的是**内容**。这里扫的是会被装进 daemon 的那几份活体产物，不是文档。
#
# build-sop.js 不在扫描范围里，不是漏了：它的禁用词模式表本身就写着这些词，
# 而它要发布的那些字段由它自己的构建期守卫覆盖（那条守卫做过变异检验，注入 5 处都能抓到并 exit 1）。
# 两处重复扫只会让规则表自己变成永远的红灯，然后被人整条关掉。
RETIRED='jenkins|Jenkins|jenkins-lab|不低于上一次|相对阈值|分支保护|\bMR\b|approver_number|a1 repo|a1 project'  # hygiene-allow: 守卫自己的规则表，必须写出这些字面量
# 放行两类：① 有意写成的否定句/迁移说明（撤回一个说法时往往会把原话引在「不存在…」里）；
#          ② 同一行带 `hygiene-allow: <理由>` 标记的——标记必须带理由，否则它退化成一键忽略。
ALLOW='不存在「不低于上一次」|不是 push 保护|已从本机|已退役|不要按它解释|不应再出现|hygiene-allow:'
HITS=0
SCANNED=0
for f in "$LABDIR"/wakers/desc-*.txt "$LABDIR"/sop/sop-body.md \
         "$LABDIR"/scripts/qw-group.sh "$LABDIR"/scripts/github-lab.sh \
         "$LABDIR"/scripts/qw-render.js "$LABDIR"/env.sh "$REPO/AGENTS.md"; do
  [ -f "$f" ] || { warn "守卫没扫到 $f（文件不存在）——这会让本节报一个假的 ok"; continue; }
  SCANNED=$((SCANNED + 1))
  # 整行匹配再过滤否定句。不能用 grep -o 取片段——片段窗口装不下否定句，会把它也当成命中。
  FOUND=$(grep -En "$RETIRED" "$f" 2>/dev/null | grep -Ev "$ALLOW")
  [ -n "$FOUND" ] || continue
  N=$(printf '%s\n' "$FOUND" | wc -l | tr -d ' ')
  HITS=$((HITS + N))
  echo "  ⚠ ${f#"$REPO"/}  （${N} 行）"
  printf '%s\n' "$FOUND" | cut -c1-180 | sed 's/^/     /'
done
if [ "$SCANNED" = 0 ]; then
  # 一个文件都没扫到还报 ok，就是本节最危险的失败模式。宁可吵。
  bad "退役表述守卫一个文件都没扫到，本次结论无效"
elif [ "$HITS" = 0 ]; then
  echo "  ok  ${SCANNED} 份活体产物里没有已退役的表述残留"
else
  warn "命中 ${HITS} 行。改完记得：描述要 install.sh 重装，SOP 正文要升版本重发并 rebind。"
  echo "     有意保留的提及（版本判据、迁移说明）在同一行加 \`hygiene-allow: <理由>\` 放行。"
fi

echo
if [ "$FAIL" = 0 ]; then
  echo "环境自检：全部通过。"
else
  echo "环境自检：${FAIL} 项需要处理（上面标 ! 或 x 的行）。"
fi
echo "跑完一轮记得做快照：lab/scripts/qw-backup.sh <标签>"
[ "$FAIL" = 0 ] || exit 1
