#!/bin/bash
# 已认证的 daemon API 代理。
#
# 为什么需要它：daemon 的 /api/* 要 frontend access session cookie，而那个 cookie 是 httpOnly 的，
# curl 直接调会 401 FRONTEND_AUTH_REQUIRED。引导方式是带 .auth/token 作 Bearer，再加
# X-QoderWake-Frontend-Session-Client: cli，POST /api/frontend-auth/session/bootstrap 就会下发 cookie。
# 有些操作 CLI 表达不了（例如把 waker 的 mcpServers 清空——CLI 的校验要求非空 map），只能走 API。
#
# 用法：
#   lab/scripts/qw-api.sh <METHOD> <path> [json-body]      path 以 /api 开头
#   lab/scripts/qw-api.sh GET /api/agents/<wakerId>
#   lab/scripts/qw-api.sh PATCH /api/agents/<wakerId> '{"mcpServers":{}}'
#   lab/scripts/qw-api.sh PATCH /api/workflows/<uuid> @/tmp/body.json    # 大载荷用 @文件，别塞进 argv
#
# 安全：token 只经 stdin 传给 curl（-K -），不进 argv；cookie jar 与 body 临时文件都是 0600，退出即删。
set -uo pipefail

# shellcheck source=../env.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/env.sh"

QW_HOME="${QW_HOME:-$HOME/.qoderwake}"
TOKEN_FILE="$QW_HOME/.auth/token"
API="http://127.0.0.1:${QW_DAEMON_PORT}"

die() { echo "x ${1}" >&2; exit 1; }

METHOD="${1:-}"; PATHP="${2:-}"; BODY="${3:-}"
[ -n "$METHOD" ] && [ -n "$PATHP" ] || die "用法：qw-api.sh <METHOD> <path> [json-body]"
case "$PATHP" in
  /api/*) ;;
  *) die "path 必须以 /api 开头：${PATHP}" ;;
esac

[ -f "$TOKEN_FILE" ] || die "缺少 ${TOKEN_FILE}，daemon 可能没登录过"
lab_daemon_up || die "daemon 未运行（端口 ${QW_DAEMON_PORT} 没在听），先跑 lab/scripts/qw-up.sh"

JAR=$(mktemp -t qwapi.XXXXXX) || die "无法创建临时 cookie jar"
BOOT=$(mktemp -t qwapiboot.XXXXXX) || die "无法创建临时文件"
REQ=$(mktemp -t qwapireq.XXXXXX) || die "无法创建临时文件"
chmod 600 "$JAR" "$BOOT" "$REQ"
cleanup() { rm -f "$JAR" "$BOOT" "$REQ"; }
trap cleanup EXIT INT TERM

# .auth/token 上可能被本机安全软件挂着「按访问云查」的扩展属性，
# 那次查会偶发地把这次读挡下来（EPERM，不是 EACCES）。真撞上时 Bearer 头会是空的，
# daemon 回一个 401 LOCAL_CLI_AUTH_REQUIRED ——看着像认证坏了，其实只是没读到文件。
read_token() {
  local n tk
  for n in 1 2 3 4 5; do
    tk=$(tr -d '\n' < "$TOKEN_FILE" 2>/dev/null) && [ -n "$tk" ] && { printf '%s' "$tk"; return 0; }
    sleep 1
  done
  return 1
}

TOKEN=$(read_token) || die "读不到 ${TOKEN_FILE}（连续 5 次）。该文件带 EDR 云查扩展属性，可能正被按访问扫描挡住；稍等几秒重试，别去动登录态。"

boot=$(printf '%s' "$TOKEN" \
  | { read -r tk; printf 'header = "Authorization: Bearer %s"\nheader = "X-QoderWake-Frontend-Session-Client: cli"\n' "$tk"; } \
  | curl -s -o "$BOOT" -w '%{http_code}' -K - \
      -X POST "$API/api/frontend-auth/session/bootstrap" \
      -H 'Content-Type: application/json' -d '{}' -c "$JAR" 2>/dev/null)
[ "$boot" = "200" ] || die "session 引导失败 HTTP=${boot}：$(head -c 200 "$BOOT")"
grep -q '"authenticated":true' "$BOOT" || die "引导成功但未认证：$(head -c 200 "$BOOT")"
[ -s "$JAR" ] || die "没拿到 cookie"

if [ -n "$BODY" ]; then
  case "$BODY" in
    @*)
      # 大载荷从文件走。注册 workflow 的 body 里带着 55KB 的脚本，满是反引号、引号和 $，
      # 当 shell 参数传必被破坏。
      SRC="${BODY#@}"
      [ -f "$SRC" ] || die "body 文件不存在：${SRC}"
      resp=$(curl -s -w '\n%{http_code}' -X "$METHOD" "$API$PATHP" \
        -H 'Content-Type: application/json' -b "$JAR" --data-binary @"$SRC" 2>/dev/null)
      ;;
    *)
      printf '%s' "$BODY" > "$REQ"
      resp=$(curl -s -w '\n%{http_code}' -X "$METHOD" "$API$PATHP" \
        -H 'Content-Type: application/json' -b "$JAR" --data-binary @"$REQ" 2>/dev/null)
      ;;
  esac
else
  resp=$(curl -s -w '\n%{http_code}' -X "$METHOD" "$API$PATHP" \
    -H 'Content-Type: application/json' -b "$JAR" 2>/dev/null)
fi

code=$(printf '%s' "$resp" | tail -1)
printf '%s' "$resp" | sed '$d'
echo
[ "$code" = "200" ] || [ "$code" = "201" ] || [ "$code" = "202" ] || exit 1
