#!/bin/bash
# GIT_ASKPASS shim。git 用它取 https 凭据，所以 token 只在这里从文件读出来，
# 不出现在任何进程的 argv 里、不进 shell 历史、不写进 .git/config。
# 本脚本读的 token 文件在 Waker 的 fileGuard 黑名单上——脚本本身可以公开，token 不行。
prompt="${1:-}"
token_file="${GITHUB_WAKER_TOKEN_FILE:-$HOME/.config/ai-devops-lab/github-waker-token}"
case "$prompt" in
  *Username*|*username*) printf 'x-access-token\n' ;;
  *) cat "$token_file" ;;
esac
