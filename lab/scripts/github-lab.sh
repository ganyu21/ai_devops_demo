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
#   github-lab.sh pr-status <n>                    合并资格 + 每个必需状态检查
#   github-lab.sh commit-status <sha>              该 SHA 上的全部 context 与 state
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
if [ ! -d "$REPO_ROOT/.git" ]; then
  echo "{\"error\":\"NO_REPO\",\"detail\":\"$REPO_ROOT 不是 git 仓库，用 LAB_REPO 指定\"}"
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
    # 合并资格的唯一事实源。必需状态检查缺状态时 mergeStateStatus=BLOCKED。
    "$GH" pr view "$n" --repo "$REPO" --json number,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup \
      --jq '{number,mergeable,mergeStateStatus,reviewDecision,checks:[.statusCheckRollup[]?|{context:(.context//.name),state:(.state//.conclusion)}]}'
    ;;

  commit-status)
    sha="${1:?commit sha}"
    api "repos/$REPO/commits/$sha/statuses" --jq '[.[]|{context,state,description,created_at}]'
    ;;

  ruleset)
    api "repos/$REPO/rulesets" --jq '[.[]|{id,name,enforcement}]'
    ;;

  push)
    branch="${1:?分支名}"
    [ -x "$ASKPASS" ] || { echo '{"error":"NO_ASKPASS","detail":"gh-askpass.sh 不存在或不可执行"}'; exit 2; }
    # credential.helper= 置空是关键：不清掉就会用机器上那张有 admin 权限的仓主凭据。
    git -C "$REPO_ROOT" -c credential.helper= \
      env GIT_TERMINAL_PROMPT=0 GIT_ASKPASS="$ASKPASS" \
      push "https://github.com/$REPO.git" "refs/heads/$branch:refs/heads/$branch" 2>&1
    ;;

  fetch)
    [ -x "$ASKPASS" ] || { echo '{"error":"NO_ASKPASS","detail":"gh-askpass.sh 不存在或不可执行"}'; exit 2; }
    git -C "$REPO_ROOT" -c credential.helper= \
      env GIT_TERMINAL_PROMPT=0 GIT_ASKPASS="$ASKPASS" \
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
