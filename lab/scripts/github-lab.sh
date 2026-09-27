#!/bin/bash
# GitHub capability wrapper for the digital-employee lab.
#
# Wakers call THIS, never gh/git-with-credentials directly. The fine-grained PAT
# is read from a file outside the repository on every invocation and is never
# printed, never passed in argv, and never written into .git/config.
#
# Why git push goes through here too: the machine's own git credential helper
# holds the repo owner's OAuth token, which has admin rights. A Waker pushing with
# that helper would silently escalate past the least-privilege design, so every git
# network operation here clears the helper and authenticates through a GIT_ASKPASS
# shim that reads the scoped PAT from the file.
#
# Environment overrides:
#   GITHUB_WAKER_TOKEN_FILE   PAT 文件（默认 ~/.config/ai-devops-lab/github-waker-token）
#   LAB_GH_REPO               owner/repo（默认 ganyu21/ai_devops_demo）
#   LAB_REPO                  本地仓库根（默认从本脚本位置反推两级，即仓库根）
#
# Usage:
#   github-lab.sh issue <n>                        issue 正文、标签、状态
#   github-lab.sh issue-comment <n> <file>         用文件内容发评论（避开引号换行守卫）
#   github-lab.sh pr-create <branch> <tf> <bf>     开 PR（标题与正文都走文件）
#   github-lab.sh pr-status <n>                    合并资格 + 未解决评审线程 + 由脚本推导的阻塞原因
#   github-lab.sh pr-reply <threadId> <file>       回复一条评审线程（裁定意见写在文件里）
#   github-lab.sh pr-resolve <threadId> <reason>   把一条评审线程标记为已解决（理由会先回帖留痕）
#   github-lab.sh pr-merge <n> --yes --approved-by <出处> [--method merge|squash|rebase]
#                                  合并（三道闸：显式 --yes、G2 裁定出处、现场复核 CLEAN 且 0 条未解决线程）
#   github-lab.sh commit-status <sha>              该 SHA 上的 commit status 与 check run（两个都查）
#   github-lab.sh ruleset                          main 的规则集（治理控制现状）
#   github-lab.sh push <branch>                    推分支（用 PAT，不用机器上的仓主凭据）
#   github-lab.sh fetch                            取远端引用
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# token 绝不放进仓库，也不进 argv。
TOKEN_FILE="${GITHUB_WAKER_TOKEN_FILE:-$HOME/.config/ai-devops-lab/github-waker-token}"
ASKPASS="${GITHUB_WAKER_ASKPASS:-$HERE/gh-askpass.sh}"
REPO="${LAB_GH_REPO:-ganyu21/ai_devops_demo}"
REPO_ROOT="${LAB_REPO:-$(cd "$HERE/../.." && pwd)}"
GH="${GH_BIN:-/opt/homebrew/bin/gh}"

if [ ! -f "$TOKEN_FILE" ]; then
  echo '{"error":"NO_TOKEN","detail":"PAT 文件不存在，用 GITHUB_WAKER_TOKEN_FILE 指定或先装好凭据"}'
  exit 2
fi
# 用 rev-parse 判，不要用 [ -d .git ]：linked worktree 里的 .git 是**文件**不是目录，
# 按目录判会在 worktree 里恒失败，报一个看起来像路径写错的 NO_REPO。
if ! git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  echo "{\"error\":\"NO_REPO\",\"detail\":\"$REPO_ROOT 不是 git 仓库或 worktree，用 LAB_REPO 指定\"}"
  exit 2
fi

# GH_TOKEN 走环境变量：ps 里看不到，shell 历史里也留不下。
GH_TOKEN="$(cat "$TOKEN_FILE")"
export GH_TOKEN

api() { "$GH" api "$@"; }

cmd="${1:-}"; shift || true

case "$cmd" in
  issue)
    n="${1:?issue 号}"
    api "repos/$REPO/issues/$n" \
      --jq '{number,title,state,labels:[.labels[].name],comments,created_at,body}'
    ;;

  issue-comment)
    n="${1:?issue 号}"; f="${2:?正文文件}"
    [ -f "$f" ] || { echo '{"error":"NO_FILE","detail":"正文文件不存在"}'; exit 2; }
    # 正文走文件而不是命令行参数：既避开 toolGuard 的引号换行规则，也避开 shell 转义。
    api "repos/$REPO/issues/$n/comments" -X POST -F body=@"$f" --jq '{id,html_url,created_at}'
    ;;

  pr-create)
    branch="${1:?分支名}"; tf="${2:?标题文件}"; bf="${3:?正文文件}"
    [ -f "$tf" ] && [ -f "$bf" ] || { echo '{"error":"NO_FILE","detail":"标题或正文文件不存在"}'; exit 2; }
    api "repos/$REPO/pulls" -X POST \
      -f title="$(cat "$tf")" -F body=@"$bf" -f head="$branch" -f base=main \
      --jq '{number,html_url,state,head:.head.sha}'
    ;;

  pr-status)
    n="${1:?PR 号}"
    # 合并资格的唯一事实源。
    #
    # 为什么不止报 mergeStateStatus：BLOCKED 只说「合不了」，不说「为什么合不了」。
    # 首轮交付就栽在这里——DevOps 看到 BLOCKED、看到 reviewDecision 为空，
    # 就把原因写成「需要至少 1 名有权限的评审人」并把 unresolvedReviewThreads 填了 false。
    # 实测真实原因是 required_review_thread_resolution：7 条 qoderai 的评审线程一条都没解决，
    # 而 required_approving_review_count 当时已经是 0。
    # 所以这里把每一项规则的实况都拉出来，并**由工具**推出 blockingReasons，
    # 不给调用方留一个「凭印象填原因」的空档。
    case "$n" in ''|*[!0-9]*) echo '{"error":"BAD_PR_NUMBER","detail":"PR 号必须是纯数字"}'; exit 2 ;; esac
    owner="${REPO%%/*}"; name="${REPO##*/}"
    # gh pr view --json 没有 reviewThreads 这个字段（实测报 Unknown JSON field），只能走 GraphQL。
    # 号码已在上面校验为纯数字，直接内插；owner/name 来自本脚本自己的配置，不是外部输入。
    #
    # statusCheckRollup 本身是个 OBJECT（字段是 state 与 contexts），真正的联合类型在它下面的
    # contexts.nodes —— CheckRun | StatusContext。所以片段要 spread 在 contexts.nodes 里，
    # 写在 statusCheckRollup 上会报 cannotSpreadFragment，而直接写 context/name/conclusion
    # 会报 undefinedField；两种错都会让整个查询失败，一条数据都拿不到。
    #
    # 不查 branchProtectionRules：那需要 Administration 权限，而数字员工那张 PAT 没有。
    # 治理配置的现状属于操作员视角（见 ruleset 子命令），不该混进 Waker 的合并资格判据里。
    "$GH" api graphql -f query="query{
      repository(owner:\"$owner\",name:\"$name\"){
        pullRequest(number:$n){
          number mergeable mergeStateStatus reviewDecision headRefOid
          reviewThreads(first:100){nodes{
            id isResolved isOutdated path line
            comments(first:1){nodes{author{login} body}}
          }}
          statusCheckRollup{
            state
            contexts(first:50){nodes{
              ... on CheckRun { name conclusion status }
              ... on StatusContext { context state }
            }}
          }
          reviews(first:50){nodes{author{login} state}}
        }
      }
    }" --jq '
      .data.repository as $r | $r.pullRequest as $pr
      | ($pr.reviewThreads.nodes // []) as $th
      | ([ $th[] | select(.isResolved==false) ]) as $unres
      # CheckRun 与 StatusContext 用的是两套词表（conclusion: SUCCESS/FAILURE/CANCELLED/SKIPPED/…
      # 对 state: SUCCESS/FAILURE/PENDING/EXPECTED），所以每条都带上 kind 说明它来自哪一套，
      # 并把两者归一到同一个 verdict 上再分类。
      #
      # 分类必须**穷尽**：原先只列了「坏」与「还没结论」两档，于是 CANCELLED / SKIPPED /
      # STALE / NEUTRAL / STARTUP_FAILURE 会掉进缝里被当成「没问题」静默放行。
      # 一条必需检查报 SKIPPED 意味着它根本没跑，规则集不会因此满足——静默放行比标错更糟。
      | ([ $pr.statusCheckRollup.contexts.nodes[]?
           | (if .name then "checkRun" else "statusContext" end) as $kind
           | (.context // .name) as $ctx
           | (.conclusion // .state // null) as $raw
           | ($raw // (if $kind=="checkRun" then (.status // "") else "" end)) as $v
           | { context: $ctx, kind: $kind, state: $raw, runStatus: (.status // null),
               verdict: (
                 if $v=="SUCCESS" or $v=="EXPECTED" then "pass"
                 elif $v=="FAILURE" or $v=="ERROR" or $v=="TIMED_OUT" or $v=="ACTION_REQUIRED"
                      or $v=="CANCELLED" or $v=="STARTUP_FAILURE" then "fail"
                 elif $v=="PENDING" or $v=="QUEUED" or $v=="IN_PROGRESS" or $v=="WAITING"
                      or $v=="" or $v==null then "pending"
                 elif $v=="SKIPPED" or $v=="STALE" or $v=="NEUTRAL" then "notrun"
                 else "unknown" end) } ]) as $checks
      | ([ $checks[] | select(.verdict=="fail") | "\(.context)=\(.state // .runStatus)" ]) as $badchecks
      | ([ $checks[] | select(.verdict=="pending") | .context ]) as $noresult
      | ([ $checks[] | select(.verdict=="notrun" or .verdict=="unknown") | "\(.context)=\(.state // .runStatus // "?")" ]) as $notrun
      | ([ $pr.reviews.nodes[]? | select(.state=="APPROVED") | .author.login ]) as $approvals
      | {
          number: $pr.number,
          headSha: $pr.headRefOid,
          mergeable: $pr.mergeable,
          mergeStateStatus: $pr.mergeStateStatus,
          reviewDecision: $pr.reviewDecision,
          rollupState: $pr.statusCheckRollup.state,
          checks: $checks,
          reviewsByState: (reduce ($pr.reviews.nodes[]?) as $x ({}; .[$x.state] += [$x.author.login])),
          approvedBy: $approvals,
          reviewThreads: {
            total: ($th|length),
            unresolved: ($unres|length),
            unresolvedDetail: [ $unres[] | {
              threadId: .id, path, line, outdated: .isOutdated,
              author: (.comments.nodes[0].author.login // "?"),
              excerpt: ((.comments.nodes[0].body // "") | gsub("[\\n\\r]+"; " ") | .[0:240])
            } ]
          },
          blockingReasons: (
            (if ($unres|length) > 0 then ["required_review_thread_resolution: \($unres|length) 条评审线程未解决"] else [] end)
            + (if ($badchecks|length) > 0 then ["必需状态检查未过: \($badchecks|join(", "))"] else [] end)
            + (if ($noresult|length) > 0 then ["状态检查尚无结论: \($noresult|join(", "))"] else [] end)
            + (if ($notrun|length) > 0 then ["状态检查没有给出可用结论（SKIPPED/STALE/NEUTRAL 或本脚本不认得的值）: \($notrun|join(", "))——必需检查报这些值时规则集不会被满足，要人工核对"] else [] end)
          ),
          # 「没有任何 APPROVED 审查」不放进 blockingReasons：它是不是阻塞取决于规则集里的
          # required_approving_review_count，而那张 PAT 没有 Administration 权限、读不到这个值。
          # 实测证据：PR #19 在 0 条审查、0 条未解决线程时 mergeStateStatus 是 UNSTABLE 而不是
          # BLOCKED，说明该值为 0 时缺审查并不阻塞。把它断言成阻塞原因，就等于重犯首轮那个错——
          # 用一个读不到的规则去解释 BLOCKED。所以单列一项，并写清它成立的前提。
          possibleAdditionalBlockers: (
            if ($approvals|length) == 0 then
              ["没有任何 APPROVED 审查（reviewDecision=\($pr.reviewDecision // "空")）。"
               + "仅当规则集要求 required_approving_review_count ≥ 1 时这一项才是阻塞原因；"
               + "该值需要 Administration 权限才能读到，本脚本读不到，请用 ruleset 子命令或 PR 页面核对"]
            else [] end
          ),
          note: "blockingReasons 由本脚本从 GraphQL 实况推导，不要用自己的印象覆盖它。若它为空而 mergeStateStatus 仍是 BLOCKED，说明还有一条本脚本没覆盖的规则（例如 require_extra_approval_for_unattributed_changes）——此时如实报告「原因未定位，需人工在 PR 页面核对」，不要猜。"
        }'
    ;;

  pr-reply)
    # 缺参数一律输出结构化 JSON 而不是 bash 的 ${VAR:?} 原文：
    # 调用方（数字员工）按 JSON 解析，一行 bash 报错会让它去猜错在哪。
    tid="${1:-}"; bf="${2:-}"
    [ -n "$tid" ] || { echo '{"error":"NO_THREAD_ID","detail":"缺评审线程 id，取法：pr-status <n> 的 reviewThreads.unresolvedDetail[].threadId"}'; exit 2; }
    [ -n "$bf" ]  || { echo '{"error":"NO_FILE","detail":"缺正文文件。长内容与多行正文一律走文件，不要塞进 argv"}'; exit 2; }
    [ -f "$bf" ] || { echo '{"error":"NO_FILE","detail":"正文文件不存在。长内容与多行正文一律走文件，不要塞进 argv"}'; exit 2; }
    # 用 GraphQL 而不是 REST 的 pulls/<n>/comments/<id>/replies：REST 那条要的是 database id，
    # 而 pr-status 从 GraphQL 拿到的是 node id（PRRT_…），两者不通用。
    "$GH" api graphql -F threadId="$tid" -F body=@"$bf" -f query='
      mutation($threadId:ID!, $body:String!){
        addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$threadId, body:$body}){
          comment{ url createdAt }
        }
      }' --jq '.data.addPullRequestReviewThreadReply.comment // {error:"NO_REPLY_CREATED"}'
    ;;

  pr-resolve)
    tid="${1:-}"; reason="${2:-}"
    [ -n "$tid" ] || { echo '{"error":"NO_THREAD_ID","detail":"缺评审线程 id，取法：pr-status <n> 的 reviewThreads.unresolvedDetail[].threadId"}'; exit 2; }
    # 理由必填，不是形式要求：resolve 之后线程会折叠，后来的人只看得到「已解决」。
    # 不留理由就等于把裁定过程丢掉，下一次运行的人无法判断这个 resolve 是有依据的还是图省事。
    [ -n "$reason" ] || { echo '{"error":"NO_REASON","detail":"缺裁定理由。resolve 是个不可见的动作，不留理由就等于把裁定过程丢掉"}'; exit 2; }
    # 先把理由回帖留痕，再 resolve。顺序不能反：resolve 之后线程会折叠，
    # 后来的人只看得到「已解决」，看不到当初为什么判它不阻塞。
    tmp="$(mktemp -t prresolve.XXXXXX)" || { echo '{"error":"TMPFILE"}'; exit 2; }
    chmod 600 "$tmp"
    printf '裁定：%s\n\n（本线程随后被标记为已解决。理由先留在这里，是因为 resolve 之后线程会折叠，后来的人只看得到「已解决」而看不到当初的判断依据。）\n' "$reason" > "$tmp"
    "$HERE/$(basename "${BASH_SOURCE[0]}")" pr-reply "$tid" "$tmp" >/dev/null 2>&1
    replied=$?
    rm -f "$tmp"
    if [ "$replied" != 0 ]; then
      echo '{"error":"REPLY_FAILED","detail":"裁定理由没能回帖成功，因此不执行 resolve——不留痕的 resolve 等于把判断依据丢掉。先修好回帖再重试。"}'
      exit 3
    fi
    "$GH" api graphql -F threadId="$tid" -f query='
      mutation($threadId:ID!){
        resolveReviewThread(input:{threadId:$threadId}){
          thread{ id isResolved path line }
        }
      }' --jq '.data.resolveReviewThread.thread // {error:"NOT_RESOLVED"}'
    ;;

  commit-status|checks)
    sha="${1:?commit sha}"
    # 两个端点都要查：外部 CI 的状态回写桥产生的是 legacy commit status，
    # 而 GitHub Actions 产生的是 check run。只查 statuses 会看不见 Actions 的结论，
    # 然后误判成「回写没成功」并报一个假阻塞——这是把门禁搬到 Actions 时最容易踩的一脚。
    api "repos/$REPO/commits/$sha/statuses" \
      --jq '{statuses:[.[]|{context,state,description}]}'
    api "repos/$REPO/commits/$sha/check-runs" \
      --jq '{checkRuns:[.check_runs[]|{name,status,conclusion}]}'
    ;;

  pr-merge)
    # 合并是整条交付里唯一不可逆的一步，所以把纪律做进工具，而不是指望调用方自觉。
    # 三道闸，缺一条就拒绝执行：
    #   1. --yes               显式表明这是有意为之，不是脚本跑到这一行顺带做的
    #   2. --approved-by       G2 裁定的出处（谁、在哪条群消息/issue 评论里批的）。
    #                          不留出处的合并等于把「人批准过」这个前提丢掉，事后无从追溯。
    #   3. 现场复核 mergeStateStatus 必须是 CLEAN 且未解决评审线程为 0
    #      —— 用调用时那一刻的实况，不用调用方传进来的说法。
    n=""; yes=0; method="merge"; approved_by=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --yes) yes=1; shift ;;
        --method) method="${2:?--method 需要 merge|squash|rebase}"; shift 2 ;;
        --approved-by) approved_by="${2:?--approved-by 需要填 G2 裁定的出处}"; shift 2 ;;
        -*) echo "{\"error\":\"BAD_FLAG\",\"detail\":\"不认得的参数：$1（可用 --yes / --method / --approved-by）\"}"; exit 2 ;;
        *) [ -z "$n" ] && n="$1" && shift || { echo "{\"error\":\"BAD_ARGS\",\"detail\":\"多余的位置参数：$1\"}"; exit 2; } ;;
      esac
    done
    case "$n" in ''|*[!0-9]*) echo '{"error":"BAD_PR_NUMBER","detail":"PR 号必须是纯数字"}'; exit 2 ;; esac
    [ "$yes" = 1 ] || { echo '{"error":"NO_CONFIRM","detail":"合并不可逆，必须显式带 --yes"}'; exit 2; }
    [ -n "$approved_by" ] || { echo '{"error":"NO_APPROVAL_REF","detail":"必须用 --approved-by 填 G2 裁定的出处（谁批的、在哪条消息或评论里），否则事后无从追溯这个合并的前提"}'; exit 2; }
    case "$method" in merge|squash|rebase) ;; *) echo '{"error":"BAD_METHOD","detail":"--method 只能是 merge|squash|rebase"}'; exit 2 ;; esac

    self="$HERE/$(basename "${BASH_SOURCE[0]}")"
    verdict="$("$self" pr-status "$n" 2>/dev/null)"
    gate="$(printf '%s' "$verdict" | python3 -c "
import json,sys
try: d=json.load(sys.stdin)
except Exception: print('PARSE_FAIL'); raise SystemExit
ms=d.get('mergeStateStatus'); un=(d.get('reviewThreads') or {}).get('unresolved')
sha=(d.get('headSha') or '')
print('%s|%s|%s' % (ms, un, sha))
" 2>/dev/null)"
    case "$gate" in
      CLEAN\|0\|*) ;;
      PARSE_FAIL) echo '{"error":"STATUS_UNREADABLE","detail":"拿不到 pr-status 的结论，因此不合并——看不清就不动，别赌"}'; exit 3 ;;
      *)
        printf '{"error":"NOT_CLEAN","detail":"现场复核不通过：mergeStateStatus/未解决线程数 = %s。合并只在 CLEAN 且 0 条未解决线程时执行。先看 pr-status %s 的 blockingReasons，不要绕过这一条。"}\n' "$gate" "$n"
        exit 3 ;;
    esac
    "$GH" pr merge "$n" --repo "$REPO" --"$method" 2>&1 | tail -5
    rc=$?
    # 合并成功不等于 main 上真的有那个提交。必须回读 origin/main，
    # 否则「已交付」就是一个没有证据的断言——这正是首轮交付要防的那个错。
    if [ "$rc" = 0 ]; then
      "$GH" pr view "$n" --repo "$REPO" --json state,mergedAt,mergeCommit         --jq '{number:'"$n"',state,mergedAt,mergeCommit:.mergeCommit.oid,approvedBy:"'"$approved_by"'",method:"'"$method"'"}'
    fi
    ;;

  ruleset)
    api "repos/$REPO/rulesets" --jq '[.[]|{id,name,enforcement}]'
    ;;

  push)
    branch="${1:?分支名}"
    [ -x "$ASKPASS" ] || { echo '{"error":"NO_ASKPASS","detail":"gh-askpass.sh 不存在或不可执行"}'; exit 2; }
    # credential.helper= 置空是关键：不清掉就会用机器上那张有 admin 权限的仓主凭据。
    # 环境变量必须写在 git **前面**：写在后面会被当成 git 的子命令（'env' is not a git command）。
    GIT_TERMINAL_PROMPT=0 GIT_ASKPASS="$ASKPASS" \
      git -C "$REPO_ROOT" -c credential.helper= \
      push "https://github.com/$REPO.git" "refs/heads/$branch:refs/heads/$branch" 2>&1
    ;;

  fetch)
    [ -x "$ASKPASS" ] || { echo '{"error":"NO_ASKPASS","detail":"gh-askpass.sh 不存在或不可执行"}'; exit 2; }
    GIT_TERMINAL_PROMPT=0 GIT_ASKPASS="$ASKPASS" \
      git -C "$REPO_ROOT" -c credential.helper= \
      fetch "https://github.com/$REPO.git" '+refs/heads/*:refs/remotes/origin/*' 2>&1
    ;;

  ""|-h|--help|help)
    sed -n '2,32p' "${BASH_SOURCE[0]}"
    ;;

  *)
    echo "{\"error\":\"UNKNOWN_COMMAND\",\"detail\":\"$cmd\"}"
    exit 2
    ;;
esac
