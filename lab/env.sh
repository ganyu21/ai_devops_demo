# shellcheck shell=bash
# 演练环境的唯一配置入口。source 它，不要执行它。
#
#   source lab/env.sh
#
# 这里**不写死任何机器本地 id**（群 id、会话 id、Waker id 都不写）。它们随 QoderWake store
# 重建而变，写死就等于把一份会过期的事实源放进仓库；而这是公开仓，本机的实例 id 也不该出现在里面。
# 一律按名字/标题在运行时解析，与 lab/install.sh 解析 Waker 的做法一致。
#
# 解析是惰性的：source 本身不发起任何 CLI 调用，只有真去取 id 时才调。
# 所以 source 一个不存在的群不会报错，报错发生在你用它的时候——那时错误信息才有上下文。

LAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

# --- 平台与运行时 ---
QW="${QODERWAKE_BIN:-$HOME/.qoderwake/qoderwake}"
# 用绝对路径：本机 nvm 的 shell hook 是坏的，裸 node 会刷 _nvm_lazy_load 报错
NODE="${NODE_BIN:-/opt/homebrew/bin/node}"
QW_DAEMON_PORT="${QW_DAEMON_PORT:-19820}"

# --- 靶仓 ---
LAB_REPO_SLUG="${LAB_REPO_SLUG:-ganyu21/ai_devops_demo}"
LAB_GATE_WORKFLOW="${LAB_GATE_WORKFLOW:-gate.yml}"
LAB_GATE_JOB="${LAB_GATE_JOB:-mvn-verify}"

# --- 数字员工团队 ---
LAB_GROUP_TITLE="${LAB_GROUP_TITLE:-GitHub 靶仓交付团队}"
LAB_SOP_ID="${LAB_SOP_ID:-github-lab-group-delivery}"
LAB_SOP_VERSION="${LAB_SOP_VERSION:-1.0.3}"
LAB_WAKER_LEAD="${LAB_WAKER_LEAD:-Lead-Waker}"
LAB_WAKER_PM="${LAB_WAKER_PM:-PM-Waker}"
LAB_WAKER_DEV="${LAB_WAKER_DEV:-Dev-Waker}"
LAB_WAKER_QA="${LAB_WAKER_QA:-QA-Waker}"
LAB_WAKER_DEVOPS="${LAB_WAKER_DEVOPS:-DevOps-Waker}"

# --- 凭据：只有「值」在仓外，路径约定在仓内 ---
GITHUB_WAKER_TOKEN_FILE="${GITHUB_WAKER_TOKEN_FILE:-$HOME/.config/ai-devops-lab/github-waker-token}"
export GITHUB_WAKER_TOKEN_FILE

# --- 群 / 会话 id 解析 ---
# 覆盖方式：直接 export LAB_GROUP / LAB_CONV 即可跳过解析（例如要操作一个还没起标题的群）。
#
# 解析分两级，因为标题不是可靠主键：实测 `group list` 报的 conversation.title 与
# `group show` 报的 title 可以不一致（群被 rename 过，list 那侧仍是建群时的标题）。
# 所以先按标题精确匹配（一次调用，够快），匹配不到再退回按 SOP 绑定找——
# 「绑着本演练 SOP 的那个群」才是不随改名漂移的不变量。
_lab_list_json() { "$QW" group list --json 2>/dev/null; }

_lab_pick() {   # $1 = 要取的字段路径：resourceId | conversationId
  _lab_list_json | LAB_TITLE="$LAB_GROUP_TITLE" LAB_FIELD="$1" "$NODE" -e '
    let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
      const i=s.indexOf("["); if(i<0) return;
      let arr; try{arr=JSON.parse(s.slice(i));}catch(e){return;}
      const want=process.env.LAB_TITLE;
      // 同标题可能有多份（重建过环境），取 createdAt 最新的那份：旧的那份是尸体，
      // 往里发消息没人回，而现象看起来像「团队挂了」。
      const hit=(Array.isArray(arr)?arr:[])
        .filter(x=>((x.conversation||{}).title)===want)
        .sort((a,b)=>String((b.conversation||{}).createdAt).localeCompare(String((a.conversation||{}).createdAt)));
      if(!hit.length) return;
      const b=hit[0].binding||{}, c=hit[0].conversation||{};
      process.stdout.write(process.env.LAB_FIELD==="resourceId" ? (b.resourceId||"") : (c.id||""));
    });'
}

# 退回路径：逐个群查 SOP 绑定，找出绑着 LAB_SOP_ID 的那个。
# 群通常只有一两个，所以这几条额外调用的代价可以接受，而换来的是改名不会打断演练。
_lab_find_by_sop() {   # $1 = resourceId | conversationId
  local ids pair gid cid
  ids="$(_lab_list_json | "$NODE" -e '
    let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
      const i=s.indexOf("["); if(i<0) return;
      let a; try{a=JSON.parse(s.slice(i));}catch(e){return;}
      for(const x of (Array.isArray(a)?a:[]))
        process.stdout.write(`${(x.binding||{}).resourceId||""} ${(x.conversation||{}).id||""}\n`);
    });')"
  [ -n "$ids" ] || return 1
  while read -r gid cid; do
    [ -n "$gid" ] || continue
    if timeout 60 "$QW" group sop list "$gid" --json 2>/dev/null | grep -q "\"$LAB_SOP_ID\""; then
      [ "$1" = "resourceId" ] && printf '%s' "$gid" || printf '%s' "$cid"
      return 0
    fi
  done <<< "$ids"
  return 1
}

lab_group() {
  if [ -n "${LAB_GROUP:-}" ]; then printf '%s' "$LAB_GROUP"; return 0; fi
  LAB_GROUP="$(_lab_pick resourceId)"
  if [ -z "$LAB_GROUP" ]; then
    LAB_GROUP="$(_lab_find_by_sop resourceId 2>/dev/null)"
    [ -n "$LAB_GROUP" ] && echo "  (群标题不是「${LAB_GROUP_TITLE}」，按 SOP 绑定 ${LAB_SOP_ID} 找到的：${LAB_GROUP})" >&2
  fi
  export LAB_GROUP
  if [ -z "$LAB_GROUP" ]; then
    echo "x 找不到演练群：既没有标题为「${LAB_GROUP_TITLE}」的群，也没有绑着 ${LAB_SOP_ID} 的群。" >&2
    echo "  现有群：\$QW group list --json" >&2
    echo "  要新建：见 lab/install.sh 末尾打印的 group create 命令。" >&2
    echo "  要指向别的群：export LAB_GROUP=<groupId> LAB_CONV=<conversationId>" >&2
    return 1
  fi
  printf '%s' "$LAB_GROUP"
}

lab_conv() {
  if [ -n "${LAB_CONV:-}" ]; then printf '%s' "$LAB_CONV"; return 0; fi
  LAB_CONV="$(_lab_pick conversationId)"
  [ -n "$LAB_CONV" ] || LAB_CONV="$(_lab_find_by_sop conversationId 2>/dev/null)"
  export LAB_CONV
  [ -n "$LAB_CONV" ] || { echo "x 找不到演练群的会话 id（同 lab_group 的排查方式）" >&2; return 1; }
  printf '%s' "$LAB_CONV"
}

lab_daemon_up() {
  [ -n "$(lsof -nP -iTCP:"$QW_DAEMON_PORT" -sTCP:LISTEN -t 2>/dev/null | head -1)" ]
}

# 谁在占用靶仓的工作树。共享工作树是本演练最容易踩的坑：
# 每个 Waker 会在 ~/.qoderwake/data/cloud-conversations/<conv>/workers/<wakerId>/ 下
# 开自己的 worktree，而 git 不允许同一个分支被两个 worktree 同时 checkout。
# 操作员想 `git switch main` 时会直接失败，若此时改成「从当前分支切一个新分支」，
# 就会把某个 Waker 尚未推送的半成品带进自己的提交里——这个事故真实发生过。
lab_worktrees() {
  local root; root="$(git -C "$LAB_ROOT/.." rev-parse --show-toplevel 2>/dev/null)"
  [ -n "$root" ] || { echo "  （当前目录不在靶仓的 git 工作树里，跳过）"; return 0; }
  # 先 fetch 再比较。领先/落后是拿本地缓存的 refs/remotes/origin/* 算的，而那份缓存
  # 只在有人显式 fetch 或 push 时才更新——实测它把已经推上去的 5 个提交报成
  # 「⚠ 领先 origin，有未推送的工作」。这一节的整个用途就是「动手前先确认没人占着、
  # 没有未推送的半成品」，报一个自信的假警报比不报更糟：要么把人挡在正当操作之外，
  # 要么教会人忽略这条警告。fetch 失败（离线）时如实说明比较基准可能陈旧，不装作准确。
  if git -C "$root" fetch origin --quiet 2>/dev/null; then
    :
  else
    echo "  !  fetch 失败（离线？），下面的领先/落后是拿本地缓存的 origin 引用算的，可能陈旧"
  fi
  # 除了「谁占着哪个分支」，还要报**它相对远端是领先还是落后**：
  # 领先意味着有 Waker 的提交还没推上去，此时操作员从那个分支切新分支就会把半成品带走；
  # 落后只是 checkout 陈旧，无害。两者的处置完全不同，光看 worktree list 分不出来。
  git -C "$root" worktree list --porcelain 2>/dev/null | awk '
    /^worktree /{wt=$2}
    /^branch /{br=$2; sub(/^refs\/heads\//,"",br); print wt "\t" br}
    /^detached$/{print wt "\tdetached"}
  ' | while IFS=$'\t' read -r wt br; do
      [ -n "$wt" ] || continue
      ab="$(git -C "$root" rev-list --left-right --count "origin/${br}...${br}" 2>/dev/null)"
      if [ -n "$ab" ]; then
        behind="${ab%%[[:space:]]*}"; ahead="${ab##*[[:space:]]}"
        if [ "$ahead" != "0" ] && [ "$behind" != "0" ]; then
          note="⚠ 与 origin/${br} 分叉（本地独有 ${ahead}、远端独有 ${behind}）——有未推送的工作"
        elif [ "$ahead" != "0" ]; then
          note="⚠ 领先 origin/${br} ${ahead} 个提交——有未推送的工作"
        elif [ "$behind" != "0" ]; then
          note="落后 origin/${br} ${behind} 个提交（checkout 陈旧，无害）"
        else
          note="与 origin/${br} 同步"
        fi
      else
        note="（没有对应的 origin/${br}）"
      fi
      printf '  %-20s %s\n' "${br}" "${note}"
      printf '  %-20s %s\n' "" "$(git -C "$wt" log --oneline -1 2>/dev/null)   ←  ${wt/#$HOME/~}"
    done
  echo
  echo "  在飞的会话运行（running / waiting_input）："
  timeout 60 "$QW" runs list "$(lab_conv)" 2>/dev/null | grep -Ei "running|waiting_input" | sed 's/^/    /' \
    || echo "    （无）"
}
