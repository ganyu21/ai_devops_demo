# lab/ — 数字员工团队的资产

这个目录装的是**跑这套演练所需的全部可版本化资产**：角色描述、协作 SOP、凭据隔离封装脚本、守护配置。它们跟着仓库走，所以换一台机器也能照着装回来。

不放这里的只有一样东西：**token 本身**。

```
lab/
├── install.sh                     把下面的资产装到本机 QoderWake（支持 --check 只核对不写）
├── wakers/desc-{lead,pm,dev,qa,devops}.txt   五个角色的职责描述与边界
├── sop/
│   ├── sop-body.md                群协作 SOP 正文（业务流程、角色边界、门禁、完成判定）
│   ├── build-sop.js               把正文 + 五个角色参数渲染成可发布的 SOP JSON
│   └── github-lab-group-delivery.json   构建产物，sop publish 的输入
├── guard/file-guard-additions.json  要追加到每个 Waker 的 fileGuard 黑名单的路径
└── scripts/
    ├── github-lab.sh              GitHub 能力的唯一入口（凭据隔离封装）
    └── gh-askpass.sh              GIT_ASKPASS 垫片，git 走 https 时用它取 token
```

## ⚠️ 当前状态：仓内资产已领先于 daemon（刻意的，别当成不一致去"修"）

机器门禁已从本机 Jenkins 迁到 GitHub Actions（workflow `gate.yml`，job `mvn-verify`），规则集的必需状态检查 context 也已从 `jenkins/verify` 换成 `mvn-verify`。本目录下的资产**已经全部改成 Actions 口径**：

- `sop/sop-body.md` 已发布为 **`github-lab-group-delivery@1.0.2`**（release `ccr_01m3hazvbx7a2k0zt8jnvwvn3w`，digest `015b281f…`）
- `wakers/desc-*.txt` 五份都已改写（DevOps 那份整份重写）

**但两者都还没生效到运行态**，因为迁移发生时那一轮交付正在跑（QA 在 P6）：

| 动作 | 状态 | 为什么先不做 |
| --- | --- | --- |
| `group sop set … @1.0.2` 重绑 | **待做** | 中途重绑会让正在跑的角色读到新旧两份正文，构成第二个事实源 |
| `install.sh` 写入新描述 | **待做** | 同理：运行中的 Waker 下一轮会读到与开场时不同的角色边界 |

所以这一轮的过渡靠**群消息**传达（已发，含新 context、读结论的入口、以及「不要手动触发门禁」）。**等这一轮 P7 收尾后**，按顺序补两步并复核：

```bash
lab/install.sh && lab/install.sh --check     # 描述装进 daemon，逐份核对「一致」
qoderwake group sop set <convId> --sop github-lab-group-delivery@1.0.2 \
  --param github-lab-group-delivery.delivery_lead=Lead-Waker \
  --param github-lab-group-delivery.product_manager=PM-Waker \
  --param github-lab-group-delivery.engineering_executor=Dev-Waker \
  --param github-lab-group-delivery.qa_reviewer=QA-Waker \
  --param github-lab-group-delivery.ci_gate_keeper=DevOps-Waker
qoderwake group sop list --json <convId>     # 复核 version=1.0.2 且 5 个参数都解析到真实 Waker
```

重绑之后**必须重做预热与验证**（绑定 SOP ≠ 读到正文），验证问题要挑一个 1.0.1 与 1.0.2 之间不同的细节——本轮现成的判据是「门禁的必需状态检查 context 叫什么」，1.0.1 答 `jenkins/verify`、1.0.2 答 `mvn-verify`。

`install.sh --check` 在这段过渡期会报「不一致」，那是**真信号不是故障**：它如实反映了仓内资产已改、daemon 还没改。

## 凭据模型

数字员工用的是一张 **fine-grained PAT**：只授权 `ganyu21/ai_devops_demo` 这一个仓，权限只有 Contents / Pull requests / Issues 的读写，**没有 Administration**。所以它改不了分支规则集、删不了仓、动不了分支保护——需要更高权限才能完成的动作，本来就不该由数字员工完成。

token 文件放在仓库**外面**：

```
~/.config/ai-devops-lab/github-waker-token     # chmod 600，本目录 chmod 700
```

可用 `GITHUB_WAKER_TOKEN_FILE` 覆盖路径。这个目录在 Waker 的 fileGuard 黑名单上，所以 Waker 读不到 token，只能调 `scripts/github-lab.sh`——脚本内部读文件、经环境变量交给 `gh`，token 不进 argv、不进 shell 历史、不写进 `.git/config`、不出现在任何群消息或提交内容里。

**git 的网络操作也必须走这个脚本**，不能直接 `git push`。原因：机器上自己的 git credential helper 里存着仓主的 OAuth token，那张 token 有 admin 权限。Waker 直接 push 就会绕过最小权限设计，静默提权。`github-lab.sh push` 会把 `credential.helper` 置空，改用 `GIT_ASKPASS` 垫片走那张受限的 PAT。

## 装到本机

```bash
lab/install.sh --check     # 先核对现状
lab/install.sh             # 写角色描述 + 合并 fileGuard 黑名单 + 构建 SOP JSON
```

发布 SOP、建群、绑定角色这三步会改动共享状态，`install.sh` 不做，它会在最后把命令打出来。

**绑定 SOP 之后必须先预热再验证**：`group sop set` 只是把 SOP pin 到群上，正文要等 daemon 惰性物化。跳过预热就上真需求，五个角色会照着 SOP 标题即兴发挥，而且看起来一切正常——这比报错危险得多。预热完发一条验证消息，要求角色**引用 SOP 正文原文**，引不出来就是没物化。

## 两个环境的坑（都是实测踩到的）

- **Waker 会话起不来，报 `qodercli version is incompatible with the bundled SDK (expected 1.1.48, received 1.1.64)`**：托管的 `qodercli-wake` 被热更新推到了 daemon 里 SDK 期望的版本之前。`qoderwake update --check` 会说「已是最新」，因为 daemon 本身确实是最新的——错配在运行时那一侧。**`qoderwake restart` 让两侧重新对齐即可**，重启后同一条消息的 run 从 `failed` 变成 `completed`。排查这类「消息发出去了但没人回」的问题，先看 `qoderwake runs list <convId>`，那里有 run 状态和错误原因；只看消息列表会以为是路由没通。
- **读群消息**：`qoderwake messages list <convId> --limit N --json` 返回的是**顶层数组**（不是 `{data:{messages:[]}}`），按 seq 升序，正文字段是 `body.text`，发送者是 `senderParticipantId`（要对 `group show` 里的 participant id 才能翻成名字）。`messages claim` 只能在一个活跃的 Conversation Run 内部调用，从外面调会报 `this command can only run inside an active QoderWake Conversation Run`——别拿它当读消息的入口。
