#!/bin/bash
# 快照 QoderWake 演练环境。动机是一次真实事故：store 被误删后，角色配置、流程定义、
# 运行历史与全部 Memory 一起消失，只能靠会话转录考古重建。
#
# 两层快照，缺一不可：
#   1. waker export --full  → 官方可恢复格式，含 memory/permissions/triggers/connectors
#   2. sqlite .backup       → 覆盖 global scope 的数据（不属于任何单个 Waker，waker export 拿不到）
#
# **仓内资产不在快照范围里**：lab/ 下的角色描述、SOP 正文、脚本都由 git 版本化，
# 备份它们等于制造第二份会漂移的副本。这里只备份 git 管不到的东西。
#
# 用法：lab/scripts/qw-backup.sh [标签]     默认标签 manual
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../env.sh
. "$HERE/../env.sh"

REPO="$(cd "$HERE/../.." && pwd)"
DB="$HOME/.qoderwake/data/store/qoderwake.sqlite"
ROOT="${LAB_BACKUP_ROOT:-$HOME/qoderwake-backups}"
# ROOT 来自环境变量，而下面要用它拼 rm -rf。设成 / 或 ~/Documents 就会删掉别人的数据，
# 所以先把它钉死：必须是绝对路径、且不是 / 或家目录本身。
# 空串那一支实际上到不了——${VAR:-default} 对「未设置」和「设为空」都会取默认值
# （已实测：LAB_BACKUP_ROOT="" 会正常备份到默认目录）。留着是因为默认值一旦改动它就成了活路径，
# 而一条走不到的分支比一条走得到却没防的路径便宜得多。
case "$ROOT" in
  "") echo "x LAB_BACKUP_ROOT 展开后是空串，拒绝继续（否则轮转的 rm -rf 会落到 / 上）" >&2; exit 1 ;;
  /*) ;;
  *)  echo "x LAB_BACKUP_ROOT 必须是绝对路径，当前是：$ROOT" >&2; exit 1 ;;
esac
# 去掉尾部斜杠后再比对，否则带尾斜杠与不带尾斜杠的同一个目录判不出来  # hygiene-allow: 这里的示例路径是通用占位，不是真实机器用户名
ROOT_NOSLASH="${ROOT%/}"
case "$ROOT_NOSLASH" in
  ""|"$HOME"|"$HOME/") echo "x LAB_BACKUP_ROOT 不能是文件系统根或家目录本身：$ROOT" >&2; exit 1 ;;
esac
ROOT="$ROOT_NOSLASH"
KEEP="${LAB_BACKUP_KEEP:-10}"
STAMP="$(date +%Y%m%d-%H%M%S)"
TAG="${1:-manual}"
DEST="$ROOT/$STAMP-$TAG"

[ -f "$DB" ] || { echo "x store 不存在：$DB" >&2; exit 1; }
mkdir -p "$DEST/wakers"

# --- 1. Waker 全量导出 ---
# 不加 --include-secrets：它会把连接器里的 token 明文写进 zip。
# 本演练的凭据由 lab/scripts/github-lab.sh 内部持有，Waker 连接器无需携带密钥。
if "$QW" waker export --full --out "$DEST/wakers/all-wakers.zip" >/dev/null 2>&1; then
  echo "waker export: $(du -h "$DEST/wakers/all-wakers.zip" | cut -f1)"
else
  # 一次性全量导出失败时退回逐个导出，至少保住角色配置
  for wid in $(sqlite3 "$DB" "select agent_id from agents;"); do
    "$QW" waker export --waker-id "$wid" --out "$DEST/wakers/$wid.zip" >/dev/null 2>&1 \
      && echo "waker export $wid: ok" || echo "waker export $wid: FAILED" >&2
  done
fi

# --- 2. sqlite 在线备份 ---
# 必须用 .backup 而不是 cp：daemon 在跑，直接复制主库会漏掉 -wal 里的已提交事务。
sqlite3 "$DB" ".backup '$DEST/qoderwake.sqlite'"
echo "sqlite backup: $(du -h "$DEST/qoderwake.sqlite" | cut -f1)"

# --- 3. 清单：记录此刻的关键标识，恢复后要靠它核对 ---
# token 只记指纹不记值：备份目录里存一份可用凭据等于把泄漏面从 1 个扩到 11 个（KEEP=10）。
# 真丢了就轮换，那本来就是唯一正确的处置。
{
  echo "stamp: $STAMP"
  echo "tag: $TAG"
  echo "repo: $REPO"
  echo "repo HEAD: $(git -C "$REPO" rev-parse HEAD 2>/dev/null)  branch=$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  echo "qoderwake version: $(cat "$HOME/.qoderwake/.installed-version" 2>/dev/null)"
  echo
  if [ -f "$GITHUB_WAKER_TOKEN_FILE" ]; then
    echo "github waker token: ${GITHUB_WAKER_TOKEN_FILE/#$HOME/~}"
    echo "  sha256 前 16 位: $(shasum -a 256 "$GITHUB_WAKER_TOKEN_FILE" | cut -c1-16)"
    echo "  字节数: $(wc -c < "$GITHUB_WAKER_TOKEN_FILE" | tr -d ' ')   （只记指纹，值不入快照）"
  else
    echo "github waker token: 缺失 ${GITHUB_WAKER_TOKEN_FILE/#$HOME/~}"
  fi
  echo
  echo "wakers:"
  sqlite3 -separator '  ' "$DB" "select agent_id, name from agents order by created_at;"
  echo
  echo "groups:"
  "$QW" group list --json 2>/dev/null | "$NODE" -e '
    let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
      const i=s.indexOf("["); if(i<0){console.log("  (取不到)");return;}
      let a;try{a=JSON.parse(s.slice(i));}catch(e){console.log("  (解析失败)");return;}
      for(const x of a){
        const b=x.binding||{}, c=x.conversation||{};
        console.log(`  ${c.title}  group=${b.resourceId}  conv=${c.id}  created=${c.createdAt}`);
      }
    });'
  echo
  echo "group sop bindings（恢复后要靠 releaseId 与五个角色参数重新 group sop set）:"
  if G="$("$HERE/qw-group.sh" sop 2>/dev/null)"; then printf '%s\n' "$G" | sed 's/^/  /'; else echo "  (取不到)"; fi
  echo
  echo "仓内期望的 SOP 版本: ${LAB_SOP_ID}@${LAB_SOP_VERSION}"
  echo "workflow_runs: $(sqlite3 "$DB" 'select count(*) from workflow_runs;' 2>/dev/null)"
  echo "workflow_definitions: $(sqlite3 "$DB" 'select count(*) from workflow_definitions;' 2>/dev/null)"
  echo "triggers: $(sqlite3 "$DB" 'select count(*) from triggers;' 2>/dev/null)"
} > "$DEST/MANIFEST.txt"

cat "$DEST/MANIFEST.txt"

# --- 4. 轮转：只保留最近 KEEP 份 ---
# glob 展开本身就是字典序，目录名以 YYYYMMDD-HHMMSS 开头即等于时间序，无需 sort。
# 不用 head -n -K：macOS 的 BSD head 不支持负数，且管道配 pipefail 会因提前退出而失败。
# 只认「YYYYMMDD-HHMMSS-<标签>」这一种名字。glob 2*/ 已经不够安全：
# 它匹配任何以 2 开头的目录，而 ROOT 一旦指错，那就是别人家的数据。
is_snapshot() {
  case "$(basename "$1")" in
    [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]-*) return 0 ;;
    *) return 1 ;;
  esac
}
total=0
for d in "$ROOT"/*/; do [ -d "$d" ] && is_snapshot "$d" && total=$((total + 1)); done
extra=$((total - KEEP))
if [ "$extra" -gt 0 ]; then
  i=0
  for d in "$ROOT"/*/; do
    [ -d "$d" ] || continue
    is_snapshot "$d" || { echo "  -  跳过（不是本脚本的快照命名）：$(basename "$d")"; continue; }
    i=$((i + 1))
    [ "$i" -le "$extra" ] || break
    rm -rf "$d" && echo "rotated out: $(basename "$d")"
  done
fi

# 备份目录里虽然没有 token 值，但有角色配置、Memory 与全部会话历史——同样不该被 Waker 读到。
chmod 700 "$ROOT" 2>/dev/null || true
chmod -R go-rwx "$DEST" 2>/dev/null || true

echo
kept=0
for d in "$ROOT"/*/; do [ -d "$d" ] && is_snapshot "$d" && kept=$((kept + 1)); done
echo "备份完成：${DEST}（当前保留 $kept 份）"
echo "提示：$ROOT 已在 lab/guard/file-guard-additions.json 的黑名单里，别让 Waker 读它。"
