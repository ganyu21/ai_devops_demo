# lab/ — 数字员工团队的资产

这个目录装的是**跑这套演练所需的全部可版本化资产**：角色描述、协作 SOP、凭据隔离封装脚本、
守护配置、以及操作员驱动团队用的那套脚本。它们跟着仓库走，换一台机器 clone 下来就能照着装回来。

## 自洽边界：仓外只允许两样东西

这是本目录的一条硬约束，`qw-up.sh` 会逐份核对：

| 允许在仓外 | 为什么 | 仓里放的是什么 |
| --- | --- | --- |
| **token 的值**（`~/.config/ai-devops-lab/github-waker-token`） | 公开仓里不能有凭据 | 路径约定、权限要求（600/700）、以及「值不入 git」的核对 |
| **已安装的软件**（QoderWake CLI 与 daemon、`gh`、`git`、`mvn`、JDK） | 那是运行时依赖，不是演练资产 | 调用它们的封装脚本与版本/JAVA_HOME 约定 |

除此之外**不应该再有任何仓外配套**。这条约束是补出来的：操作员脚本原先散在 `~/jenkins-lab/` 下，<!-- hygiene-allow: 记的是这条约束的来历，需要点名那个已退役目录 -->
群 id 与会话 id 写死在其中一份里，换一台机器就整套跑不起来；而且那份脚本指向的还是上一代的群。
现在它们都在 `scripts/` 下，id 一律运行时解析。

```
lab/
├── env.sh                       唯一配置入口（source 它）。所有 id 按名字/标题运行时解析，不写死
├── install.sh                   把资产装进本机 QoderWake（--check 只核对不写）
├── README.md                    本文
├── guard/file-guard-additions.json   fileGuard 黑名单增量（add 合并 / remove 摘除）
├── wakers/desc-{lead,pm,dev,qa,devops}.txt   五个角色的职责描述与边界
├── sop/
│   ├── sop-body.md              群协作 SOP 正文（业务流程、角色边界、门禁、完成判定）
│   ├── build-sop.js             正文 + 五个角色参数 → 可发布的 SOP JSON，内含构建期口径守卫
│   └── github-lab-group-delivery.json   构建产物，sop publish 的输入
└── scripts/
    ├── github-lab.sh            GitHub 能力的唯一入口（凭据隔离封装）
    ├── gh-askpass.sh            GIT_ASKPASS 垫片，git 走 https 时用它取 token
    ├── qw-api.sh                已认证的 daemon HTTP API 代理（CLI 表达不了的操作走它）
    ├── qw-render.js             CLI/API 的 JSON 解析与渲染（消息、成员、SOP 绑定、审批队列）
    ├── qw-group.sh              群驱动器：status / smoke / watch / approvals / kickoff / 门禁批准 / rebind
    ├── qw-up.sh                 环境自检（7 节）+ daemon 拉起
    ├── qw-backup.sh             快照 store 与角色导出（仓内资产不入快照，它们由 git 版本化）
    └── check-public-hygiene.sh  公开仓卫生扫描：内部口径、内部单号、机器用户名、凭据字面量
```

## ⚠️ 当前状态：仓内资产已领先于 daemon（刻意的，别当成不一致去"修"）

机器门禁跑在 GitHub Actions 上（`.github/workflows/gate.yml`，job `mvn-verify`），
规则集要求的必需状态检查 context 就是 `mvn-verify`。本目录下的资产已全部是这个口径：

- `sop/sop-body.md` 已构建为 **`github-lab-group-delivery@1.0.3`**（尚未发布）
- `wakers/desc-*.txt` 五份都已改写（DevOps 那份整份重写）

**但两者都还没生效到运行态**，因为迁移发生时那一轮交付正在跑：

| 动作 | 状态 | 为什么先不做 |
| --- | --- | --- |
| `group sop set … @1.0.3` 重绑 | **待做** | 中途重绑会让正在跑的角色读到新旧两份正文，构成第二个事实源 |
| `install.sh` 写入新描述 | **待做** | 同理：运行中的 Waker 下一轮会读到与开场时不同的角色边界 |
| `install.sh` 合并 fileGuard 增量 | **待做** | 与前两项同批做。它只收紧权限（新增 2 条黑名单、摘除 3 条已退役 CI 的死条目），风险低于前两项 |

现网群上仍绑着 `@1.0.1`，`qw-up.sh` 与 `qw-group.sh sop` 都会把这条差异显式报出来。
这一轮的过渡靠**群消息**传达（已发，含新 context、读结论的入口、以及「不要手动触发门禁」）。

**等这一轮 P7 收尾后**按顺序补三步并复核：

```bash
lab/install.sh && lab/install.sh --check          # 描述 + fileGuard 装进 daemon，逐份核对「一致」
./lab/scripts/qw-group.sh rebind                  # 重绑到 env.sh 里的 LAB_SOP_VERSION（会要确认）
./lab/scripts/qw-group.sh smoke                   # 预热 + 验证（绑定 SOP ≠ 读到正文）
```

`smoke` 的第 3 问就是版本判据：答 `mvn-verify` 说明读到的是 Actions 口径的正文；
答 `jenkins/verify` 说明群上还绑着旧版本。<!-- hygiene-allow: 版本判据必须写出旧 context 名，否则无法区分读到的是哪一版正文 -->

`install.sh --check` 在这段过渡期会报「不一致」，`qw-up.sh` 会把它计入待处理项数——
那是**真信号不是故障**：它如实反映了仓内资产已改、daemon 还没改。

## 凭据模型

数字员工用的是一张 **fine-grained PAT**：只授权 `ganyu21/ai_devops_demo` 这一个仓，
权限只有 Contents / Pull requests / Issues 的读写，**没有 Administration、没有 Workflows**。
所以它改不了分支规则集、删不了仓、也改不了 `.github/workflows/` 下的门禁定义——
需要更高权限才能完成的动作，本来就不该由数字员工完成。

token 文件放在仓库**外面**：

```
~/.config/ai-devops-lab/github-waker-token     # chmod 600，所在目录 chmod 700
```

可用 `GITHUB_WAKER_TOKEN_FILE` 覆盖路径。这个目录在每个 Waker 的 fileGuard 黑名单上，
所以 Waker 读不到 token，只能调 `scripts/github-lab.sh`——脚本内部读文件、经环境变量交给 `gh`，
token 不进 argv、不进 shell 历史、不写进 `.git/config`、不出现在任何群消息或提交内容里。

**git 的网络操作也必须走这个脚本**，不能直接 `git push`。原因：机器上自己的 git credential helper
里存着仓主的 OAuth token，那张 token 有 admin 权限。Waker 直接 push 就会绕过最小权限设计，静默提权。
`github-lab.sh push` 会把 `credential.helper` 置空，改用 `GIT_ASKPASS` 垫片走那张受限的 PAT。

**⚠ 这条防线有一个 fileGuard 兜不住的部分，别讲错**：仓主那张 token 存在 **macOS 钥匙串**里
（已实测 `~/.config/gh/hosts.yml` 里没有 `oauth_token` 键）。fileGuard 是路径守卫，
拦不到 `security find-generic-password` 或 `git credential fill`。所以「Waker 拿不到 admin token」
靠的是**调用纪律 + toolGuard**，不是 fileGuard。也不要把 `~/.config/gh/` 加进黑名单来「补这个洞」：
里面没有 token，而 `gh` 每次调用都要读这个目录，拉黑有打断 GitHub 访问的风险。

## 装到本机

```bash
./lab/scripts/qw-up.sh status    # 先自检：7 节，报出所有待处理项
lab/install.sh --check           # 只看角色描述与 fileGuard 的差异
lab/install.sh                   # 写角色描述 + 合并 fileGuard 黑名单 + 构建 SOP JSON
./lab/scripts/check-public-hygiene.sh   # 提交前扫一遍公开仓卫生
```

发布 SOP、建群、绑定角色这三步会改动共享状态，`install.sh` 不做，它会在最后把命令打出来。

**绑定 SOP 之后必须先预热再验证**：`group sop set` 只是把 SOP pin 到群上，正文要等 daemon 惰性物化。
跳过预热就上真需求，五个角色会照着 SOP 标题即兴发挥，而且看起来一切正常——这比报错危险得多。
预热完发一条验证消息，要求角色**引用 SOP 正文原文**，引不出来就是没物化。

## 三道守卫各管什么（不要指望一道守住全部）

| 守卫 | 在哪 | 扫什么 | 抓不到什么 |
| --- | --- | --- | --- |
| SOP 构建期口径守卫 | `sop/build-sop.js` | 要发布的那份 JSON 的**每个字段**（正文 + 5 个参数描述 + label + description） | 仓里其他文件 |
| 活体产物退役表述守卫 | `scripts/qw-up.sh` 第 7 节 | 会被装进 daemon 的那些文件：5 份角色描述、SOP 正文、封装脚本、`AGENTS.md` | 文档（`README.md`、手册） |
| 公开仓卫生扫描 | `scripts/check-public-hygiene.sh` | **全部被跟踪文件**，含内部平台名/内部单号/机器用户名/凭据字面量 | 未 `git add` 的新文件 |

三道都是逐行匹配 + 同行 `hygiene-allow: <理由>` 放行，标记必须带理由，否则它退化成一键忽略。
第一道做过变异检验（注入 5 处，全部抓到并 exit 1）；第三道是这轮新加的，
加它的直接原因是：前两道都只扫「活体产物」，于是仓根 `README.md` 与
`.github/workflows/qoder-code-review.yml` 里那句「CI 由 Jenkins 跑、context 是 `jenkins/verify`」<!-- hygiene-allow: 引述被修掉的假话原文，否则说不清这道守卫补的是什么 -->
一直没人发现——那是一句**已经变成假话的陈述**，而不是措辞问题。

有意保留的提及（版本判据、迁移说明、守卫自己的规则表）用同行标记放行，
**不要**把文件加进 `check-public-hygiene.sh` 的 `SELF_EXCLUDE`——那份名单只该有规则表本身。

## 合并资格：一个实测教训，和一次判定实验

`mergeStateStatus: BLOCKED` **不告诉你为什么**。首轮交付卡在 P7，PR #17 的两个必需检查
（`mvn-verify`、`qoder-review`）都是 SUCCESS，`mergeable: MERGEABLE`，而 `mergeStateStatus: BLOCKED`。
团队据此在群里报「唯一阻塞是 reviewDecision 为空（qoderai 仅 COMMENTED）」，
并在 `state.json` 里写下 `"unresolvedReviewThreads": false`。

**那个 `false` 与实况不符**：PR #17 上有 **7 条 qoderai 留下的评审线程，`isResolved` 全是 false**。
根因在工具而不在角色：当时的 `github-lab.sh pr-status` 只返回
`mergeable / mergeStateStatus / reviewDecision / statusCheckRollup`，**根本不包含评审线程**
（`gh pr view --json` 也没有 `reviewThreads` 这个字段，实测报 Unknown JSON field），
所以调用方无法从工具输出里得知那 7 条线程的存在，只能凭 `reviewDecision` 为空去推原因。

### 判定实验（2026-09-27，PR #19）

哪一条规则真的在阻塞，本来分不开：#17 上「7 条未解决线程」与「没有任何 APPROVED 审查」同时成立。
开 #19 时顺带做了一次对照，把它分开了：

| 时刻 | 未解决线程 | APPROVED 审查 | 必需检查 | `mergeStateStatus` |
| --- | --- | --- | --- | --- |
| #19 刚开、AI 审查还没落 | 0 | 0 | 一个还在跑 | **UNSTABLE**（不是 BLOCKED） |
| #19 检查全绿、AI 只留了 1 条线程 | 1 | 0 | 全 SUCCESS | **BLOCKED** |

结论：规则集里 `required_approving_review_count` 当前是 **0**，所以**缺审查并不阻塞**；
真正阻塞的是 `required_review_thread_resolution` —— **一条未解决的评审线程就够**。
因此 #17 的阻塞原因就是那 7 条线程，不需要动用 `require_extra_approval_for_unattributed_changes`
来解释（那条规则的含义仍未实测，别当结论引用）。

顺带一个确定的结论：Qoder Action 留下的是 **COMMENTED** 审查而不是 APPROVED，
所以它**填不上**「至少 1 名评审人批准」那一项——等 `required_approving_review_count` 调回 1 时这条就会显形。
而它**会**创建评审线程，于是它实际上拥有对合并的否决权：它每留一条意见，人就必须逐条裁定。

**还没证明的一步**：把线程全部 resolve 之后 #17 是否就转 `CLEAN`。`dismiss_stale_reviews_on_push: true`
与 `require_extra_approval_for_unattributed_changes: true` 都还开着，可能另有干预。
逐条裁定（采纳/不采纳/要求返修）是 G2 上人的活，脚本不代做。

`scripts/github-lab.sh pr-status <n>` 现在走 GraphQL 把每项规则的实况都拉出来，
并**由脚本自己**推出 `blockingReasons`。「没有任何 APPROVED 审查」被单列进
`possibleAdditionalBlockers` 而**不进** `blockingReasons`——它是不是阻塞取决于
`required_approving_review_count`，而那张 PAT 没有 Administration 权限、读不到这个值；
把一个读不到的规则断言成阻塞原因，正是首轮那个错的形状。

## 两个环境的坑（都是实测踩到的）

- **Waker 会话起不来，报 `qodercli version is incompatible with the bundled SDK (expected 1.1.48, received 1.1.64)`**：托管的 `qodercli-wake` 被热更新推到了 daemon 里 SDK 期望的版本之前。`qoderwake update --check` 会说「已是最新」，因为 daemon 本身确实是最新的——错配在运行时那一侧。**`qoderwake restart` 让两侧重新对齐即可**，重启后同一条消息的 run 从 `failed` 变成 `completed`。排查这类「消息发出去了但没人回」的问题，先看 `qoderwake runs list <convId>`，那里有 run 状态和错误原因；只看消息列表会以为是路由没通。
- **读群消息**：`qoderwake messages list <convId> --limit N --json` 返回的是**顶层数组**（不是 `{data:{messages:[]}}`），按 seq 升序，正文字段是 `body.text`，发送者是 `senderParticipantId`（要对 `group show` 里的 participant id 才能翻成名字）。`--limit` 超过服务端上限（实测 200 可用、500 不行）会**静默返回空且退出码是 0**，表现为「一条消息都没有」。`messages claim` 只能在一个活跃的 Conversation Run 内部调用，从外面调会报 `this command can only run inside an active QoderWake Conversation Run`——别拿它当读消息的入口。

## 共享工作树：这个事故真发生过

每个 Waker 会在 `~/.qoderwake/data/cloud-conversations/<conv>/workers/<wakerId>/` 下开自己的
worktree，而 git 不允许同一个分支被两个 worktree 同时 checkout。操作员想 `git switch main` 会直接失败
（`'main' is already used by worktree at …`）。

当时的错误处置是「那就从当前所在的分支切一个新的」——结果把 Dev-Waker 尚未推送的半成品
带进了操作员的提交里。正确做法：先 `./lab/scripts/qw-group.sh status` 看最后一节
（它逐个工作树报「与 origin 同步 / 落后 N 个 / **领先 N 个（有未推送的工作）**」），
再在自己的独立 worktree 里做事。
