#!/bin/bash
# 公开仓卫生扫描。靶仓是**公开**的，所以任何内部平台名、内部单号、机器用户名、
# 真实凭据都不该出现在被跟踪的文件里。这个脚本把散落在各处的检查合成一条可重复跑的守卫。
#
# 为什么需要它而不是靠 review：这类泄漏是逐个文件冒出来的。本仓已经中过三次——
# SOP 构建脚本的禁用词列表自己写了内部平台名、SOP 的 description 里留着上一代 CI 的脚本名、
# daemon API 代理的注释里写了本机安全软件的内部 bundle id。三次都是「正文改干净了、边角没改」。
#
# 用法：
#   lab/scripts/check-public-hygiene.sh            扫全部被跟踪文件
#   lab/scripts/check-public-hygiene.sh --staged   只扫已 staged 的（给 pre-commit 用）
#
# 有意保留的提及（例如「答 jenkins/verify 说明群上还绑着旧版本」这种版本判据）
# 在同一行加标记 `hygiene-allow: <理由>` 即可放行。标记必须带理由，否则它退化成一键忽略。
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
STAGED=0
[ "${1:-}" = "--staged" ] && STAGED=1

# 扫描器自己必须排除：它的规则表里就写着这些字面量，否则第一条命中永远是它自己。
SELF_EXCLUDE='lab/scripts/check-public-hygiene.sh|lab/sop/build-sop.js'

if [ "$STAGED" = 1 ]; then
  FILES=$(git -C "$REPO" diff --cached --name-only --diff-filter=ACM)
else
  FILES=$(git -C "$REPO" ls-files)
fi

# 第一道检查：.instructor/ 整个目录都不该进版本库，所以这里查的是**路径**不是内容。
# 它放的是讲师版答案（Open Question 参考裁定、缺陷确切行号、红灯分支意图、未覆盖点
# 分类答案）与含内部单号的退役脚本备份，靠 .gitignore 排除。会走到这一步只有两种
# 可能：有人 git add -f，或者 .gitignore 被改坏了——两种都必须当场拦下。
# 放在内容规则之前，因为这种情况下「哪一行有内部字样」已经不是重点了。
LEAKED=$(printf '%s\n' "$FILES" | grep -E '^\.instructor(/|$)' || true)
if [ -n "$LEAKED" ]; then
  echo "✗ .instructor/ 下的文件被纳入了版本控制：" >&2
  printf '%s\n' "$LEAKED" | sed 's/^/    /' >&2
  cat >&2 <<'EOF'

    靶仓是 PUBLIC、学员会 clone。这个目录里是讲师版答案与含内部单号的退役脚本备份，
    提交进公开仓的历史就永久可检索、删不掉（本仓已因 PR #7 / 2e23983 泄过一次，
    而改历史与关规则集都是被禁止的处置方式）。
    处置：git rm --cached <路径>，并确认 .gitignore 里有 /.instructor/。
    不要用 git add -f，也不要把 .instructor/ 加进本脚本的 SELF_EXCLUDE。
EOF
  exit 1
fi

# 规则：name<TAB>ERE。用 ERE 而不是 Perl 正则，因为要交给 grep -E，
# 而 grep -E 在 macOS(BSD) 与 GNU 下的行为差异最小的就是这一档。
RULES='内部协作平台 CLI 调用	\ba1[[:space:]]+(repo|project|ci|quality|workitem)\b
内部工单系统名	[Aa]one
已退役的 CI 口径	[Jj]enkins
MR 术语（应为 PR）	\bMR\b
内部评审规则码	approver_number
机器用户名硬编码	/Users/[A-Za-z0-9_.-]+/
8 位以上裸单号	(^|[^A-Za-z0-9./_-])[0-9]{8,}([^A-Za-z0-9./_-]|$)
GitHub 令牌字面量	github_pat_[A-Za-z0-9_]{20,}|ghp_[A-Za-z0-9]{20,}
Qoder 令牌字面量	pt-[A-Za-z0-9_-]{20,}
通用高熵凭据赋值	(password|passwd|secret|api_?key|token)[[:space:]]*[:=][[:space:]]*["'"'"'][A-Za-z0-9/+_-]{16,}["'"'"']
员工工号	工号[[:space:]]*[0-9]{5,}
内部域名	[A-Za-z0-9.-]+\.(alibaba-inc|aliyun-inc|taobao)\.com'

HITS=0
CHECKED=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in
    *.png|*.jpg|*.jpeg|*.gif|*.ico|*.jar|*.zip|*.war|*.gz|*.pdf|*.woff*|*.ttf) continue ;;
  esac
  echo "$f" | grep -Eq "$SELF_EXCLUDE" && continue
  [ -f "$REPO/$f" ] || continue
  CHECKED=$((CHECKED + 1))
  while IFS=$'\t' read -r name re; do
    [ -n "$re" ] || continue
    # 逐行扫，带行号；含放行标记的行跳过。
    OUT=$(grep -En "$re" "$REPO/$f" 2>/dev/null | grep -v 'hygiene-allow:')
    [ -n "$OUT" ] || continue
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      HITS=$((HITS + 1))
      printf '%s:%s\n    规则: %s\n    %s\n' "$f" "${line%%:*}" "$name" "$(printf '%s' "${line#*:}" | cut -c1-200)"
    done <<< "$OUT"
  done <<< "$RULES"
done <<< "$FILES"

echo
echo "已扫 ${CHECKED} 个文件，命中 ${HITS} 处。"
if [ "$HITS" = 0 ]; then
  echo "ok 没有内部口径或凭据字面量泄漏。"
  exit 0
fi
cat <<'EOF'

处置口径：
  - 真泄漏（内部平台名、内部单号、机器用户名、凭据）：改掉，不要只加放行标记。
    凭据一律立即轮换——公开仓里提交过的东西，删掉文件不等于删掉内容。
  - 有意保留的提及（版本判据、迁移说明）：在同一行加 `hygiene-allow: <理由>`。
  - 规则表本身命中的文件已在 SELF_EXCLUDE 里；不要把别的文件加进去当省事手段。
EOF
exit 1
