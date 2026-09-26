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
