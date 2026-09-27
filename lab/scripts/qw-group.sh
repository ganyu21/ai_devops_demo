#!/bin/bash
# Group 轨道的驱动器：在群里 @ 角色推进交付。SOP 是软约束，硬卡扣靠人和 GitHub 侧的规则集。
#
# 消息收发走 qoderwake CLI（CLI 自带鉴权）；只有 /api/permissions/approvals/pending
# 这类 HTTP 端点需要 frontend session，那部分委托给 qw-api.sh。
#
# 所有 id 都在运行时按标题解析（见 lab/env.sh），本文件不写死任何机器本地 id。
#
# 用法：
#   qw-group.sh status                  群成员 + SOP 绑定 + 待审批 + 工作树占用
#   qw-group.sh sop                     只看 SOP 绑定与角色参数解析
#   qw-group.sh smoke                   无副作用冒烟：只验证 @ 路由与 SOP 参数解析
#   qw-group.sh tail [N]                看最近 N 条消息（默认 15）
#   qw-group.sh watch [间隔秒]          轮询新消息 + toolGuard 待审批，只在有变化时打印（Ctrl-C 退出）
#   qw-group.sh approvals               只看当前待人工审批的 toolGuard 请求（窗口 5 分钟）
#   qw-group.sh say <Waker名> "<文本>"   以 Requirement Owner 身份在群里 @ 某个角色发言
#   qw-group.sh kickoff <需求issue> <缺陷issue>   启动一条真实需求主线（会动靶仓）
#   qw-group.sh approve-g1              批准需求基线
#   qw-group.sh approve-g2              批准准出（只对当次 PR 与当次提交有效）
#   qw-group.sh reject "<退回意见>"      退回当前门禁
#   qw-group.sh rebind                  把群上的 SOP 重绑到仓内 LAB_SOP_VERSION（会改共享状态，需确认）
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../env.sh
. "$HERE/../env.sh"

RENDER="$HERE/qw-render.js"
API="$HERE/qw-api.sh"
PMAP=""

die() { echo "x ${1}" >&2; exit 1; }

[ -x "$QW" ] || die "找不到 QoderWake CLI：$QW（用 QODERWAKE_BIN 覆盖）"
[ -x "$NODE" ] || die "找不到 node：$NODE（用 NODE_BIN 覆盖）"
lab_daemon_up || die "daemon 未运行（端口 $QW_DAEMON_PORT 没在听），先跑 lab/scripts/qw-up.sh"

GROUP="$(lab_group)" || exit 1
CONV="$(lab_conv)" || exit 1

# messages list 是**升序**返回的，所以 --limit 1 拿到的是最旧那条而不是最新那条。
# 取足够大的一页，再由 qw-render.js 求最大 seq。
# --limit 一律用 200，不要调高。上一代环境上实测过「调到 500 会静默返回空且退出码仍是 0」，
# 表现为 max_seq 拿到空串、tail 什么都不打印——看着像群里没人说话。本环境未能复现
# （74 条消息的群上 200/500/1000 都返回全部），所以这不是「已知上限在哪」，
# 而是「调高没有收益，而一旦撞上静默空返回，故障现象极具误导性」。
max_seq() {
  timeout 60 "$QW" messages list "$CONV" --limit 200 --json 2>/dev/null \
    | "$NODE" "$RENDER" maxseq
}

# participantId → 显示名，给渲染用
build_pmap() {
  PMAP=$(mktemp -t qwpmap.XXXXXX) || die "无法创建临时文件"
  chmod 600 "$PMAP"
  timeout 60 "$QW" group show "$GROUP" --json 2>/dev/null | "$NODE" "$RENDER" members > "$PMAP"
}
cleanup() { [ -n "$PMAP" ] && rm -f "$PMAP"; PMAP=""; return 0; }
trap cleanup EXIT INT TERM

# 发消息。$1=文本，其余=要 @ 的名字
send() {
  local text="$1"; shift
  local args=() m
  for m in "$@"; do args+=(--mention "$m"); done
  # 一个都不 @ 时必须显式声明，否则 CLI 会拒绝
  [ ${#args[@]} -eq 0 ] && args=(--not-mention --yes)
  # 默认走 --text。**不要**把 SOP 里那条「长内容走 --file」的纪律照搬到这里：
  #   1. 那条纪律是给 Waker 的——它构造 shell 命令时，引号内换行且下一行以 # 起始会命中
  #      一条写法守卫、卡进 5 分钟人工审批。而本脚本是把 "$text" 作为**单个 argv 元素**
  #      直接交给 CLI，不经 shell 解析，换行与 # 都无害，操作员这边也没有 toolGuard。
  #   2. --file 的代价是实测到的：内容变成 attachments 里的 input_file，body.text 留空，
  #      于是 messages list / tail / watch 全都读不到正文——群里最长、最重要的那条消息
  #      在操作员视角变成一片空白。收信方读得到（它去取附件），发信方自己读不回来。
  # 只有真的逼近 argv 长度上限时才退回 --file，那时 qw-render.js 至少会把附件名与字节数显示出来。
  if [ "${#text}" -gt 8000 ]; then
    local f; f=$(mktemp -t qwmsg.XXXXXX) || die "无法创建临时文件"
    chmod 600 "$f"; printf '%s' "$text" > "$f"
    timeout 120 "$QW" messages send "$CONV" --file "$f" --intent request_action "${args[@]}" 2>&1 | head -20
    rm -f "$f"
  else
    timeout 120 "$QW" messages send "$CONV" --text "$text" --intent request_action "${args[@]}" 2>&1 | head -20
  fi
}

show_sop() {
  # LAB_SOP_VERSION 由 env.sh 导出，管道右侧的 node 直接继承——
  # 不要写成 `VAR=x cmd1 | cmd2`，那个前缀只作用于 cmd1，cmd2 拿不到。
  timeout 90 "$QW" group sop list "$GROUP" --json 2>/dev/null | "$NODE" "$RENDER" sop
}

render_approvals() {
  # 走 qw-render.js 而不是内联 node -e：一是内联脚本里的 // 注释会撞 UNC 命令守卫，
  # 二是渲染逻辑要逐条列命中规则、算剩余秒数，塞在 shell 的单引号串里没法维护。
  "$API" GET /api/permissions/approvals/pending 2>/dev/null | "$NODE" "$RENDER" approvals
}

pend_count() {
  "$API" GET /api/permissions/approvals/pending 2>/dev/null | "$NODE" "$RENDER" pendcount
}

# 判读一次审批轮询的结果。$1 = pend_count 的输出。
#
# 「队列取不到」必须与「队列真的是空的」分开：前者是审批守卫自身故障（鉴权坏了、
# daemon 重启了、API 形状变了），后者才是没事。把前者显示成后者，需要人工批准的那一步
# 就会在 5 分钟窗口里静默超时，而操作员看到的是「当前没有任何待审批」——
# 这正是 qw-render.js 的 pendcount 在解析失败时输出 ERR 而不是空串的原因。
#
# 状态挂在 PEND_SEEN / PEND_ERRN 两个全局上：只在变化时打印，
# 否则每 10 秒刷一屏同样的队列，真变化反而看不出来。
PEND_SEEN=""
PEND_ERRN=0
poll_approvals() {
  local n="${1-}"
  if [ "$n" = "ERR" ] || [ -z "$n" ]; then
    PEND_ERRN=$((PEND_ERRN + 1))
    # 转入故障态立刻报一次，之后每 6 轮（默认约 1 分钟）再报一次，避免刷屏盖掉真消息。
    if [ "$PEND_ERRN" = 1 ] || [ $((PEND_ERRN % 6)) = 0 ]; then
      echo "⚠ 拿不到 toolGuard 审批队列（连续 ${PEND_ERRN} 次）——这是**审批守卫自身异常**，不是队列为空。"
      echo "   需要人工批准的步骤会在 5 分钟窗口里静默超时。排查："
      echo "     lab/scripts/qw-api.sh GET /api/permissions/approvals/pending"
      echo "     \$QW runs list ${CONV}   # 先看 run 状态，别只看消息列表"
    fi
    PEND_SEEN=""
    return 1
  fi
  # 先验是不是纯数字，再宣布「恢复」。顺序反了会把一个坏值当成故障结束，
  # 打印一条 ✓ 之后才说它不认得——读的人只看见那条 ✓。
  case "$n" in
    ''|*[!0-9]*)
      PEND_ERRN=$((PEND_ERRN + 1))
      echo "⚠ 审批队列返回了不认得的计数（第 ${PEND_ERRN} 次）：$(printf '%s' "$n" | cut -c1-80)"
      echo "   同样按「守卫自身异常」处理，不是队列为空。"
      PEND_SEEN=""
      return 1 ;;
  esac
  [ "$PEND_ERRN" != 0 ] && echo "✓ 审批队列恢复可读（此前连续 ${PEND_ERRN} 次异常）"
  PEND_ERRN=0
  if [ "$n" != "0" ] && [ "$n" != "$PEND_SEEN" ]; then
    PEND_SEEN="$n"
    render_approvals
  elif [ "$n" = "0" ]; then
    PEND_SEEN=""
  fi
  return 0
}

# 工作树占用（含「有没有未推送的工作」）由 env.sh 的 lab_worktrees 提供，
# 因为 qw-up.sh 也要用它——两处各写一份必然漂移。
show_worktrees() { lab_worktrees; }

# LAB_SOURCE_ONLY=1 时只加载函数定义、不执行子命令分发。
# 存在的唯一理由是 poll_approvals 需要被测：它是这段里唯一会「把守卫故障显示成没事」的地方，
# 而它跑在 watch 的死循环里，没法在原地驱动。
[ "${LAB_SOURCE_ONLY:-0}" = "1" ] && return 0

CMD="${1:-status}"

case "$CMD" in
  status)
    echo "=== 群 ==="
    echo "  title=${LAB_GROUP_TITLE}  group=${GROUP}  conv=${CONV}"
    echo
    echo "=== 群成员 ==="
    timeout 60 "$QW" group show "$GROUP" 2>&1 | tail -n +2
    echo
    echo "=== 已绑 SOP 与角色参数 ==="
    show_sop
    echo
    echo "=== 待处理的人工审批（toolGuard 窗口只有 5 分钟，且只存内存不落库） ==="
    render_approvals
    echo
    echo "=== 靶仓工作树占用 ==="
    show_worktrees
    ;;

  sop)
    show_sop
    ;;

  smoke)
    # 无副作用：只验证 @ 路由是否真的唤醒了目标 Waker、SOP 的 ${{...}} 是否解析成了真实角色、
    # 以及 Lead 的路由判断是否只指向紧邻的下一个执行者。明确禁止碰靶仓与 GitHub。
    BEFORE=$(max_seq)
    echo "发送前 seq=${BEFORE}"
    send "【冒烟测试，无副作用，不要执行任何交付动作】

请交付负责人只做下面三件事，全部用群消息回答：

1. 报当前群的成员名单，以及本群已绑定的 SOP：名称、版本、五个角色参数各自解析到了谁。如果你看到自己的角色位置上是 \${{delivery_lead}} 这种没解析的字面占位符，直接说「占位符未解析」，不要猜。
2. 按 SOP 的固定路由回答下面两个问题，**分开答，不要合并成一个**：(a) 一张新的 GitHub 需求 issue 进群后，**人**第一个该 @ 的角色是谁？(b) 被 @ 到的那个角色确认 Requirement Owner 之后，**它**第一个该 @ 的执行角色是谁？各给一句为什么。**这一轮不要真的 @ 任何人**，把结论写在消息里就行。
3. 说明你在这条消息里有没有读到 SOP 正文。引用一句你读到的原文即可，并回答：本靶仓 main 上那个必需状态检查的 context 叫什么名字？

严格禁止：读 GitHub issue、访问靶仓、跑 git 或 mvn、触发任何 workflow、@ 其他任何角色、创建或修改任何文件。这一轮的唯一目的是验证 @ 路由、SOP 参数解析与 SOP 正文是否真的物化到了会话里。" "$LAB_WAKER_LEAD"
    echo
    echo "已 @ ${LAB_WAKER_LEAD}。用下面这条看回复："
    echo "  lab/scripts/qw-group.sh tail 5"
    echo "  lab/scripts/qw-group.sh watch 10"
    echo "（发送前 seq=${BEFORE}，回复的 seq 会大于它）"
    echo
    echo "第 3 问是版本判据：答 mvn-verify 说明读到的是 Actions 口径的正文；"
    echo "答 jenkins/verify 说明群上还绑着旧版本（当前期望 @${LAB_SOP_VERSION}）。"  # hygiene-allow: 版本判据必须写出旧 context 名，否则无法区分读到的是哪一版正文
    ;;

  tail)
    N="${2:-15}"
    build_pmap
    timeout 60 "$QW" messages list "$CONV" --limit 200 --json 2>/dev/null \
      | "$NODE" "$RENDER" render "$PMAP" | tail -"$N"
    ;;

  watch)
    INTERVAL="${2:-10}"
    build_pmap
    SEQ=$(max_seq)
    [ -n "$SEQ" ] || SEQ=0
    echo "watching ${CONV} from seq=${SEQ} every ${INTERVAL}s（Ctrl-C 退出）"
    echo "同时盯 toolGuard 人工审批：窗口只有 5 分钟，只存内存不落库，超时即该步失败且无法补批。"
    PEND_SEEN=""; PEND_ERRN=0
    while true; do
      poll_approvals "$(pend_count)"

      OUT=$(timeout 60 "$QW" messages list "$CONV" --after-seq "$SEQ" --limit 200 --json 2>/dev/null \
        | "$NODE" "$RENDER" render "$PMAP")
      if [ -n "$OUT" ]; then
        printf '%s\n' "$OUT"
        NEW=$(printf '%s\n' "$OUT" | sed -n 's/^\[seq \([0-9]*\).*/\1/p' | sort -n | tail -1)
        [ -n "$NEW" ] && SEQ="$NEW"
      fi
      sleep "$INTERVAL"
    done
    ;;

  approvals)
    render_approvals
    ;;

  say)
    WHO="${2:-}"; TEXT="${3:-}"
    [ -n "$TEXT" ] || die "用法：qw-group.sh say <Waker名> \"<文本>\""
    send "$TEXT" "$WHO"
    ;;

  kickoff)
    REQ="${2:-}"; BUG="${3:-}"
    [ -n "$REQ" ] && [ -n "$BUG" ] || die "用法：qw-group.sh kickoff <需求issue号> <线上问题issue号>"
    send "新需求进入交付。

靶仓：${LAB_REPO_SLUG}
需求 issue：#${REQ}
线上问题 issue：#${BUG}

请交付负责人按 SOP 起主线：先确认 Requirement Owner 是谁（就是发这条消息的人），再按 P0→P1 把 issue 路由给需求分析角色。范围声明：需求 issue 与缺陷 issue 的验收范围不得互相污染，基线若裁定本需求不修该缺陷，实现阶段必须逐字保持现状把缺陷带过去，由缺陷 issue 独立热修。

到 G1 需求基线门禁时必须停下来 @ 我，给出 issue 号、基线文件路径、REQ 清单、逐条变更项与验收标准、计划分支、遗留 Open Question / Conflict 条数，等我明确批准后才能进入 P2。" "$LAB_WAKER_LEAD"
    echo
    echo "已启动主线：需求=#${REQ} 线上问题=#${BUG}"
    echo "  lab/scripts/qw-group.sh watch 10"
    ;;

  approve-g1)
    send "批准 G1。需求基线可以进入编码。

本批准只对当次基线有效，不沿用到后续任何变更。进入 P2 后请注意：门禁是 JaCoCo 行覆盖率 ≥ pom.xml 里 coverage.line.minimum 的绝对下限（不存在「不低于上一次」这类相对阈值机制，不要按它解释红灯），本地与 CI 必须用同一 JDK 与同一构建命令，否则会追着只在一侧存在的幽灵失败修。" "$LAB_WAKER_LEAD"
    ;;

  approve-g2)
    send "批准 G2 准出。可以执行合并。

本批准只对当次 PR 与当次提交有效。合并后必须核实 git log origin/main 确实包含本次提交；被 main 上的分支规则集拦下（必需状态检查未过、评审线程未解决、或要求的有效审查数不满足）就如实写 S6_MERGE_BLOCKED 并附阻塞证据与解除路径，严禁虚标 DELIVERED，也严禁直推 main、force push、dismiss 审查或用管理员特权绕过规则集。" "$LAB_WAKER_LEAD"
    ;;

  reject)
    TEXT="${2:-}"
    [ -n "$TEXT" ] || die "用法：qw-group.sh reject \"<退回意见>\"（要说清退回到哪一阶段、具体哪几条不达标）"
    send "退回。本次门禁不予批准。

退回意见：${TEXT}

请交付负责人把这条路由回对应责任人修订，修订完重新过闸。一次退回意见不构成批准，重新提交前不得进入下一阶段。" "$LAB_WAKER_LEAD"
    ;;

  rebind)
    echo "当前绑定："
    show_sop
    echo
    echo "将重绑到：${LAB_SOP_ID}@${LAB_SOP_VERSION}"
    echo "⚠ 这会改动共享状态。若某一轮交付正在跑，中途重绑会让正在跑的角色读到新旧两份正文，构成第二个事实源——先确认没有运行在飞。"
    printf '确认请输入 yes：'
    read -r ans
    [ "$ans" = "yes" ] || die "已取消"
    "$QW" group sop set "$CONV" --sop "${LAB_SOP_ID}@${LAB_SOP_VERSION}" \
      --param "${LAB_SOP_ID}.delivery_lead=${LAB_WAKER_LEAD}" \
      --param "${LAB_SOP_ID}.product_manager=${LAB_WAKER_PM}" \
      --param "${LAB_SOP_ID}.engineering_executor=${LAB_WAKER_DEV}" \
      --param "${LAB_SOP_ID}.qa_reviewer=${LAB_WAKER_QA}" \
      --param "${LAB_SOP_ID}.ci_gate_keeper=${LAB_WAKER_DEVOPS}" || die "重绑失败"
    echo
    echo "重绑后："
    show_sop
    echo
    echo "绑定 SOP ≠ 读到正文。必须重做预热与验证："
    echo "  lab/scripts/qw-group.sh smoke"
    ;;

  *)
    die "未知子命令：${CMD}（可用：status | sop | smoke | tail | watch | approvals | say | kickoff | approve-g1 | approve-g2 | reject | rebind）"
    ;;
esac
