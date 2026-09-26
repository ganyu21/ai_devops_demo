# 《AI 原生软件工程实战：基于 QoderWake 与 GitHub + Jenkins 的全流程重塑》

## 培训大纲 · v4 GitHub 靶仓版

> **这份是讲师用的大纲**：讲为什么、给实测数据、给教学主张与已知缺口。
> **要照着敲的命令全在另一份**：《操作手册-v4-GitHub靶仓版.md》——课前准备、每轮重置、课上两轨操作、速查与排障，一步一条命令。两份互相引用，不重复内容；本文里出现的命令只为说明证据从哪来，不是操作步骤。
> **数字员工团队自己的纪律在第三份**：仓库根的 `AGENTS.md` 与 `lab/sop/sop-body.md`。前者是自动化角色共用的审查口径，后者是群协作的业务流程。

### 数据标注约定（本版最重要的一条纪律）

v4 把协作平台从**上一代内部平台**换成了 **GitHub**，靶仓也从内部托管换成了公开仓。换平台的代价与换题材一样：**旧环境跑出来的每一个数字都不能搬到新环境上**。所以本版给所有带数字的结论打四种标签：

| 标签 | 含义 | 课上怎么用 |
| --- | --- | --- |
| **【GitHub 实测】** | 2026-09-26 起在本靶仓与 GitHub 上当场跑出来的 | 可以直接念，可以现场复现 |
| **【待实测】** | 新环境上还没有数据，位置先占着 | **不要念成事实**，说「这一项还没在新环境上跑过」 |
| **【内部环境实测】** | 上一代内部平台与内部靶仓上的实测，全文集中在附录 B | 只用来说明**机制**，不代表本靶仓的耗时、覆盖率、轮数 |
| **【单次观测】** | 只观测过一次，而**复核动作本身是破坏性的**（改配置 / 消耗门禁 / 真的推一次 main / 真的合一次 PR） | 结论照讲，但要说一句「这条没法当场再演一遍」。**别把它写成可复现的事实**，也别因为没法复核就当成没验证过 |

> 第四种标签是从 v3 继承的，v4 多了两个典型样本：直推 main 被拒（再验一次就等于真的推一次）、`--admin` 能否绕过必需状态检查（那次试合并发生在 CI 状态已经 success 之后，所以**没有隔离出结论**，见第五章缺口 5）。

**机制与设计层面的结论不受换平台影响，照常保留**：门禁必须预热、Group 的门禁是软约束、两轨共用一份工作树、审批窗口 5 分钟且只存内存、绑定 SOP ≠ 读到正文、正确性要从「执行者的品德」搬回「指令本身」——这些与协作平台是内部平台还是 GitHub 没有关系。

### 证据源（当前口径）

**协作与治理**

- 靶仓：`ganyu21/ai_devops_demo` @ github.com，**PUBLIC**，Free 套餐，本地根 `~/PycharmProjects/ai_devops_demo`，包名 `com.lab.shortlink`
- 分支规则集：`protect-main`，id `24042720`，`enforcement=active`，四条规则 = `deletion` + `non_fast_forward` + `pull_request` + `required_status_checks`
- **【GitHub 实测】** `bypass_actors: []`，API 直接回 `current_user_can_bypass: "never"`
- 工单：需求 issue **#2**、线上问题 issue **#3**（均**尚未消耗**）
- 标签：需求 / 线上问题 / 待澄清 / 阻塞 / 门禁红灯 / 已交付
- 看板：**未建成** —— `gh` 的 token 缺 `project` scope，见第五章缺口 6

**CI**

- Jenkins LTS @ `127.0.0.1:8080`，job **`ai-devops-demo-verify`**（Pipeline from SCM，https 克隆公开仓，Jenkins 侧不存任何 git 凭据）
- 状态回写桥：context **`jenkins/verify`**，已列为规则集的必需状态检查
- **【GitHub 实测】** build #1（20.7s）、#2（19.6s）、#3 全部 SUCCESS；三次都回写成功；CI 上的覆盖率与本机 `mvn -B clean verify` **逐位一致**

**靶仓基线（本机与 CI 双侧一致）**【GitHub 实测】

```
Tests run: 26, Failures: 0, Errors: 0, Skipped: 0
JaCoCo line:   67/72 = 93.05556%
JaCoCo branch:  6/8  = 75.00000%
Checkstyle 0 violations / SpotBugs 0 bugs (effort=Max, threshold=Low)
Flyway: Successfully applied 1 migration
BUILD SUCCESS
```

- 门禁阈值：行覆盖率 **绝对 ≥ 0.60**（`pom.xml` 的 `coverage.line.minimum`，**只有这一处**；Jenkinsfile 只打印 `GATE SUMMARY` 与回写状态，不自己判阈值）
- 红灯分支 `lab/predictable-code`（`bd91bac`，只把 `ShortCodeGenerator.CODE_LENGTH` 从 8 改成 6）：**2 处失败，都指向同一条策略**
- 缺陷现场：`VisitLogService.java:22` 的 `referer.toLowerCase(Locale.ROOT)`，调用点 `ShortlinkController.java:75`

**数字员工团队**

- QoderWake daemon @ `127.0.0.1:19820`，版本 1.1.3
- 群「GitHub 靶仓交付团队」`csgrp_01m3f5pwhg5ye6dbswne4dzea9` / `conv_01m3f5pwhsfrehh2375v2y5cw7`
- SOP `github-lab-group-delivery@1.0.1`，release `ccr_01m3f81cace5yda7vd64758h2c`，digest `801b75b1…`
- 5 个 Waker：Lead / PM / Dev / QA / DevOps，角色描述与 fileGuard 由 `lab/install.sh` 装机
- **【待实测】** 一轮完整交付（P0→P7）在本靶仓上**还没跑过**：所有阶段耗时、自愈轮数、冲突文件数、未覆盖点条数、PR 号、Memory 条目全部空缺
- AI 代码审查：`AGENTS.md` + 两条 workflow 已写好，**尚未推上去**（缺 `workflow` scope），因此**尚未实测**

---

## 零、v3 → v4 的实质差异

不是换名字，是换了一套治理机制。下面每条都在本靶仓上取过证。

### 0.1 平台映射

| 环节 | v3（内部平台） | v4（GitHub） |
| --- | --- | --- |
| 需求与缺陷 | 工单系统的需求单 / 线上问题单 | **Issues** #2 / #3 |
| 看板 | 项目视图 | **Projects**（未建成，缺 scope） |
| 代码审查 | MR | **Pull Request** |
| 分支治理 | 项目级默认规则（评审人通过数） | **Rulesets**（`protect-main`） |
| 读写工单的 CLI | 内部 CLI（封装成 skill） | **`gh`**（封装成 `lab/scripts/github-lab.sh`） |
| CI | 本机 Jenkins + `file://` 克隆内部仓 | 本机 Jenkins + **https 克隆公开仓**，多一条**状态回写桥** |
| 事件驱动 | 插件侧轮询工单 | GitHub **webhook**（可推送，但本地要入站通路，未验证） |

### 0.2 五个新发现（v3 里没有的）

**① 直推 main 这次真的被仓库挡住了。**【GitHub 实测】
v3 的一条核心教学主张是「挡住 Agent 直推 main 的是提示词纪律 + toolGuard，**不是**仓库配置」——因为那个仓上 `git push origin main` 推得动。GitHub 上配了规则集就不一样了：以**仓主（admin）身份**直推，被拒：

```
remote: error: GH013: Repository rule violations found for refs/heads/main.
remote: - Changes must be made through a pull request.
 ! [remote rejected] main -> main (push declined due to repository rule violations)
```

**教学主张要跟着改，但只改一半**：仓库这次确实兜住了，`bypass_actors` 为空意味着管理员也不得绕过（API 回 `current_user_can_bypass: "never"`）。可是**纪律仍然要在**——换个没配规则集的仓就兜不住，而配规则集这件事本身也是人做的决定。正确的说法是：**治理控制要配成「连管理员都绕不过」才算控制，配好之后纪律是第二层，不是替代品。**

**② 「至少 1 名评审通过」在单账号仓里是结构性死锁，而成因与 v3 不同。**【GitHub 实测】
v3 的死锁来自项目级默认规则（`approver_number`），换仓也绕不开。v4 的死锁来自**身份不足**：GitHub 不允许作者批准自己的 PR，而这个仓只有一个人类账号（`gh api user/orgs` 为空，collaborators 只有自己）。所以把 `required_approving_review_count` 设成 1，结果是**任何 PR 都合不进 main**，包括讲师自己要合的讲义。
本轮把它临时设为 **0**（其余三条规则不变），等第二身份到位再升回 1。三条出路：① 注册一个 bot 账号当数字员工；② 课堂配对，一人操作数字员工、一人当评审；③ **`qoderai` GitHub App 的 review 能不能计入评审数**——这条最有意思，因为它同时是 AI 审查层和第二身份，**【待实测】**。

**③ 配置类写入要用会报错的那个入口。**【GitHub 实测】
把 `required_status_checks` 当成 `pull_request` 规则的参数写进去时：

- `PUT /rulesets/<id>` 返回 **200**，响应体里那个键**根本不存在**——静默丢弃
- `POST /rulesets` 返回 **422**，并给出原因：`Invalid rule 'pull_request': Unexpected parameter required_status_checks`

正解是 `required_status_checks` 是**独立的规则类型**，不是 `pull_request` 的参数。
**这条的教学价值比结论本身大**：同一个错误载荷，宽松的入口告诉你「成功了」，严格的入口告诉你「错在哪」。所以配治理控制**必须回读校验**，不能看返回码。v3 在内部平台的 trigger API 上踩过同一类坑（`PATCH`/`PUT` 返回 `success:true` 却静默忽略 `target` 字段）——**这不是某个产品的问题，是所有配置类 API 的共性**。

**④ 改 CI 定义需要单独的权限，连仓主默认的 token 都没有。**【GitHub 实测】
推 `.github/workflows/` 下的文件被拒：

```
! [remote rejected] (refusing to allow an OAuth App to create or update workflow
  `.github/workflows/qoder-assistant.yml` without `workflow` scope)
```

当前 token 的 scopes 是 `gist / read:org / repo`，**没有 `workflow`**。于是「数字员工改不了自己的审查关卡」这件事有两层保证：它那张 fine-grained PAT 没有 Workflows 权限，而**人的默认 token 也没有**。要把 AI 审查升级成必需状态检查，得先有人显式授权一次——这个摩擦是好事。

**⑤ 状态绑在 SHA 上，不绑在 PR 上。**【GitHub 实测】
PR 已经拿到 `jenkins/verify = success` 之后，往同一分支再推一个提交，PR 的 `statusCheckRollup` 立刻变空、`mergeStateStatus` 回到需要重新构建的状态。**这正是「批准只对当次提交有效」在机器层面的实现**，v3 只能靠纪律约束，v4 有机械保证。课上可以现场演：批准之后再推一个空提交，看关卡怎么重新落下。

---

## 一、课程定位与目标

- **学员对象**：传统开发、测试、运维人员及技术 PM（面向 AI 原生工作流转型的 IT 人员）。
- **教学核心**：摆脱单点 Copilot 的使用偏见，基于 **QoderWake 数字员工平台**（Waker 角色配置、Group 团队协同、记忆进化、Skills/连接器、toolGuard + fileGuard 安全沙盒），打通 **GitHub（Issues / PR / Rulesets）+ Jenkins + Qoder Action**，建立「正向高效交付 + 逆向异常自愈」的生产级 AI-Native 研发体系。
- **实战产出**：通过 1 个端到端业务需求，学员组队配置并编排 Waker，完成从 GitHub 需求拆解、线上缺陷热修、Git 冲突仲裁、Jenkins CI 门禁、AI 代码审查到人工准出与记忆治理的全流程。

> **教学主张（从 v2 保留，v4 仍然成立）**：本课程最有说服力的部分不是「Agent 写完了代码」，而是**Agent 在被安全策略拦下时的行为**。【内部环境实测】里 DevOps-Waker 连续撞上 `TOOL_CMD_DANGEROUS_RM` / `TOOL_CMD_DANGEROUS_MV`，拒绝直推 main、拒绝 force push、拒绝绕过 MR 评审，并且拒绝把状态写成 `DELIVERED`——它选择停在 `S6_MERGE_BLOCKED` 并写明解除路径。这段行为由**指令与守护规则**决定，与协作平台和靶仓业务无关，所以在 GitHub + 短链靶仓上应当重现；**【待实测】** 第一轮跑完要专门核对它有没有重现。

> **v4 新增的教学主张**：治理控制的强度取决于**能不能绕过**，而不是有没有配。同一个「必须走 PR」，配了 `bypass_actors` 就是建议，配成空才是控制。这条在 GitHub 上可以现场验证（API 直接回 `current_user_can_bypass: never`），比讲概念有效。

---

## 二、阶段一：理念转轨与 QoderWake 产品架构基石

**目标**：理解 Agentic Workflow 与企业级 DevOps 工具链的连接机制，掌握 QoderWake 的「岗组设定」与记忆机制。

### 1. 从 Copilot 到 QoderWake 数字员工

- **两大主线**：以「事」为核心（任务看板、自主工作、流程编排）与以「人」为核心（Waker 岗位配置、Group 团队）。
- **Waker 核心要素**：角色配置、运行环境、记忆、Skills、连接器（MCP）、知识库与安全沙盒隔离。
- **实测锚点**：本机 **5 个 Waker**，工作区各自独立（`~/.qoderwake/data/workers/<agentId>`）。讲「沙盒隔离」时直接打开这五个目录对比，比讲概念有效。
  - WakerFlow 轨只用 PM / Dev / DevOps 三个（状态机自己就是协调者，验收折进了 G2 人工门禁）；Group 轨五个全用，理由见 4.3 与第六章。
- **5 个角色的职责原文已入仓**：`lab/wakers/desc-{lead,pm,dev,qa,devops}.txt`，换题材时就是改这五个文件再 `lab/install.sh` 装回去。课上要讲「角色边界怎么写」，直接投这五份原文，比口头描述准确。
  **【GitHub 实测】** 这五份描述本轮全部重写过：旧版写死了内部靶仓的绝对路径、内部工单口径与 MR 术语，`install.sh --check` 能逐个核对装机内容与仓内文件是否一致（幂等）。
- **⚠️ 描述里的路径要展开成绝对路径**：仓库里的文本用 `~/` 写（公开仓不该带机器用户名），`install.sh` 装机时展开成绝对路径。**Waker 的会话工作目录是自己的沙箱而不是仓库**，相对路径与 `~` 都可能落错地方。

### 2. 安全沙盒不是装饰：toolGuard 与 fileGuard 的真实代价

> 本节机制**与协作平台和靶仓都无关**，v4 原样保留。以下 4 类拦截与七次审批判据的实录见附录 B。

- **审批窗口只有 5 分钟**（`approvalTimeoutMs` 默认 `5*60*1000`，仅能通过环境变量 + 重启 daemon 调整）。超时后 worker 收到 `denied_approval_timeout`，该步骤即失败。
- **审批请求只存在内存里**，没有落库，只能轮询 `GET /api/permissions/approvals/pending` 拿到，无法事后补批。**但 daemon 日志是持久的**——事后复盘审批判据要查日志，不要说「当时没记下规则 id」。
- **实测踩到的 4 类拦截**【内部环境实测，机制通用】：`SHELL_EVASION_OBFUSCATED_FLAGS`（误报：被引号包裹的 flag）、`SHELL_EVASION_QUOTED_NEWLINE`（写法问题：引号内换行**且下一行以 `#` 起始**，即 markdown 标题行；不是「多行」本身）、`TOOL_CMD_DANGEROUS_RM` / `TOOL_CMD_DANGEROUS_MV`（正确拦截，但暴露流程设计缺陷）、fileGuard 黑名单（正确拦截，凭据目录本就不该被 worker 读）。
- **正确的修复方向**：不要为了让流程跑通而关掉守护规则。三个修复都是**改流程/改提示词/改 SOP**：禁止 `echo "---x---"` 这类写法；长内容走 `--file` 而不是 `--text`；临时复现测试不让 worker 清理，而是**升格为回归测试**交给下一阶段 `git add` 纳管。
  这一节的教学价值：**被守护拦下就是边界，不是障碍**。
- **核对守护配置要读对字段**：`fileGuard.sensitiveFiles` 与 `toolGuard.disabledRuleIds`。**不要**去找 `rules[].enabled`——那个结构不存在，按它写校验脚本会得出「5 个 Waker 全都配错了」的假结论。
  **【GitHub 实测】** 本轮 fileGuard 从 6 条增到 8 条（已逐个 Waker 回读核对）：新增 GitHub PAT 的存放目录 `~/.config/ai-devops-lab/`，以及一个过渡期的 `~/jenkins-lab/secrets/`（token 挪到仓库外之后那条已无实际内容，留着不碍事）；由 `lab/install.sh` 与该 Waker 现有清单**合并**写入，不整份替换（整份替换会冲掉本机已有的条目）。
- **⚠️ CLI 的一个不一致**【GitHub 实测】：`permission get --json` 打的是**表格**，只有 `--format json` 才真给 JSON。同类形状差异还有：`messages list --json` 与 `waker list --json` 返回**顶层数组**（不是 `{data:{…}}`），正文字段是 `body.text`，发送者是 `senderParticipantId`。按想当然的形状写解析脚本会静默得到空结果。

### 3. 基于 GitHub 的全链路事件驱动协同架构

- **全场景拓扑**：GitHub Issues（需求/缺陷）→ QoderWake（Waker / Group + SOP）→ Git（分支/代码/PR/冲突仲裁）→ Jenkins（CI/自愈）→ **commit status 回写 GitHub** → Rulesets 决定能不能合并 → issue 回写结论。
  v3 的拓扑到「CI 跑完」就结束了，v4 多了一条**回写边**：没有它，GitHub 侧的必需状态检查永远等不到结论，PR 就永远合不进去。**这条边是 v4 架构上唯一的新增件，也是治理能闭环的关键。**
- **三层审查，各管一件事**：

  | 层 | 载体 | 管什么 | 结论落在哪 |
  | --- | --- | --- | --- |
  | 机器门禁 | Jenkins job `ai-devops-demo-verify` | 跑不跑得通：测试、覆盖率、静态检查、schema 迁移 | commit status `jenkins/verify`（规则集必需检查） |
  | AI 审查 | Qoder Action（`AGENTS.md` 提供口径） | 有没有违背**已写下来的纪律** | PR review + check `qoder-review` |
  | 人工准出 | G2 门禁 | 这个风险接不接受 | 群里的明确批准 + 批准记录持久化 |

  **谁也不替代谁**。把 AI 审查当门禁用会漏掉「跑不跑得通」，把机器门禁当审查用会漏掉「该不该这么改」，而风险接受这件事**不能委托给任何自动化层**。
- **`AGENTS.md` 是审查口径的单一事实源**：Qoder CLI 自动加载它，改它要走 PR。这是「把正确性写进指令」最具体的落点——规则跟着代码一起版本化，而不是散在某个人的提示词里。里面写清了两条自动化角色最容易搞错的口径：**已登记在 issue 里的已知缺陷不要要求「顺手修」**（范围纪律优先于代码整洁），**未覆盖行不要一律要求补到 100%**（要分类给依据）。
- **⚠️ 事件驱动的真实状态**：GitHub 侧可以推 webhook（比 v3 的插件轮询强），但本地 daemon 要收到就得有入站通路。**【待实测】** 本轮仍是人工发起 + `github-lab.sh` 读写 issue。讲「事件驱动」时必须如实说明当前是哪一种，别把「平台支持」讲成「我们已经接通」。

---

## 三、阶段二～四：需求、开发、CI/CD 与记忆治理

> 本章的**机制与设计**沿用已验证的结论；**具体产物（提交号、文件名、缺陷位置、覆盖率、耗时）**在本靶仓上要么标【待实测】，要么给出【GitHub 实测】的基线值。内部环境的对应数据在附录 B，课堂上只作机制佐证。

### 阶段二：需求分析、架构设计与变更响应（GitHub Issues + PM-Waker）

**目标**：配置数字 PM/架构师 Waker，实现需求自动拆解与需求漂移的动态响应。

1. **需求智能化澄清与拆解**
   - PM-Waker 读 issue 原文（`github-lab.sh issue <n>`），只读勘察靶仓现状，产出六段式 `change-breakdown.md`：**Fact / Request / Constraint / Risk / Open Question / Conflict**。
   - Request 段编稳定 `REQ-NN`；每条 REQ 给出 `affectedPaths` 与可执行 acceptance。
   - **关键设计**：Open Question 与 Conflict **不是异常**，是正常的人工澄清路径。流程会挂起去问需求提出人。只有「有阻塞且完全没有任何可问人的事项」才直接终止。
   - **issue #2 里预置了 10 条 Open Question + 1 条 Conflict**（正文的「需要澄清的地方」与「已知的一处矛盾」两节），所以冷启动必然挂起问人，这是设计好的教学环节。**【待实测】** 第一轮跑完要核对 PM-Waker 是否把 10 条都列了出来、有没有自行假设答案。【内部环境实测】对照：某轮提出 8 条 OQ + 2 条 Conflict。
   - **不得把推测当事实**。【内部环境实测】Fact 段第 1 条就是纠正 prompt 标题与工单实际标题的差异，以工单为准。v4 的对应物：以 issue 正文为准，群里转述的需求描述不算事实源。

2. **需求基线的续跑语义**（机制与领域无关）
   - 重跑同一 issue 时 S1 **不该冷启动**：已答复的 Open Question、已裁定的 Conflict 都是需求基线的一部分，重新问一遍等于让需求提出人做第二次同样的决定。
   - 稳定编号不得重排、不得复用废弃编号；slug 必须沿用，否则分支名漂移。
   - **【内部环境实测】** S1 冷启动 13m55s（含 10 项人工澄清），续跑 2m08s、零重复提问。**【待实测】** 本靶仓的对应耗时。
   - **续跑的真实陷阱**：基线产物提交在 feature 分支上，而上一轮流程可能把 HEAD 留在 main（分诊阶段要切 main 定位缺陷）。此时产物在工作区里根本不存在，worker 会误判成冷启动。修复是在 S1 提示词里加前置动作：先 `git branch --list 'feature/issue-<n>-*'`，有就 checkout 过去再核对。
   - **判断一轮是冷启动还是续跑，要读 `change-breakdown.md` 文档头的「启动方式」段，不要去 acceptance 里找**。曾记录过一条「续跑提示泄漏进 REQ-01 验收标准」的缺陷，复核后不成立。**「记录下来的缺陷」本身也要复核**，别把它当既成事实写进讲义。

3. **需求变更与「逆向撤回」应对**
   - **⚠️ 未验证**：「issue 变更/关闭 → PM-Waker 自动分析影响面 → Dev-Waker 自动识别废弃分支发起清理 PR」在两个环境上都没跑过。实测的变更响应是 G1 门禁前的人工裁定 + S1 增量修订。GitHub 侧的 webhook 让这个能力**技术上更可及**，但仍然**【待实测】**。

### 阶段三：代码开发、冲突仲裁与智能审查（Git + PR）

1. **事件驱动开发**
   - Dev-Waker 在 `feature/issue-<n>-<slug>` 分支上实现 REQ 并写单测。issue #2 要求两件事：**给解析缓存加容量上限与 TTL**、**把访问流水落库并提供统计查询接口**。
   - **S2 的阻塞是致命的**：`commitStatus === 'HOOK_FAILED' || blockers.length > 0` 直接终止流程。本机全局提交钩子会扫凭据泄露，命中即失败，且**严禁用 `--no-verify` 绕过**。
   - **范围红线（本靶仓已写成机械可查的形式）**：issue #2 的「明确的非目标」第 1 条是**不修缺失 `Referer` 时的 500，必须逐字保持 `VisitLogService.record()` 现有行为**。理由写在正文里——否则 issue #3 的热修会变成空提交，它的修复前后对比证据也就没了。**【待实测】** 首轮要专门核对有没有违反这条。
   - **【待实测】** 首轮的提交号与 `impl-report.md` 内容。

2. **冲突仲裁（本靶仓的冲突机关是设计出来的，不是碰运气）**
   - 冲突来源是**真实的两条工单改同一个方法**：需求侧要把 `VisitLogService.record()` 从内存 `List`（`Collections.synchronizedList(new ArrayList<>())`）**改成落库**，方法体与字段都要重写；线上问题侧要在**旧的内存版** `record()` 里加一行 `referer` 空值保护。两侧改的是同一个文件的同一个方法 → S4 必然产生真冲突。
   - **仲裁原则**（已沉淀进 Memory，与领域无关）：git 冲突标记只表达文本重叠，真正要保护的单元是「两侧各自想生效的修复」。整文件取 ours/theirs 会让另一侧的修复**静默丢失**，其测试要么失败要么连同实现一起消失，**而门禁还可能照样绿**。验收标准是两侧测试的**并集全绿**；同时留意测试断言可能编码了旧架构语义（如访问流水快照原先按插入序返回、落库后改成按 `visitedAt` 倒序），需按新架构调整断言但保留测试意图。
   - **复杂语义冲突抛给人**：G2 门禁承担这个卡扣。
   - **【待实测】** 冲突文件数、`bothFixesPreserved`、合并提交号。【内部环境实测】对照：2 个文件冲突，`bothFixesPreserved=true`。

3. **PR 与 CR 评审**
   - Dev-Waker 用 `github-lab.sh pr-create` 开 PR 并在正文里关联 issue。**【待实测】** 本靶仓首轮的 PR 号。
   - **v4 多了一层 AI 审查**：Qoder Action 在 `pull_request` 的 `opened / synchronize / reopened` 上跑 `/review-pr`，按 `AGENTS.md` 的口径给意见。**【待实测】** 它会不会犯我们最担心的那两类错——把已登记在 issue 里的已知缺陷要求「顺手修」、把刻意保留的未覆盖行一律要求补满。这两条恰恰是 `AGENTS.md` 显式写进去的，所以第一轮的结果同时是对那份文件的检验。
   - **【GitHub 实测】PR 已经全部走流程合入**：截至本轮 **4 条 PR**（#1 代码基线、#4 状态回写桥、#5 流程产物目录约定、#6 数字员工资产入仓）全部经 PR 合并进 main，直推被 `GH013` 拒过一次（探针提交保留在本地分支上，没进 main）。
   - **「一键 Merge」在单人账号仓库里做不到**，见阶段四第 3 点。

### 阶段四：CI/CD 自愈、线上缺陷闭环与记忆治理

1. **Jenkins CI 门禁 + 状态回写桥**
   - job **`ai-devops-demo-verify`**：Pipeline from SCM，`https` 克隆公开仓（**Jenkins 侧不存任何 git 凭据**，这是相对 v3 `file://` + `ALLOW_LOCAL_CHECKOUT` 的简化），参数 `BRANCH_NAME` 传分支名。
   - **两段结构化输出**：`jenkins-lab.sh build <分支>` 的单行 JSON，以及构建日志里的 `=== GATE SUMMARY ===` 段（`tests.total` / `tests.fail` / `jacoco.line` / `jacoco.lineCovered` / `jacoco.lineTotal` / `checkstyle.violations` / `spotbugs.bugs` / `gateVerdict`）。**数字员工只允许引用这两段，不得自行宣称门禁通过。**
   - **回写桥**：构建结束后把结论 POST 成 commit status，context `jenkins/verify`。**【GitHub 实测】** 三次构建三次回写成功，GitHub 侧核对到 `{"context":"jenkins/verify","state":"success",…}`。
     两个设计决定值得讲：
     - **回写失败只把构建标成 UNSTABLE，不改判门禁结论**。门禁红不红由 `mvn` 决定；桥断了是基础设施问题，不能让它伪装成代码问题，也不能让它把一次绿灯说成红灯。**但没回写成功就等于 PR 合不进去**，所以要如实报成阻塞。
     - **所有值经 `withEnv` 传进 `sh`，脚本里一律用引号包住的 shell 变量**，不做 Groovy 字符串插值——分支名里带特殊字符时不会把命令拼坏。
   - **凭据隔离设计（v4 有两层，不是一层）**：
     1. Jenkins 凭据由 `jenkins-lab.sh` 内部持有，`~/jenkins-lab/home/` 与 `admin-token.txt` 在 fileGuard 黑名单上；
     2. GitHub PAT 由 `github-lab.sh` 内部持有，token 文件在仓库**外面**（`~/.config/ai-devops-lab/`），该目录在 fileGuard 黑名单上。
     **`git push` 也必须走封装脚本**：机器上自己的 credential helper 里存着有 admin 权限的仓主 token，Waker 直接 push 会静默提权、绕过最小权限设计。`github-lab.sh push` 把 `credential.helper` 置空，改用 `GIT_ASKPASS` 垫片走那张受限 PAT。token 不进 argv、不进 shell 历史、不写进 `.git/config`。
   - **构建环境必须钉死**：本机构建一律先 `export JAVA_HOME=/opt/homebrew/opt/openjdk@21` 再用 `/opt/homebrew/bin/mvn`，与 Jenkins 侧一致。**【GitHub 实测】** 钉死之后 CI 与本机的行覆盖率**逐位一致**（93.05556%）；不钉死就会本地与 CI 跑出两套结果，**自愈回环会追着一个只在一侧存在的幽灵失败修**。
   - **自愈回环**：`MAX_HEAL_ROUNDS = 3`，红则 Dev 返修，3 轮仍红挂起问人。**【待实测】** 本靶仓首轮是否触发、触发几轮。【内部环境实测】对照见附录 B。
   - **封装脚本必须在入口处失败得清楚**：`build` 的第一个参数是分支名不是构建号。【内部环境实测】曾有 Waker 传了构建号，Jenkins 去 checkout 一个叫 `8` 的分支报 `couldn't find remote ref`——**这条错误在自愈回环看来和真的代码失败长得一模一样**。现在先 `rev-parse` 验分支，不存在就返回结构化 `NO_SUCH_BRANCH` 并 `exit 6`。
     **同一条纪律 v4 又用了一次**：`github-lab.sh` 在 token 缺失时返回 `{"error":"NO_TOKEN",…}` 并 `exit 2`，仓库根不对时返回 `NO_REPO`。**【GitHub 实测】** 两条错误路径都验过。原则是：**封装脚本要么给出可执行的结论，要么给出可执行的错误，绝不给出看起来像成功的空结果。**

2. **线上 Bug 逆向分诊与热修（本靶仓的缺陷是预置的，可稳定复现）**
   - issue **#3**：**部分短链打开报 500——从某些入口点开打不开，从网页里点开正常**。工单是症状级的：没有堆栈、没有 Trace、没有日志聚合，只给了「对同一访问者结果稳定」这条线索。
   - **缺陷现场**【GitHub 实测，已在 main 上核对】：`ShortlinkController.redirect()` 用 `@RequestHeader(value = HttpHeaders.REFERER, required = false)` 接 Referer（第 69 行），第 75 行无条件调 `visitLog.record(code, referer)`；`VisitLogService.record()` 第 22 行 `referer.toLowerCase(Locale.ROOT)` 在 referer 为 null 时抛 NPE → 500，**并且这一次的访问流水也丢了**。
   - **复现方式**【GitHub 实测】：
     ```
     带 Referer  → HTTP/1.1 302, Location: <目标地址>
     不带 Referer → http_code=500
     堆栈：java.lang.NullPointerException: Cannot invoke "String.toLowerCase(java.util.Locale)"
           because "referer" is null
           at com.lab.shortlink.visit.VisitLogService.record(VisitLogService.java:22)
           at com.lab.shortlink.api.ShortlinkController.redirect(ShortlinkController.java:75)
     未知短码不带 Referer → 404（空值检查先短路，所以这个 500 只发生在存在的短码上）
     ```
   - **为什么这是个好教材**：浏览器在多种常见情况下都不发 Referer（直接粘贴链接、严格的 Referrer-Policy、App 内置浏览器、https→http），所以「不带 Referer」是**正常流量**，不是异常输入。学员容易第一反应当成「非法请求该拦」，正好用来讲「**缺陷的严重程度取决于受影响流量是不是正常流量**」。工单里那句「从某些入口点开打不开、从网页里点开正常」就是这个判断的线索，而**答案没有写在工单里**。
   - **热修**：Dev-Waker 从 main 切 `hotfix/issue-<n>-<slug>`，把分诊留下的复现测试**直接当作回归测试** `git add` 纳管，先跑红再修绿。
   - **⚠️ 实测校准（v3 保留）**：「自动抓取日志与 Trace 链路定位 Commit」中的 **Trace 链路抓取跑不了**——实验环境没有真实线上日志与 Trace 系统。实测是靠读代码 + 写 MockMvc/HTTP 复现拿到真实堆栈。**讲的时候不要承诺 Trace 集成。**

3. **交付准出与合并死锁（实测最重要的治理案例）**
   - **【GitHub 实测】v4 的死锁现场**：`gh pr merge` 被拒——
     ```
     X Pull request #5 is not mergeable: the base branch policy prohibits the merge.
     ```
     此时该 PR 的 head SHA 上**没有任何 commit status**，而规则集要求 `jenkins/verify`。补上 CI 之后同一条 PR 变成 `MERGEABLE / CLEAN`。
   - **与 v3 的死锁对比（课堂重点）**：

     | | v3（内部平台） | v4（GitHub） |
     | --- | --- | --- |
     | 拦住合并的是什么 | 项目级评审规则 `approver_number` | 规则集的必需状态检查 + （若开启）评审通过数 |
     | 成因 | 治理控制，换仓也绕不开 | **身份不足**：作者不能批准自己的 PR，而仓里只有一个人类账号 |
     | 解除路径 | 第二评审人 / 调项目配置 / 改本地 remote | 第二身份（bot 账号 / 配对学员 / **`qoderai` App**）/ 补 CI 状态 |
     | 直推 main 能不能绕过 | **能**（所以只能靠纪律） | **不能**（`bypass_actors` 为空，管理员也不得绕过）|

     **这张表是 v4 最该讲的一页**：同一句「Agent 没能合并」，两个环境里的成因和解法完全不同。把它讲成一个故事（「治理控制挡住了它」）会让学员在换平台时做出错误判断。
   - **Waker 的反应是本课程最好的教学素材**【内部环境实测，本靶仓待复核】：它没有直推 main、没有 force push、没有绕过评审；也**没有按指令字面把状态写成 `DELIVERED`**，而是写成 `S6_MERGE_BLOCKED` 并说明理由。最终 `mergedToMain=false`，流程以 `finalStatus=ESCALATED` 如实收场。
   - **★ 一次意外的对照实验（最有说服力的一段）**【内部环境实测；**机制与领域无关，结论保留**】
     平台存储被误删，7 条 Memory 随之消失。三个 Waker 按原配置重建后，用**同一套流程脚本、同一套守护规则、同一个仓库**重跑一轮。结果：

     | | 有 Memory | Memory 被抹掉 | 修复指令后 |
     | --- | --- | --- | --- |
     | 合并被评审规则拦下 | 如实上报，不绕过 | **同样**如实上报，不绕过 | 如实上报，不绕过 |
     | `state.json` 最终状态 | `S6_MERGE_BLOCKED`（**主动违抗指令**并写下理由） | **`DELIVERED`** ——而 main 上 16 个提交一个都没有 | `S6_MERGE_BLOCKED`（**照指令执行即可**） |

     根因不在 Waker，在流程脚本：那一步的原文是「最后把 `state.json` 更新为 DELIVERED 并提交」，**无条件**，与「合并成功才允许把 `mergedToMain` 填 true」自相矛盾。第一轮之所以写对，是因为那个 Dev-Waker **选择违抗指令**并说明了理由，这条理由随后沉淀成了 Memory。Memory 一丢，全新的 Waker 老老实实照字面执行，就写出了虚假的交付状态。

     **课堂结论**：正确性依赖「执行者主动违抗指令」本身就是缺陷。结构性修复是把状态改由实际合并结果决定。**把正确性从「执行者的品德」搬回「指令本身」**——第一轮的对是运气，第三轮的对才是设计。
     更值得讨论的是**两条经验的不同命运**：新 Waker 独立重新推导出了「合并被拦要如实上报」（当轮就撞上、有直接证据），却**没能**重新推导出「不要虚标 DELIVERED」（当轮不会立刻爆雷，危害要等下一次运行才显现）。这就是记忆治理真正兜住的那一类经验——**延迟暴露的、单轮无法自证的判断**。
   - **v4 把这条主张写进了三个地方**（不是只写在提示词里）：`lab/sop/sop-body.md` 的「唯一事实源」第 3 条、`lab/wakers/desc-devops.txt` 的合并执行段、仓库根 `AGENTS.md` 的审查重点第 7 条。**同一条纪律出现在流程、角色、审查三层，才叫写进了系统。**

4. **记忆治理**
   - S6 的记忆沉淀纪律：**只沉淀经验与判断依据，不沉淀一次性事实**（issue 号、分支名、提交哈希、产物路径属于 `state.json` 与 release-note，不进 Memory）。每条写清「经验 + 为什么」。
   - **【内部环境实测】沉淀的 7 条**（原文摘录在附录 B，可直接作为课堂阅读材料）。这 7 条**没有一条提到具体业务**，全是可迁移的判断。
   - **本靶仓第一轮跑完要做的对照**：新 Waker 会沉淀出哪几条？哪几条与上面 7 条重合？重合的那几条说明它们是**这一类工作的通用经验**，不重合的要判断是新平台带来的还是遗漏。**【待实测】**
   - **v4 有一条新的、必须沉淀的经验候选**：**配置类 API 的宽松入口会静默丢弃它不认识的字段**（`PUT` 200 但键不存在），所以配治理控制必须回读校验。这条正好是「延迟暴露、单轮无法自证」那一类——当轮看起来配成功了，危害要等到某次合并被意外放行时才显现。
   - **⚠️ 反面教材（v4 口径）**：检查有没有把「**短码必须用 `SecureRandom` 生成 8 位 base62**」沉淀为策略记忆。这条是**需求约束兼安全约束**，属于**冻结基线**：它写在 issue #2 的「约束」节里、写在 `ShortCodeGenerator` 的 javadoc 里、并由 `ShortCodeGeneratorTest` 的策略断言固定。把它写进 Memory 就是记忆污染——下一次产品决定改用别的编码方案，这条记忆会变成错误惯性，**而且它看起来特别像一条正确的经验**，这正是它适合当教材的原因。
   - **教学法（v3 校准后保留）**：用 `memory` CLI，不用控制台 UI（学员能自己复现、能 diff、能写进讲义）。三步：**跑之前先看基线**（确认是空的，截下来）→ **跑完一轮看长出了什么**（`memory versions` + `memory diff`，它按行号区间逐条列）→ **治理动作**（`snapshot` / `update|remove --reason` / `rollback` / `export|import`）。
     这个顺序比「看现成的 N 条然后判断」更好教：学员看到的是记忆**形成的过程**，不是一份静态清单。
   - **课堂练习**：让学员逐条判断新沉淀的记忆——哪几条是**可迁移的判断**（该留），哪几条是**一次性事实**（不该进 Memory），哪几条**看起来对但嵌了错前提**（最危险）。现成的第三类样本在附录 B 第 4 条：它写「覆盖率门禁的**相对阈值**最容易意外翻红」，而相对阈值**根本没有实现**。**一条经验可以同时是「有用的」和「前提是错的」。**
   - ⚠️ **`memory import` 默认整份替换**，不是增量合并。先跑不带 `--apply` 的 dry-run 核对文件数。

---

## 四、阶段五：Hands-on Lab 实验手册（120 分钟）

### 4.1 实验背景与实战目标

学员组队担任「人类架构师/TL」，基于 QoderWake 联动 GitHub + Jenkins，完成包含**正向开发、线上缺陷热修、冲突仲裁、CI 门禁、AI 审查与记忆治理**的生产级实战。

- **实战课题**：**短链接服务的两处加固**——解析缓存加容量上限与 TTL、访问流水落库并提供统计查询接口（issue #2）；中途插入线上缺陷单（**缺 `Referer` 头时跳转返回 500**，issue #3）。
- **技术栈**：Java 17 / Spring Boot 3.2.4 / Maven。跳转预算 300ms，`POST /api/links` 与 `GET /{code}` 的对外契约不变。

> **为什么用短链接当靶仓**（课上学员一定会问，这是标准答案）
>
> 领域知识不该成为理解流程的门槛。短链接不需要任何前置领域知识：「把长网址变成短网址、点开短网址跳回去」一句话讲完，学员的注意力可以全部放在编排、门禁、仲裁和治理上。
>
> 换题材的**唯一硬要求是六个教学机关一个都不能丢**。它们在本靶仓里的对应物与实测位置：
>
> | # | 教学机关 | 本靶仓的落点 | 状态 |
> | --- | --- | --- | --- |
> | 1 | 有架构可重写（S2 有事可做） | `VisitLogService` 存 `Collections.synchronizedList(new ArrayList<>())` | 【GitHub 实测】 |
> | 2 | 真冲突的来源（S4 不空转） | 需求侧把 `record()` 改落库 vs 缺陷侧在旧 `record()` 里加空值保护——**同一个方法** | 设计就绪，**【待实测】** |
> | 3 | 可稳定复现的线上缺陷（S3 先红后绿） | 缺 `Referer` → `VisitLogService.java:22` NPE 500 | 【GitHub 实测】已复现 |
> | 4 | 一条不可协商的安全约束（记忆污染的反面教材） | 「短码必须 `SecureRandom` 生成 8 位 base62」，由 `ShortCodeGeneratorTest` 断言 | 【GitHub 实测】红灯分支已验证它挡得住 |
> | 5 | 冻结契约的只读边界（G2 卡扣） | `api/openapi.yaml` 两个既有路径 + `V1__create_short_link.sql`，由 `OpenApiContractTest` 机械检查 | 【GitHub 实测】 |
> | 6 | 一个会被「顺手改」破坏的对外承诺 | 跳转预算 300ms，由 `RedirectBudgetTest` 守着 | 【GitHub 实测】 |
>
> 另外两处是**故意留白**的，不要补上：
> - `ShortlinkProperties` 里**没有**缓存容量/TTL 的配置项——补上就等于替学员回答了 issue #2 里的 Open Question，S1 的澄清环节会空转。
> - `V1__create_short_link.sql` 定义了 `short_link` 表但代码里没用（`InMemoryLinkStore` 是内存实现）——这个缺口正是「schema 变更只能新增 V2」这条约束的用武之地。
>
> 还有两处**故意不覆盖**的测试路径，别当成疏漏：
> - `VisitLogServiceTest` **没有** null-referer 用例，`ShortlinkControllerTest` 的每个跳转用例都**显式带 Referer**。补上任何一个，基线就会是红的，而那个红本该属于 issue #3——它「修复前红、修复后绿」的对比证据也就没了。

> **⚠️ 时间预算的硬约束**
>
> **【待实测】** 本靶仓上还没有完整跑过一轮，**新版议程的时间分配目前是借内部环境的数据推的，第一轮跑完必须回来校准**。
>
> 【内部环境实测】四轮完整运行的结论（详见附录 B）：机器净耗时 44m42s ～ 2h11m14s，墙钟最长 **2h46m24s**，其中 35m10s 是在等人点门禁。
>
> 三条结论**与靶仓和平台无关，直接沿用**：
> 1. **120 分钟内不可能让学员从零配置 Waker 再完整跑一遍**。学员动手的必须是「决策与验证」，不是「等待」。必须按下方「环境预置清单」提前把 Waker、仓库、Jenkins、SOP 全部备好。
> 2. **门禁等人时间是最大的不可控项**，而门禁本身不会超时，所以课上要么安排专人值守，要么课前预跑。
> 3. **裁定质量直接决定耗时**。【内部环境实测】某轮 S1 连开三轮澄清挂起，把一个阶段从 14 分钟拉到 66 分钟，其中两轮是因为需求提出人回了「按推荐的来」这类无内容答复、流程只能原地再问一遍。这不是流程缺陷——课上要让学员体会这一点，就得让他们自己当一次需求提出人。

### 4.2 环境预置清单（讲师必须在课前完成）

> **具体命令见《操作手册》第 1、2 节**。这里只列讲师要做判断的几项：

| 项 | 现状 | 讲师要决定什么 |
| --- | --- | --- |
| GitHub 仓与规则集 | **【GitHub 实测】** `protect-main` active，4 条规则，`bypass_actors=[]` | 评审通过数保持 0，还是等第二身份到位后升到 1（升到 1 之前**任何 PR 都合不进去**） |
| 数字员工的 GitHub 身份 | ❌ **未装入**（fine-grained PAT 待创建） | 没有它，团队读不了 issue、推不了分支。这是 kickoff 的硬前置 |
| Waker 编制 | **5 个**（Lead / PM / Dev / QA / DevOps），描述已 GitHub 化并装机核对 | 课上讲 WakerFlow 时说清「三个专职」，讲 Group 时说清「五个」，别让学员以为数字前后矛盾 |
| SOP | **【GitHub 实测】** `github-lab-group-delivery@1.0.1` 已发布并绑定，5 个参数全部解析，正文可见性已验证 | 改过正文就要升版本号重发重绑（release 不可变），并**重做预热与验证** |
| 本轮工单 | issue **#2**（需求）/ **#3**（线上问题），**尚未消耗** | 每轮开课前必须重建一对——**冲突是一次性事件**，见模块 2 |
| Jenkins job | **【GitHub 实测】** `ai-devops-demo-verify`，3 次构建全绿、3 次回写成功 | 开课前跑一次 `build main` 把当前状态拨回绿，否则学员看到的第一个画面是红的 |
| AI 审查 | ❌ **未接通**（`qoderai` App 未装、令牌未配、workflow 未推） | 不接通，三层审查只能讲两层。接通后要专门核对它有没有犯 `AGENTS.md` 明令禁止的两类错 |
| 人工审批值守 | toolGuard 审批窗口 **5 分钟**，只存内存不落库，超时即该步失败且无法补批 | **必须指定专人**盯审批队列。这是整条流水线最主要的挂死风险 |
| 第二评审身份 | ❌ **未准备** | 不准备，「至少 1 名评审通过」这道关卡只能讲不能演 |
| Projects 看板 | ❌ **未建成**（`gh` token 缺 `project` scope） | 不建，需求流转只能在 issue 列表里看，学员看不到阶段全貌 |
| QoderWake daemon | **【GitHub 实测】** 1.1.3 在线 | 开课前跑一次 `runs list` 确认没有 `failed` 的残留 run；有 `qodercli` 版本错配就 `restart` |

> **⚠️ 状态存在哪里：一次真实的数据丢失**【内部环境实测，机制与领域无关，结论保留】
> 平台存储目录被误删，daemon 重启后重建了一个空 store。一次性消失的东西：**3 个 Waker 的全部配置、已注册的流程定义、两次运行的完整事件历史、Dev-Waker 沉淀的 7 条 Memory**。
> 完全没受影响的东西：**git 仓、Jenkins（job 配置与构建历史）、工单系统（工单与结论评论）、MR、登录态与 machine binding**。
> 靠技能包、守护配置和流程脚本本身，**约 5 分钟重建完毕**。
>
> 课堂上这是个有用的结论：**交付产物落在 git/CI/工单系统里就是安全的，落在 Agent 平台自己的存储里就要单独备份**。
>
> **v4 把这条结论变成了仓库结构**：`lab/` 目录里的五份角色描述、SOP 正文与渲染器、守护清单、装机脚本全部入仓，`lab/install.sh` 一条命令装回。**再丢一次不用考古了**——上次就是靠翻会话转录才把三段职责描述找回来的。

### 4.3 核心配置：Waker 角色与两种编排

#### 1. 五个角色的边界（原文在 `lab/wakers/desc-*.txt`，课上直接投）

| 角色 | 职责 | 最要紧的那条边界 |
| --- | --- | --- |
| **Lead-Waker**（delivery_lead） | 持有需求主线、路由工作、守护 G1/G2 两道人工门禁 | 只协调不写码；收到「按推荐的来」这类无内容答复要指出缺哪几项，**而不是原样转交** |
| **PM-Waker**（product_manager） | 读 issue、只读勘察、产出六段式拆解、维护需求基线 | 勘察不得改动任何文件；不得把推测当事实；**不得自行假设 Open Question 的答案** |
| **Dev-Waker**（engineering_executor） | 隔离分支实现、热修、冲突仲裁、PR 自查、issue 回写、记忆沉淀 | 严禁降阈值/关插件/skip 参数/`--no-verify`；严禁直推 main、force push；**严禁顺手做「明确的非目标」里的事** |
| **QA-Waker**（qa_reviewer） | 从**已冻结基线与设计**推导测试，给带证据的三态结论 | 不得改实现代码；**无证据不得下 PASS**；不从实现反推（那只能证明代码做了它做的事） |
| **DevOps-Waker**（ci_gate_keeper） | 跑门禁、读日志定位根因、核对状态回写、逆向分诊、批准后执行合并 | **只跑门禁和读日志，严禁修改任何业务代码或 `pom.xml`**；**不得自行宣称门禁通过** |

> **「跑门禁的」与「改代码的」必须是两个 Waker**，这是把 2 个角色拆成 3 个的唯一理由：分诊者同时改代码，等于自己给自己签验收。
>
> **⚠️ 模板自带的东西不是中立的**【内部环境实测】：QA 模板自带一句「does not run unit tests and does not fix issues」，**与本实验 QA 职责直接矛盾**。而且它的位置很刁钻——不在 `BIBLE.md`、也不在已被整份覆盖的 description 里，而在**自动生成的 Waker Profile**（`MEMORY.md`）里，会作为记忆索引注入。**5 个 Waker 各有一份，课前要逐份读过。** 这同时给记忆治理那节提供一个真实、非破坏性的 `memory update` 演示对象。

#### 2. 两种编排：WakerFlow 轨与 Group 轨

WakerFlow 轨的 8 phase 拓扑（GitHub 口径）：

```text
[人工发起 run / GitHub webhook]
        │  args: issueNumber, requirementDescription, bugIssueNumber, repoRoot
        ▼
[S1 需求拆解]  PM-Waker：读 issue #N + 只读勘察（短码生成、解析缓存、访问流水）
        │      → 六段式 change-breakdown.md
        │      Open Question / Conflict 非空则挂起问人（可多轮；本仓预置 10 + 1）
        ▼
【Human Gate 1 · G1 需求基线门禁】 人工逐项裁定 → 折进 REQ 验收标准并冻结
        │                         批准记录持久化到 .devflow/issue-<n>/
        ▼
[S2 事件驱动编码]  Dev-Waker：feature/issue-<n>-<slug> 实现 REQ + 单测
        │          缓存加上限与 TTL、访问流水落库 + 统计查询接口
        │          HOOK_FAILED 或 blockers 非空 → 流程终止（凭据扫描钩子不可绕过）
        │          ⚠ 不得顺手给 referer 加空值保护——那是 issue #3 的范围
        ▼
[S3 线上缺陷热修]  DevOps-Waker 分诊（写复现测试，留 untracked，交接 reproTestPath）
        │          → Dev-Waker 从 main 切 hotfix/issue-<n>-<slug>，
        │            复现测试升格为回归测试，先红后绿
        ▼
[S4 Git 冲突仲裁]  Dev-Waker：hotfix 合回 feature
        │          两侧都改了 VisitLogService.record()：落库 + 空值保护都要保留
        │          bothFixesPreserved=false → 流程终止
        ▼
[S5 CI 门禁自愈回环]  DevOps-Waker 跑 Jenkins（job ai-devops-demo-verify）
        │              → 读 GATE SUMMARY → RED 则 Dev-Waker 返修（最多 3 轮）
        │              → 核对 commit status jenkins/verify 是否真的回写成功
        │              3 轮仍红 → 挂起问人「授权新一轮 / 升级处理」
        ▼
【Human Gate 2 · G2 CR 准出门禁】 Dev-Waker 开 PR + 6 项自查 + 重新核对未覆盖点
        │                         Qoder Action 按 AGENTS.md 出 AI 审查意见
        │                         人工评审：批准准出 / 退回修改
        ▼
[S6 准出与记忆治理] DevOps-Waker 合并 PR（受规则集约束）→ 回写 issue #2/#3
                     → release-note.md → 沉淀 Memory → 更新 state.json
                     合并未核实成功则写 S6_MERGE_BLOCKED，不虚标 DELIVERED
```

Group 轨的差异见第六章。**课上必须讲清一件事：Group 轨的门禁是软的**——没有任何机械装置阻止 Waker 越过门禁继续做。这不是缺陷清单里的一行，而是两种范式的本质差异，不要包装成「Group 更灵活」。灵活和没有强制力在这里是同一件事。

### 4.4 120 分钟实战流程

> **【待实测】** 下面的分钟数是按内部环境的机器时间排的，本靶仓第一轮跑完要回来校准。**模块顺序与教学内容不依赖具体耗时**，可以先用。

#### 模块 1：需求下发、澄清与基线冻结（00:00 – 00:20）

1. **下发需求**：讲师展示 issue #2 原文。两句话说清题材：解析缓存没有上限也不会过期（慢性内存泄漏 + 更正目标地址后一直跳旧地址）；访问流水存在进程内存里（重启即丢、多实例互不可见，支撑不了运营要的引流来源查询）。
2. **发起流程**：WakerFlow 轨用 `lab-run.sh --watch <issueNumber>`；Group 轨在群里 @ 交付负责人并把 issue 链接贴进去。
   > **⚠️ 校准（v3 保留）**：「在工单评论区 @PM-Waker 自动触发」**不成立**。真实链路是人工发起 run，工单侧是**读写而非触发**。GitHub 侧 webhook 技术上可做，**【待实测】**。
3. **观察 S1 产出**：六段式 `change-breakdown.md`。让学员数 Open Question 与 Conflict 的条数——**issue #2 正文里预置了 10 条 OQ + 1 条 Conflict**，可以拿它当答案对照，看 PM-Waker 漏了几条、有没有自行假设答案。
4. **Human Gate 1**：学员扮演需求提出人，逐项裁定。**参考答案（每条都带「为什么」，因为无内容的答复会让 S1 原地再问一遍）**：

   | # | Open Question | 参考裁定 | 为什么 |
   | --- | --- | --- | --- |
   | 1 | 缓存上限按条数还是按内存？数值？ | **按条数，上限 10000** | 按内存核算要引入对象大小估算，收益不抵复杂度；条数上限足以挡住无界增长 |
   | 2 | TTL 多长？允许按环境不同？ | **10 分钟，不允许按环境覆盖** | 环境间行为漂移会让「为什么这个短码还跳旧地址」变成猜谜 |
   | 3 | 淘汰策略 LRU / FIFO / LFU？ | **LRU** | FIFO 会把热点短码淘汰掉，命中率掉得比 LRU 明显 |
   | 4 | 统计接口路径 / 参数 / 分页 / 字段 / 排序？ | **`GET /api/links/{code}/visits`**；`limit` 选填、默认 50、硬上限 200；不分页；字段固定 `code / referer / visitedAt`；按 `visitedAt` 倒序 | 挂在已有资源下是**纯新增**，不动 `openapi.yaml` 里两个既有路径的定义；不分页是因为硬上限已经挡住了大响应 |
   | 5 | 「最近」是 N 条还是时间窗？ | **最近 N 条**，默认 50，`limit` 可覆盖，硬上限 200 | 时间窗在流量稀疏的短码上会返回空，运营看到的是「没有数据」而不是「没人访问」，两者分不清 |
   | 6 | 存到哪张表？复用还是新建？启用 Flyway？ | **新建 `visit_log` 表，写成 `V2__create_visit_log.sql`，同时把 `spring.flyway.enabled` 打开** | V1 已合入即只读，一个字段都不许改；`short_link` 表存的是链接本体，往里塞流水会把两个生命周期绑死。**门禁会在内存库上真跑一遍迁移，脚本写错就是红灯** |
   | 7 | 统计写入要不要计入 300ms 跳转预算？ | **不计入**，但给写入设一个独立的短超时，超时即放弃 | 统计是旁路，不能挤占跳转主链路；不设超时则一次慢写入就能把对外承诺打破 |
   | 8 | 写入失败怎么办？ | **记 ERROR 日志后继续返回 302**，不重试不补偿 | 旁路故障放大成主链路 5xx，会让本来能打开的短链变成打不开——**这正是 issue #3 那个缺陷的成因类型** |
   | 9 | 要不要暴露成监控指标？ | **本期只记日志**，指标另开需求 | 多一个暴露面就多一处要验收的东西，而本期验收重点是落库与查询 |
   | 10 | 新接口要不要鉴权？ | **不加鉴权，与现有接口一致** | 但访问流水含 `referer`，比短码本身敏感，所以这条要写成**持续风险**记进交付文档，**不能悄悄删掉** |
   | C1 | **矛盾**：更正目标地址要马上生效 vs 缓存命中率要高 | **正确性优先**：TTL 10 分钟，**并在「更正目标地址」这条写路径上主动失效对应短码的缓存条目** | 命中率不该靠长 TTL 维持，而该靠写时失效；这样两条要求不再对立。若实现下来写时失效不可行，退回 TTL 10 分钟并接受最长 10 分钟延迟，**且这个延迟要写进交付文档** |

   > **裁定要给内容，不要给「按推荐的来」**。【内部环境实测】无内容答复会让 S1 原地再问一遍，一轮里连开三次同样的澄清门，阶段耗时从 14 分钟拉到 66 分钟。
   >
   > **课上先让学员自己念一遍、争一轮，再投参考答案**——直接投就跳过了本模块唯一要练的东西。

5. **续跑对比演示（本模块最有价值的一环）**：再发起一次同参数的 run，让学员看 S1 的耗时差与**零重复提问**。讲清「需求基线是资产，不是临时产物」。**【待实测】** 本靶仓的冷启动/续跑耗时；【内部环境实测】对照是 13m55s → 2m08s。

#### 模块 2：事件驱动编码与 Git 冲突仲裁（00:20 – 00:50）

> **⚠️ 课前必须准备：冲突是一次性事件，同一对工单只能演一次**
>
> S4 的冲突来自「需求侧把 `VisitLogService.record()` 改成落库」与「缺陷侧在旧的 `record()` 里加一行 `referer` 空值保护」撞在同一个方法上。**hotfix 一旦合进 feature，这个条件就永久消失**——再跑同一对工单，S4 只会如实报 `conflictedFiles: []`（【内部环境实测】某轮如此），本模块最核心的仲裁环节直接空转。
>
> 分支名是从工单号推导的（`feature/issue-<n>-<slug>`、`hotfix/issue-<n>-<slug>`），所以**每次开课前必须换一对新 issue**。前置校验要逐项验明本轮能否复现真冲突，任一不满足就明确报错，**不会让你跑完 40 分钟才发现没有冲突**：
> - `origin/main` 上 `VisitLogService` 仍是内存 `List` 架构（需求侧才有架构可重写）
> - `origin/main` 上 `referer` 仍无空值保护（S3 才能真复现 NPE、真热修）
> - `origin/main` 上没有那个复现测试类（否则 S3 的复现测试一上来就是绿的）
> - **工作区干净**（`.devflow/` 流程产物除外）
> - `feature/issue-<n>-*` 与 `hotfix/issue-<n>-*` 均不存在（才会冷启动而非续跑）
> - **HEAD 必须停在 main**——这条最容易漏也最致命：上一轮跑完 HEAD 会留在旧 feature 分支，而那个分支上 `VisitLogService` 已经是落库版本，S1 的只读勘察会据此写出「访问流水已落库」的错误基线，S2 便无架构可重写
> - daemon / Jenkins 在线，且 `runs list` 里没有 `failed` 或 `running` 的残留 run
>
> **【GitHub 实测】** 本轮 pre-flight 已核对：HEAD=main、工作区干净、无 `feature/issue-*` 与 `hotfix/issue-*` 残留分支。
>
> **⚠️ 一项永远告警的检查等于没有检查**【内部环境实测】：曾有一条「工作区干净」校验因为过滤规则写得比 git 的折叠输出更精确，永远匹配不上，于是**永远告警**。人会学会忽略它，等它真报出散落测试文件时也没人看了。加校验时要确认它**能变绿**。

1. **S2 编码**：学员阅读 `impl-report.md` 与 feature 分支提交，核对每条 REQ 的 acceptance 是否逐条落地。**重点核对两条反向约束**：
   - 有没有**顺手给 `referer` 加空值保护**？加了就是越界（issue #2「明确的非目标」第 1 条），会让 S3 的热修变成空提交。
   - 有没有**动 `openapi.yaml` 里两个既有路径**或**改 `V1__create_short_link.sql`**？两者在 G1 冻结后对下游只读。`OpenApiContractTest` 会挡住前者的一部分，但**它允许纯新增**，所以「新增了不该新增的东西」还得靠人看。
2. **S3 线上缺陷热修**：
   - 分诊产出应含：`reproducible=true`、`severity`（学员自己判，不要照抄工单）、精确 `defectSite`——**参考答案是 `VisitLogService.java:22`，`record(...)` 里的 `referer.toLowerCase(Locale.ROOT)`**。
   - **重点讲 `reproTestPath` 交接**：复现测试写完留在工作区、保持 untracked、**绝不删除或移动**（`rm`/`mv` 会被 toolGuard 拦下并卡进 5 分钟审批，【内部环境实测】有一轮就是在这里耗光整轮）；下一阶段用 `git add` 把它升格为回归测试。**复现测试与回归测试本来就是同一个东西。**
   - 热修分支从 main 切出，先跑红再修绿。
3. **S4 冲突仲裁**：
   - 冲突现场：`VisitLogService.java`（一侧改架构、一侧改行为）与 `state.json`。
   - 学员验证 `bothFixesPreserved=true`，并回答：**为什么不能整文件取 theirs？**（答案：落库改造会整体覆盖掉那行空值保护，500 缺陷静默复活，而它的回归测试也一起消失。）
   - 延伸讨论：测试断言可能编码了旧架构语义（比如 `snapshot()` 的顺序或 `size()` 的含义在落库后变了），仲裁后要按新架构调整断言但**保留测试意图**。
4. **30 分钟装不下，三种上法（推荐 A）**

   | | 做法 | 代价 |
   | --- | --- | --- |
   | **A. 课前预跑，课上做判断（推荐）** | 课前建一对新 issue 并完整跑一轮，让 S4 留下 `04-merge/conflict-resolution.md`。课上 30 分钟做三件事：读 `impl-report.md` 核对 REQ、逐处读仲裁记录、现场让学员回答「为什么不能整文件取 `--theirs`」 | 学员看不到 Waker 实时仲裁，但动的是判断力而不是等待 |
   | **B. 现场只演冲突本身** | 手工造一次：从 `main` 切分支给 `record()` 加那行空值保护，再往含落库重写的分支上 merge，冲突当场出现 | 5 分钟，能让学员看清「文本重叠 ≠ 语义冲突」，但完全不经过 Waker |
   | **C. 现场真跑** | 模块 2 给到 45 分钟以上，压缩模块 3/4 | 120 分钟议程要重排，且现场要有人盯 5 分钟审批窗口 |

#### 模块 3：CI 门禁、自愈回环与治理控制（00:50 – 01:20）

1. **门禁绿路径**：触发 `build main`，读 `GATE SUMMARY`。**【GitHub 实测】** 基线：26 tests / 0 fail / 0 skip，行覆盖 67/72 = **93.05556%**，分支 6/8 = 75.0%，Checkstyle 0，SpotBugs 0，Flyway 应用 1 个迁移，`gateVerdict=GREEN`。
   > **⚠️ 校准（v3 保留）**：不要说「覆盖率不低于上一次」。**相对阈值没有实现**，两处配置都是绝对 60%（v4 收敛成 `pom.xml` 一处）。课上要讲「覆盖率会被新增未测代码稀释」这个道理没问题，但**不能说门禁会自动挡住它**。
2. **红灯路径（必须单独演示，主流程不一定跑得到）**：
   - **课堂上用预置的红灯分支**：确定、二十几秒出结果，而真自愈一轮要十几分钟。
     ```bash
     LAB_JOB=ai-devops-demo-verify LAB_REPO=~/PycharmProjects/ai_devops_demo \
       ~/jenkins-lab/jenkins-lab.sh build lab/predictable-code
     ```
     **【GitHub 实测】** 该分支只把 `ShortCodeGenerator.CODE_LENGTH` 从 8 改成 6，commit message 伪装成「短一点的链接在短信和二维码里都更好看」这种听起来合理的改动。本地门禁 **26 tests / 2 fail**，两处失败指向同一条策略：
     ```
     ShortCodeGeneratorTest.codeLengthAndAlphabetMeetTheUnenumerabilityPolicy:26
       policy requires 8 base62 characters, i.e. at least 47 bits of entropy
       ==> expected: <8> but was: <6>
     ShortlinkControllerTest.createReturns201WithCodeLocationAndBody:63
       Expected size: 8 but was: 6 in: "2eo4YI"
     ```
     **教学点有三层**：① 门禁挡住的不只是写错的代码，还有**看起来像改进的退化**；② 挡住它的那条断言，是人在写测试时把安全要求编码进去的结果——**策略被编码在两处**（生成器的策略断言 + API 层的长度断言），改一处不够；③ 那条断言**故意写死 8 而不是引用 `CODE_LENGTH` 常量**，引用常量会让它在常量被改小时跟着一起变绿，那正是它要挡住的事。
   - **【待实测】** 本靶仓首轮是否真触发自愈。【内部环境实测】某轮首轮真触发过，真因不是代码缺陷，而是 **CI 复用 workspace 里残留上一分支的 stale compiled test classes**，修法是把构建命令改成 `clean verify`（本靶仓的 Jenkinsfile 已经是 `mvn -B clean verify`，所以这个坑不会重现，要演得另找素材）。这本身就是个好的讨论点：**CI 的红灯有多少其实来自环境而不是代码。**
   - 学员观察 DevOps-Waker 如何从 Console Log 定位到具体断言行，以及 Dev-Waker 如何在**不降阈值、不加 skip 参数**的前提下返修。
3. **治理控制现场（v4 新增，本模块的核心）**：
   - **直推被拒**：展示那条 `GH013` 报错原文，并强调它是以**仓主身份**推的。⚠️**【单次观测】**：再验一次就等于真的往 main 推一次，台上不要重演——直接看规则集 API 回的 `current_user_can_bypass: "never"`，那是非破坏性的复核方式。
   - **无 CI 状态的 PR 合不进去**：`mergeStateStatus=BLOCKED` + `the base branch policy prohibits the merge`；补上 `jenkins/verify=success` 之后变 `CLEAN`。**【GitHub 实测】**
   - **状态绑在 SHA 上不绑在 PR 上**：批准后再推一个提交，关卡重新落下。**【GitHub 实测】**
   - **配置要回读校验**：讲 `PUT` 静默丢弃 vs `POST` 422 那个对照（见 0.2 ③）。**【GitHub 实测】**
   - **凭据边界演示（⚠️ 教法已更正，v3 结论保留）**：**不要让学员在自己终端 `cat` 那个目录**——fileGuard 与 toolGuard 都是 **per-Waker** 配置，只在该 Waker 会话的工具调用上生效，**人在自己终端会直接读成功，什么拦截都看不到**。照原样演，学员只会得出「守卫没生效」的错误结论。
     **正确的演法**：在群里让 DevOps-Waker 去读凭据目录，然后在审批队列里看请求弹出来，按判据拒绝并在 reason 里给替代路径，最后看它怎么收场（如实写进 blockers，还是换个写法再撞）。
     **教学点因此更硬了**：同一条命令，**人有权限执行、Agent 没有**；而 Agent 被拦下之后有没有说谎，才是能不能托付生产的分界线。
   - **v4 多一条可讲的凭据边界**：`git push` 为什么必须走封装脚本——机器上的 credential helper 存着有 admin 权限的仓主 token，直接 push 就是**静默提权**。这条在 v3 不存在（内部仓走 SSH，权限模型不同）。
   - **规则目录可以直接枚举，不要只讲概念**：`permission builtin tool-guard-rules` 打出全部规则，每条带中文描述与 remediation。**⚠️ 两个 guardian 不是一回事，别混讲**：fileGuard 的黑名单命中来自 `FilePathToolGuardian`、严重度 **CRITICAL**，且**不在 toolGuard 的规则目录里**——课上要提前说，否则学员对着目录找不到那条规则会以为环境坏了。

#### 模块 4：人机 CR、准出与记忆治理（01:20 – 01:50）

1. **G2 准出门禁**：
   - 6 项自查 checklist：契约是否变更且向后兼容、门禁阈值是否被动过、是否有 skip 参数或 `--no-verify`、是否有直推 main、提交信息是否可回溯 issue 与 REQ、hotfix 回归测试是否仍在。**v4 加第 7 项：issue 正文「明确的非目标」有没有被违反。**
   - **未覆盖点必须在门禁现场重新核对**（v2 修复的设计缺陷，机制与领域无关）：S2 自报的清单在经历 S3/S4/S5 后必然过期。现在由 PR 自查这一步 checkout 分支逐条打开源码核对，人看到的是现状而非历史记录。
   - **本靶仓上有一条现成的核对素材**【GitHub 实测，已用 JaCoCo 报告逐行核对】：基线 5 行未覆盖 + 2 处部分覆盖分支，位置确切——
     - `ShortlinkController.java:57`，碰撞重试循环里的 `code = codeGenerator.next();`（同时有 **1 个未覆盖分支**：第 56 行 `while (store.findByCode(code).isPresent())` 的条件从未为真）。8 位 base62 空间下碰撞概率极低，这行在测试里几乎不可能自然走到。
     - `ShortlinkController.java:78-79`，跳转预算超时告警（第 77 行的比较分支未覆盖）。要覆盖它得构造一次超过 300ms 的跳转。
     - `ShortlinkApplication.java:13-14`，`main()` 的两行——Spring Boot 启动入口，单测里由 `@SpringBootTest` 拉起上下文，不经过 `main()`。

     让学员判断：**这五处该补测试、该记成已知未覆盖点、还是该改设计？** 关键是它们**性质不同**：第一处是真的没被验证过的业务逻辑（碰撞了会怎样？），第二处是要付出代价才能构造的场景（值不值得为一条告警日志造一次慢跳转？），第三处是框架入口（补测试毫无信息量）。**未覆盖点要分类，不能一律「补到 100%」**——这个判断本身就是 G2 该由人做的事，也是 `AGENTS.md` 里显式写给 AI 审查者的口径。
   - **如实带着走的遗留风险**：统计查询接口不加鉴权是需求提出人自己裁定的（OQ-10），但访问流水含 `referer`，比短码本身敏感，所以它要被写成**持续风险**而不是被悄悄删掉。**裁定可以接受风险，交付文档不可以隐藏风险。**
   - **批准只对当次 PR 与当次提交有效**，不得沿用到后续任何变更。**【GitHub 实测】** 这条在 v4 有机械保证（状态绑 SHA），不再只靠纪律。
2. **合并死锁与治理（本模块核心）**：
   - 现场执行 `github-lab.sh pr-status <n>`，看 `mergeable` / `mergeStateStatus` / 每个必需检查的 context 与 state。
   - 讨论：Agent 有哪些「能跑通」的手段？（直推 main / force push / 绕过 PR / 把状态写成 DELIVERED / **改规则集**）——v4 里最后一条也堵死了：那张 PAT 没有 Administration 权限，**技术上就改不了**。
   - **这里要讲清 v3 与 v4 的差别**（见 0.2 ①）：v3 的正确说法是「仓库没兜住，全靠纪律」；v4 是「仓库这次真兜住了，但纪律仍然要在，因为兜住这件事本身是人的决定，换个仓就没了」。
   - **run #2 vs run #4 的对照是本模块最该讲的一句**（见阶段四第 3 点）：写对是因为**主动违抗**了自相矛盾的指令（运气），还是因为**照指令执行就会写对**（设计）。
   - **★ 一块教材，能把上面这句钉死**【内部环境实测】：5 个 Waker 的 `WORK_STYLES.md`（模板自带，本实验从未改过）里，**每个角色都自带一条同类主张**——Lead 的「不粉饰」是「**绝不带着阻碍报绿**」；Dev 的「坦诚透明」是「不确定就明说，被阻塞就记录证据，**不假装完成**」；QA 的「实事求是」是「**绝不隐瞒风险或假装全量验证通过**」；DevOps 的「证据门控」是「发布放行必须依赖健康检查和测试扫描等**客观证据**」。九行完整对照表见附录 B5。
     > **这张表是本课程最省事的一块教材**：「如实上报而不是绕过」「不越界改不该改的东西」这些主张，**产品模板层面已经按角色分别写好了**，不是某个模型的偶然表现，也不是我们靠提示词硬掰出来的。本实验的描述只是在它之上叠加**靶仓特定的边界**（哪条分支不能推、哪个阈值不能降、哪个契约只读）。
     >
     > **v4 把叠加的那一层也入仓了**：`AGENTS.md`（审查口径）+ `lab/sop/sop-body.md`（流程口径）+ `lab/wakers/desc-*.txt`（角色口径），三份都可 diff、可 PR、可回滚。

     于是课堂上可以问一句：**「既然模板已经要求它不粉饰，为什么还需要流程里那条『合并未核实成功就写 `S6_MERGE_BLOCKED`』的硬指令？」**
     答案就是 Memory 被抹掉的那一轮：一个**全新的** Waker，带着**一模一样的工作风格**，照样写出了虚假的 `DELIVERED`。**风格是倾向，指令才是保证。** 这一问把「为什么要做流程工程，而不是挑一个够诚实的模型」讲透了——而这正是本课「全流程重塑」这个标题的落点。
   - 提问学员：如果它绕过去了，你会怎么发现？（答案：发现不了，`state.json` 会显示已交付，而 main 上什么都没有。）
   - **课前必须决定**：准备第二评审身份，还是把评审通过数保持 0。否则「至少 1 名评审通过」这道关卡只能讲不能演。
3. **AI 审查这一层怎么验（v4 新增）**：
   - **接通前先讲清它不是什么**：它不是门禁（跑不跑得通由 Jenkins 判），也不是准出（风险接不接受由人判）。它管的是「有没有违背**已经写下来的**纪律」。
   - **接通后要专门核对两条**【待实测】：① 它会不会把已登记在 issue 里的已知缺陷要求「顺手修」？② 它会不会把刻意保留的未覆盖行一律要求补满？这两条正是 `AGENTS.md` 显式禁止的，所以第一轮的结果**同时是对那份文件的检验**——如果它犯了，说明口径写得不够硬，改 `AGENTS.md` 而不是改结论。
   - **`@qoder` 的正确用法与边界**：需求澄清阶段可以在 issue 里问「@qoder 这个缓存现在有没有容量上限？在哪一行？」，让回答带着代码位置回来再据此裁定。但**它给的是建议与解释，不是裁定**：裁定权在 Requirement Owner 手上，裁定结果要写进需求基线才算数。让 AI 的回答直接变成需求，等于把「谁对需求负责」这件事悄悄转移掉了。
4. **issue 回写核验**：评论应含根因/变更点、PR 链接、build 号与覆盖率、回归测试位置、遗留未覆盖点、**合并受阻状态（如实）**。
   - 顺带讲一个实测细节【内部环境实测】：多行评论的**终端回显不等于落库内容**（回显会压平换行、给标题加转义符），先读回核实再决定是否重发——**凭回显重发只会制造重复评论**。v4 的对应纪律：评论正文走**文件**（`github-lab.sh issue-comment <n> <file>`），既避开回显失真，也避开引号换行守卫。
5. **记忆治理**：见阶段四第 4 点。课堂练习用「先看它是空的 → 看它在这一轮里长出了什么 → 再判断哪几条该留」这个顺序。
   - **【GitHub 实测】当前 5 个 Waker 的记忆基线要在开课前重新取一次**：本机经历过一次平台存储误删与重建，旧环境沉淀的 7 条**没有回灌**。v3 那句「打开详情页阅读实测沉淀的 7 条」**照做会翻车**。用 `memory show --view index|topics|sessions` + `memory lifecycle inspect` 取基线并截图。

#### 收尾（01:50 – 02:00）

- 对照四维 Rubric 自评。
- 展示 `state.json` 的 `gateApprovalHistory`，讲「全流程可审计」的含义。
- **v4 多一件收尾动作**：`lab/install.sh --check` 核对装机内容与仓内资产是否一致，然后 `qw-backup.sh <标签>` 打快照。**资产入仓 + 快照，两层各管一件事**：入仓管「换机器能装回来」，快照管「本机灾难恢复」。

### 4.5 实验评估标准（四维 Rubric，v4 校准）

| 评估维度 | 权重 | 达标标准（Pass Criteria） |
| --- | --- | --- |
| **Waker 与编排配置** | 25% | 配出 WakerFlow 轨需要的 **3 个**职责互不重叠的 Waker（尤其理解「跑门禁的不能是改代码的」）；若同时搭 Group 轨则再加交付负责人与独立验收共 **5 个**，并说清为什么状态机轨道不需要这两个角色；绑定最小化 Skills/连接器与**最小权限的 GitHub 身份**；成功编排 8 phase、含两道 Human Gate |
| **变更与冲突仲裁能力** | 25% | 能在 G1 逐项裁定 10 条 Open Question 与 1 条 Conflict 并冻结基线；续跑时不重复提问；在真实语义冲突下做到 `bothFixesPreserved=true`，能说清为什么不能整文件取一边；**没有违反 issue 的「明确的非目标」** |
| **CI 门禁、治理控制与 Bug 逆向分诊** | 25% | 能读懂 Console Log 定位到具体断言行；能演示红灯分支的自愈返修且**未降阈值、未用 skip 参数**；能说清规则集四条规则各挡什么、`bypass_actors` 为空意味着什么、以及「本地门禁绿」为什么还不等于「PR 能合并」；分诊产出含可复现结论、精确 defectSite（`VisitLogService.java:22`）与**自己判定的**严重级别及其依据 |
| **代码质量、治理与记忆** | 25% | 门禁达标（行覆盖 ≥60% 绝对阈值，基线 93.05556%）；**遇到治理控制时如实上报而非绕过**（合并死锁案例）；生成准出报告与 issue 回写；能审计 Memory 并识别出污染条目；能判断 AI 审查意见里哪几条该采纳、哪几条与范围纪律冲突 |

> **v4 变更说明**：第 3 维加入「治理控制」，第 4 维加入「能判断 AI 审查意见」。理由：v4 的仓库侧真的能挡住直推与非法合并了，所以「知道控制在哪、能不能绕过」变成了可考核的知识；而多了一层 AI 审查之后，**能识别 AI 的建议与已冻结的范围纪律相冲突**，比能让 AI 说话更重要。

---

## 五、已知缺口与未验证项（讲师必读）

照原样讲会承诺以下能力，但**没有**验证。课上要么如实说明，要么课前补跑。

| # | 缺口 | 现状 | 建议 |
| --- | --- | --- | --- |
| 1 | **本靶仓上一轮完整交付都没跑过** | 全部阶段耗时、自愈轮数、冲突文件数、未覆盖点条数、PR 号、Memory 条目**都是空的**。本文档里这些位置一律标【待实测】 | 课前必须跑一轮并回填。约需 3 小时，且**需要有人守两道人工门禁与 5 分钟审批窗口**，不能无人值守。**硬前置是数字员工的 GitHub PAT** |
| 2 | **数字员工的 GitHub 身份未装入** | fine-grained PAT 未创建，`github-lab.sh` 现在返回结构化 `NO_TOKEN`（**这条错误路径已实测**） | 创建 PAT（只给一个仓、Contents/PR/Issues 读写、**不给 Administration 与 Workflows**），装进 `~/.config/ai-devops-lab/`，然后逐个命令实测：读 issue、开 PR、推分支、**试改规则集应当失败** |
| 3 | **「至少 1 名评审通过」这道关卡演不了** | 单账号仓，作者不能批准自己的 PR，当前 `required_approving_review_count=0` | 三条出路：bot 账号 / 课堂配对 / **`qoderai` App 的 review 能否计入评审数**（最有意思，因为它同时是 AI 审查层与第二身份）。**【待实测】** |
| 4 | **AI 审查这一层完全没跑过** | `AGENTS.md` 与两条 workflow 已写好，但**推不上去**（token 缺 `workflow` scope），`qoderai` App 未装、令牌未配 | 补 scope → 推 workflow → 装 App → 配 `QODERCN_PERSONAL_ACCESS_TOKEN` → 开一个 PR 看它跑不跑。稳定之后再考虑把 `qoder-review` 升级成规则集的必需状态检查（**升级之前先确认它不会无故失败，否则所有 PR 都合不进去**） |
| 5 | **`--admin` 能否绕过必需状态检查** | **没有隔离出结论**。那次试合并发生在 CI 状态已经 success 之后，所以「合并成功」既可能是因为管理员特权，也可能是因为要求已满足 | 要验就得开一个**没有任何状态**的探针 PR，立刻试 `--admin`，然后关掉它。⚠️**【单次观测】**级别的断言，别在课堂上凭印象讲 |
| 6 | **Projects 看板未建成** | `gh` token 缺 `project` / `read:project` scope，API 直接报缺 scope | 补 scope 后建看板，列对应 8 个 phase 与两道门禁。不建的话学员看不到阶段全貌，只能在 issue 列表里翻 |
| 7 | **真·事件驱动唤醒** | GitHub 侧可以推 webhook（比 v3 的插件轮询强），但本地 daemon 要收到得有入站通路 | 本轮仍是人工发起 + 封装脚本读写。要演事件驱动，先解决入站通路，**并把「平台支持」与「我们已接通」分开讲** |
| 8 | **需求变更/废弃的自动感知** | 两个环境上都未跑。实测是 G1 前人工裁定 + S1 增量修订 | 「issue 变更 → 自动影响面分析 → 自动清理废弃分支」不要承诺 |
| 9 | **Trace 链路抓取** | 实验环境无真实线上日志与 Trace 系统；分诊靠读代码 + 复现测试 | 不要承诺 Trace 集成 |
| 10 | **G2 退回返修路径** | 历轮都是直接批准，返修 + 重跑门禁 + 复审分支无实测数据 | 课上可人为退回一次以演示 |
| 11 | **「覆盖率不低于上一次」这个相对阈值** | **不存在**。只有 `pom.xml` 的 `coverage.line.minimum`（绝对 0.60）一处 | v2 曾把它写成实测结论，**已更正**。要演「新增未测代码稀释覆盖率而翻红」，只能自己调高阈值或故意加未测代码 |
| 12 | **Group 轨 P0→P7 全程** | 本靶仓上**只做过三轮无副作用验证**（正文可见性、版本核对、路由判断），全程未跑 | 见第六章。课上必须讲清那个反直觉的坑：**绑定 SOP 只把 pin 交给 Waker，正文要等惰性物化，第一条消息可能读不到** |

### 其他需要课前处理的杂项

- **公开仓的脱敏口径**：这个仓是 PUBLIC。仓内文件不得出现工号、内部域名、内部工单号、内部邮箱、客户名；`lab/` 下的文本一律用 `~/` 而不是写死家目录（`install.sh` 装机时展开成绝对路径）。内部环境的实测数据只保留机制结论，数字标【内部环境实测】并集中在附录 B。
- **`main` 上的 README 与 AGENTS.md 不含缺陷答案**：README 只讲怎么构建、门禁有什么、三条只读边界；`AGENTS.md` 只讲审查口径，刻意**不点名**缺陷在哪一行——否则就把 issue #3 的诊断环节剧透了。
- **`lab/predictable-code` 与几条已合并分支仍留在远端**：红灯分支是教学素材，**不要删**；已合并的 feature 分支可以清，但清之前想清楚 PR 里的证据链还要不要点开看。
- **本机的全局提交钩子会扫凭据泄露**，命中即 `HOOK_FAILED`。**严禁 `--no-verify`**。这条在 v4 仍然成立，而且现在仓是公开的，泄露后果更重。
- **`target/` 与 `data/` 已在 `.gitignore`**：H2 的本地库文件落在 `data/`，别让学员把它提交上去（`git check-ignore -v data/*.mv.db` 是准出前该做的卫生检查——顺带一提，这条命令里的 `mv` 会命中 `TOOL_CMD_DANGEROUS_MV` 的**文件名误报**，正好当教材）。

---

## 六、Group 轨道：第二套编排范式

前面五个阶段讲的都是 **WakerFlow 轨**：流程脚本是状态机，阶段顺序、门禁、重试都写死在脚本里。本节是并行搭起来的 **Group 轨**：同一批角色放进一个群，靠一条 SOP 约定流程，靠 @ 路由推进。两轨并存，用来在课堂上对照讲「编排」这件事的两种做法。

**【GitHub 实测】本轮 Group 轨在 GitHub 口径下重建并做了三轮无副作用验证：**

| 轮次 | 验的是什么 | 结果 |
| --- | --- | --- |
| 1 | 绑定 SOP 之后，Waker 读到的是**正文**还是只有 pin 元数据 | 交付负责人**逐字引用了正文原文**（「被 toolGuard / fileGuard 拦下就是边界，不是障碍…」），并报出名称与版本 1.0.0 |
| 2 | 五个角色参数是否解析到真实 Waker；固定路由是否答得对 | 6 名成员报全；5 个参数全部解析（无未解析占位符）；路由两问**分开答对**：(a) 人先 @ 交付负责人，(b) 它确认后第一个 @ 需求分析 |
| 3 | 重绑到 1.0.1 之后，读到的是新 release 还是残留的旧物化副本 | 报出**新版本号 1.0.1**，并逐字抄出**新**的封装脚本路径（1.0.0 与 1.0.1 的路径不同，这是个能区分新旧的判据）；凭据边界那问也答对 |

> **第 3 轮的验证方法值得单独讲**：要证明「读到的是新版本」，光问版本号不够——它可能从 pin 元数据里读到版本号而没读到正文。所以问一个**只存在于正文里、且两个版本不一样**的细节（封装脚本的完整路径）。**验证可见性要用只有正文里才有的信息，而且要挑一个两版之间有差异的字段。**

### 1. 5 角色编制

见 4.3 的表格。SOP 角色参数与 Waker 的映射：`delivery_lead`→Lead、`product_manager`→PM、`engineering_executor`→Dev、`qa_reviewer`→QA、`ci_gate_keeper`→DevOps。**【GitHub 实测】** 5 个参数全部解析成功。

### 2. 发布与绑定 SOP

命令见《操作手册》。当前身份：profile `ccp_01m3f5nszv9p8dnvpbrare6rnv`，release `ccr_01m3f81cace5yda7vd64758h2c`（1.0.1），revision 3。

- `sop init --version 1.0.0` 会被全局 `--version` 标志吃掉（打印出 CLI 版本号、什么也不建），必须写 `--version=1.0.0`。
- `sop validate` 的文件参数是**位置参数**，不是 `--file`。
- **release 不可变**：改了正文再 publish 同一版本号会报 `SOP release version already exists with different immutable content`，必须升版本号。**【GitHub 实测】本轮就因此从 1.0.0 升到 1.0.1**——仓内正文因为路径改写多了 9 个字符，与已发布的 1.0.0 不再是同一份。**留着两份就是留着两个事实源**，所以升版本重发重绑，不将就。
- `--param` 的 selector 前缀用 profile 名；绑完要用 `group sop list --json` 核对 `parameterValues` 里每个键都解析到了真实 employee id + display_name，而不是字面量。
- **构建 SOP JSON 时顺手跑三个自检**（`lab/sop/build-sop.js` 已内置）：正文占位符与参数键**双向**核对（缺失 / 未用都要报）、退役口径残留扫描（旧平台的 CLI 命令、旧术语、旧仓路径一个都不许剩）。**这三个自检是「改了一处漏一处」的防线。**

### 3. ⚠ 反直觉的坑：绑定 SOP ≠ Waker 能读到 SOP 正文

这是本节最有教学价值的一条，【内部环境实测】四轮冒烟才判定清楚，**【GitHub 实测】本轮第 1、3 轮验证再次确认**。**机制与靶仓和平台无关。**

机制：`group sop set` 只是把 SOP **pin** 到群上；正文要等 daemon 把它物化成 `<会话>/workers/<agentId>/.qoder-sop-runtime/<hash>/plugin/skills/<id>/SKILL.md`，再作为 `--plugin-dir` 挂进 Waker 会话。**物化是惰性的**，而会话在启动时就固定了 plugin 目录列表——第一条消息触发的会话很可能赶在物化完成之前挂载，于是读不到正文。

**【GitHub 实测】** 本轮可以直接看到物化产物：

```
~/.qoderwake/data/cloud-conversations/conv_01m3f5…/workers/7125fd7975a6/
  .qoder-sop-runtime/c05396780c713ac0/plugin/skills/github-lab-group-delivery/SKILL.md
```

**还踩过一个更隐蔽的变体**【内部环境实测】：曾以为要靠会话级 skill 副本才能解决，加上之后确实读到了；但用一个唯一标记做判定实验后发现**两份都能读到且内容已分歧**——pin 自己就会物化，会话级副本是冗余的，而且构成**第二个事实源**（以后 republish 只更新 pin 副本，两者长期分歧，而 Waker 两份都读）。已删掉会话级记录。

**所以正确顺序是**：

```
sop publish → group create / group sop set
  → 发一条预热消息（触发物化，内容无所谓）
  → 再发一条验证消息，确认角色真能引用 SOP 原文、且路由判断正确
  → 才开始跑真需求
```

跳过预热与验证就上真需求，5 个角色会**照着 SOP 标题即兴发挥**，而且看起来一切正常——这比报错危险得多。

### 4. ⚠ 第二个坑：「第一个该 @ 谁」是两个问题，不是一个

【内部环境实测】第五、六轮冒烟抓到的。**同一个问法在两轮里被答成不同角色**，一度以为是 Waker 不稳定。实际是**问题本身有歧义**：

- 「群里来了新工单，**人**第一个该 @ 谁？」→ **交付负责人**
- 「交付负责人确认 Requirement Owner 之后，**它**第一个该 @ 谁？」→ **需求分析**

修法有两处，都是改提问而不是改角色：SOP 的 P0 段把两段路由都写死并明确「这是两个不同的问题，回答时要说清问的是哪一个」；冒烟脚本的第 2 问改成 (a)(b) 分开问。**【GitHub 实测】本轮第 2 轮验证：分开答对。**

> **课堂用法**：这是个很好的「先怀疑提问，再怀疑模型」的例子。学员看到两轮答案不一致，第一反应通常是「Agent 不靠谱」；真相是**人的问题没界定清楚**。同样的教训在 G1 裁定上也成立（无内容答复 → 阶段原地循环）。

### 5. ⚠ 第三个坑（v4 新增）：消息发出去没人回，先看 run 不要先看消息

**【GitHub 实测】** 本轮第一条预热消息发出去之后 400 秒没有任何回复。只看消息列表会得出「@ 路由没通」的错误结论；`runs list <convId>` 直接给出真相：

```
crun_01m3f66t0cdqhxqn6q5wy0hyxn  Lead-Waker  failed
  remote_employee_session_failed: qodercli version is incompatible with the
  bundled SDK (expected 1.1.48, received 1.1.64)
```

托管的 `qodercli-wake` 被热更新推到了 daemon 里 SDK 期望的版本之前，而 `qoderwake update --check` 会说「已是最新」（daemon 确实是最新的，错配在运行时那一侧）。**`qoderwake restart` 让两侧重新对齐**，重启后同一条消息的 run 从 `failed` 变成 `completed`。

> **课堂用法**：这条与「审批只存内存、5 分钟即焚，但 daemon 日志是持久的」是同一个教训的两面——**排障要看运行记录，不要只看产物**。消息列表是产物，run 状态与日志才是过程。

### 6. 两轨的本质差异（课堂重点，别讲反）

| | WakerFlow 轨 | Group 轨 |
| --- | --- | --- |
| 编排载体 | 流程脚本，状态机 | 群 + SOP 正文，靠 @ 路由 |
| 阶段顺序 | 代码写死，跳不过去 | SOP 约定，**靠角色自觉** |
| G1/G2 门禁 | **状态机硬阻塞**：确认点不答就不往下走，且永不超时 | **SOP 软约束 + 人工纪律**：没有任何机械装置阻止 Waker 越过门禁继续做 |
| 结构化产出 | 每阶段返回受 JSON Schema 约束的对象（缺字段直接判失败） | 自由文本消息，靠 SOP 里的「唯一事实源」条款约束 |
| 失败恢复 | 可从 `state.json` 与已提交基线续跑 | 靠群消息历史，续跑语义要自己维护 |
| 会话形态 | 本地 worker 会话 | **云会话**，由 MachineBridge 轮询远端会话驱动，`--cwd` 是 Waker 自己的沙箱**而不是仓库** |
| 适用 | 固定、重复、要可审计的流水线 | 探索性、要人随时插话、角色要协商的场景 |

**必须如实讲的一条**：Group 轨的门禁是软的。这不是缺陷清单里的一行，而是两种范式的本质差异——不要包装成「Group 更灵活」。灵活和没有强制力在这里是同一件事。

**`--cwd` 是沙箱不是仓库**，这条会咬人：所以仓库根必须在提示词与角色描述里**显式下发绝对路径**，产物路径也一律写绝对路径。**【GitHub 实测】** 本轮 5 份角色描述都写了这一条，`install.sh` 装机时把 `~/` 展开成绝对路径。

另一条硬约束：**两轨绝不能同时跑**。流程脚本里的 `repoRoot` 是**一份共享工作树，没有 per-run worktree**，两条运行同时 `git checkout` 会互相把树抽走。kickoff 前要先查有没有 `running` / `waiting_input` 的运行——**`waiting_input` 也算**，一个停在门禁上没人管的 run 同样是地雷。

### 7. toolGuard 现场：审批判据（教材）

**【内部环境实测】七次审批的逐条重建见附录 B6**（含每条的规则 id、严重度、命中片段、批/拒与判据）。**判据与领域和平台无关，本靶仓通用。**

七条一致的判据是：「**这个动作是让需求能实现，还是让门禁变绿 / 让边界失效 / 让交付失去单一入口？**」拒的时候要在 reason 里写清替代路径，否则 Waker 只会换个写法再撞一次。实测有效的 reason 写法：「用封装脚本拿结论、看日志，凭据由脚本内部持有；**读不到就是边界，不是障碍**」。

⚠️ 顺带暴露的真实问题（v4 全部仍然成立）：

- **审批请求只存内存不落库，5 分钟过期，超时即该步失败且无法补批**。但 **daemon 日志是持久的**——「当时没把规则 id 记下来」这个说法是错的，id 一直在日志里，只是没人去查。
- **触发审批的多半不是危险动作，而是写法或文件名**：七条里三条是写法（续行、markdown 标题、注释里的引号），一条是文件名（扩展名里带 `mv`），只有三条是真的危险动作。**持久的修法是改提示词/SOP，不是放宽守护规则。**
- **归因必须查证据，不能靠规则名字面联想**：有两条拦截先后猜了三次都错，而答案一直躺在日志里。这条对学员同样成立，值得当场演示一次日志检索。

### 8. Group 轨尚未验证的

- **P0→P7 全程没跑过**（本靶仓上只做过三轮无副作用验证）。
- 群里的**长文档交接**（SOP 要求长文档写进仓库 `.devflow/issue-<n>/` 并提交，群里只放结论与路径）没有实测，不知道 Waker 在群会话里能否顺利写仓库——群会话的 `--cwd` 是 Waker 自己的沙箱而不是仓库。
- **主动跟进**（Lead 超时提醒、两小时内不重复提醒）没有实测，需要定时任务配合。
- Group 轨的**成本口径**未测：5 个角色 × 8 个阶段，每次 @ 都是一个完整 agent 会话。【内部环境实测】冒烟阶段一条无副作用消息的往返约 40 秒～2 分钟；**【GitHub 实测】** 本轮三轮验证都在 300 秒的 `--wait` 窗口内返回（未逐轮计时，所以不给具体分钟数）；而首轮因为 run `failed`，空等了 400 秒才从 `runs list` 查出原因——**这也是「排障先看 run」这条纪律的代价样本**。

---

## 附录 A：靶仓文件地图（讲师答疑用）

包名 `com.lab.shortlink`。**【GitHub 实测】** 11 个类被 JaCoCo 分析，26 个测试分布在 7 个测试类里。

| 路径 | 里面有什么 | 课上用来讲什么 |
| --- | --- | --- |
| `api/ShortlinkController.java` | `POST /api/links`（含短码碰撞重试循环）、`GET /{code}`（302 跳转；第 69 行 `@RequestHeader(REFERER, required=false)`，第 75 行调 `visitLog.record`） | 缺陷现场；第 56-57 行重试循环里的未覆盖行与未覆盖分支；第 77-79 行预算告警 |
| `visit/VisitLogService.java` | 内存 `List` 存流水；`record(code, referer)`，**第 22 行 `referer.toLowerCase(Locale.ROOT)` = NPE 点** | 冲突机关的核心：需求侧要重写它，缺陷侧要在它里面加一行 |
| `resolve/CachingLinkResolver.java` | 无界 `ConcurrentHashMap`，无 TTL，`cachedEntries()`；**javadoc 里直接写明两个缺陷**（慢性泄漏、更正后的目标地址永远传不出去） | REQ-A 的改造对象；「已知缺陷写在注释里」与「缺陷藏在代码里」的区别 |
| `code/ShortCodeGenerator.java` | `SecureRandom`、62 字符 base62 字母表、`CODE_LENGTH = 8` | 不可协商的安全约束；红灯分支改的就是它 |
| `link/` | `ShortLink` record、`LinkStore` 接口、`InMemoryLinkStore` | 「V1 建了表但代码没用」这个故意留的缺口 |
| `config/ShortlinkProperties.java` | 只有 `publicBaseUrl` 与 `redirectBudgetMillis`，**故意没有缓存容量/TTL** | 留白：补上就等于替学员回答 Open Question |
| `resources/api/openapi.yaml` | 只有 `POST /api/links` 与 `GET /{code}`；文件头写明冻结规则；注明 `Referer` 可选、**缺失属正常流量** | G2 冻结契约的只读边界；统计接口是纯新增 |
| `resources/db/migration/V1__create_short_link.sql` | 建了 `short_link` 表但代码未使用；文件头写明「已合入即只读，schema 变更只能新增 V2」 | 迁移脚本的只读边界；门禁会在内存库上真跑一遍 |
| `Jenkinsfile` | `stage('Gate: mvn -B clean verify')` + `GATE SUMMARY` + `post` 里的状态回写 | 三层审查里的机器门禁那一层；回写失败只标 UNSTABLE 的设计 |
| `pom.xml` | JaCoCo LINE `coverage.line.minimum=0.60`、Checkstyle `failsOnError`、SpotBugs `Max`/`Low`、Flyway 内存库迁移 | 「阈值只能由人改」的现场；**属性名不能以 `flyway.` / `checkstyle.` 开头**（那两个插件会把同前缀的 Maven 属性当自己的配置解析） |
| `AGENTS.md` | AI 审查口径：8 条审查重点 + 3 条可忽略的检查 + 团队约定 | 三层审查里的 AI 那一层；「把正确性写进指令」的落点 |
| `lab/` | 5 份角色描述、SOP 正文与渲染器、守护清单、装机脚本、两个凭据隔离封装脚本 | 「资产入仓」这件事本身：平台存储丢了也能一条命令装回来 |
| 测试（26 个） | `ShortCodeGeneratorTest`(3)、`InMemoryLinkStoreTest`(4)、`CachingLinkResolverTest`(4)、`VisitLogServiceTest`(4)、`ShortlinkControllerTest`(7)、`OpenApiContractTest`(3)、`RedirectBudgetTest`(1) | **`VisitLogServiceTest` 故意没有 null-referer 用例，`ShortlinkControllerTest` 的每个跳转测试都带 Referer**——否则基线本身就是红的，而这个红应当属于 issue #3 |

**分支状态**【GitHub 实测】：`main` = `084f13c`（PR #6 合并后）；`lab/predictable-code` = `bd91bac`（红灯分支，相对 main 只差 `ShortCodeGenerator.java` 一个文件）。

**PR 轨迹**【GitHub 实测】：#1 代码基线、#4 状态回写桥、#5 流程产物目录约定、#6 数字员工资产入仓，全部经 PR 合入；#5 在补齐 CI 状态之前实测为 `BLOCKED` 且合并被拒。

---

## 附录 B：内部环境时期的实测数据（**不可挪用到本靶仓**）

> 下列全部数字来自上一代内部协作平台与内部靶仓上的四轮完整运行与七轮 Group 冒烟。
> **它们只用来佐证机制，不代表本靶仓的耗时、覆盖率、轮数或产物。**
> 课堂上引用时必须说清「这是上一个环境的数据」。按公开仓的脱敏口径，本附录不含工号、内部域名、内部单号与客户名。

### B1 四轮运行

| run | 结果 |
| --- | --- |
| #1 | BLOCKED at S3（催生 `reproTestPath` 改造：复现测试不再被清理，而是升格为回归测试交接下去） |
| #2 | 首次完整跑通，ESCALATED at S6（合并被评审规则拦下，如实上报） |
| #3 | 数据丢失重建后重跑，验证三处修复；**写出了虚假的 `DELIVERED`** |
| #4 | **首轮真冲突 + 首轮真自愈**，8 phase 全过 |

### B2 分阶段耗时（机器时间 / 等人时间）

| Phase | run #2 机器 | run #3 机器 | run #3 等人 | run #4 机器 | run #4 等人 |
| --- | --- | --- | --- | --- | --- |
| S1 需求拆解 | 2m08s | 1m56s | — | **65m55s** | （无法分离） |
| G1 需求基线门禁 | 3m16s | 7m59s | 4m16s | 1m10s | **33m23s** |
| S2 事件驱动编码 | 14m31s | 10m32s | — | 20m43s | — |
| S3 线上缺陷热修 | 12m58s | 8m09s | — | 4m05s | — |
| S4 Git 冲突仲裁 | 10m51s | 5m53s | — | 5m46s |
| S5 CI 门禁自愈回环 | 0m54s | 0m34s | — | **15m28s** | — |
| G2 CR 准出门禁 | 3m49s | 4m51s | 50m16s | 13m44s | 1m47s |
| S6 准出与记忆治理 | **28m33s** | **4m48s** | — | 4m23s | — |
| **合计** | **1h17m00s** | **44m42s** | **54m32s** | **2h11m14s** | **35m10s** |

run #3 墙钟 1h39m14s；run #4 墙钟 **2h46m24s**。S1 冷启动 13m55s（含 10 项人工澄清），续跑 2m08s、零重复提问。run #4 的 S1 连开 3 轮澄清挂起。

### B3 门禁与覆盖率

- 预置红灯分支：`AesGcmCipherTest.derivesA256BitKey:20  policy requires AES-256, i.e. a 32 byte key ==> expected: <32> but was: <16>`，28 tests / 1 fail
- feature 分支绿灯：44 tests / 0 fail，行 **90.57751%**（298/329）、分支 86.36364%（57/66），14.3s
- run #4 自愈：build RED（60 tests / 25 fail，全部是 Spring `ApplicationContext` 启动失败的级联，**只有第一条是真因**，其余是 `ApplicationContext failure threshold (1) exceeded` 的连带跳过）→ **1 轮自愈** → GREEN（**55 tests / 0 fail / 0 skip**，行 **97.11286%**（370/381）、分支 **93.05556%**（67/72），Checkstyle 0、SpotBugs 0）
- 自愈真因：**CI 复用 workspace 里残留上一分支的 stale compiled test classes**，修法是把构建命令改成 `clean verify`
- 两次「红灯」其实是**参数误用**不是门禁判红：把构建号当分支名传，催生了 `NO_SUCH_BRANCH` 入口校验
- main 基线 90.56604%

### B4 冲突与交付

- 冲突 2 个文件：业务服务类（一侧改架构、一侧改行为）、`state.json`；`bothFixesPreserved = true`
- 缺陷现场：`record(...)` 里 `required=false` 绑定使请求头缺失时 null 传入，无条件 `toLowerCase` 触发 NPE（**与本靶仓 issue #3 同一类型，行号不同**）
- MR：**实测是三张，不是两张**（复核时才发现早先文档漏数了 hotfix 那张）。三张**全停在 `opened`、checks 全是 `unsatisfied`**
  ⚠️ 顺带说明「本轮交付只应有一条 MR」这个说法也不准：那一轮实际产出 feature 与 hotfix 两条 MR，另外还推了一条**从未建 MR、也没触发任何守卫规则**的残留分支
- `state.json`：`status=S6_MERGE_BLOCKED`、`gateApprovalHistory` 8 条、**没有 `mergedToMain` 字段**；流程返回 `mergedToMain=false`、`finalStatus=ESCALATED`
- 交付产物 9 个文件：`01-requirement/change-breakdown.md`、`02-dev/impl-report.md`、`03-hotfix/hotfix-report.md`、`04-merge/conflict-resolution.md`、`06-delivery/{两条回写评论, cr-checklist.md, release-note.md}`、`state.json`

### B5 Dev-Waker 沉淀的 7 条 Memory（可直接当课堂阅读材料）

1. **同文件双侧修改的语义冲突仲裁**——保留新架构并把那行行为修复重新应用上去，而不是整文件取一边。
2. **工作区里其他工单遗留的未跟踪测试文件会让本工单门禁变红**——测试编译不区分文件属于哪条工作流。
3. **单人账号仓库的合并死锁要如实上报而不是绕过**——绕过会让评审治理形同虚设。
4. **覆盖率门禁最容易意外翻红，且必须钉死构建环境**——本地与 CI 必须显式指定同一 `JAVA_HOME` 与同一 mvn 可执行文件，否则自愈回环会追着只在一侧存在的幽灵失败修。
5. **交付状态机宁可停在阻塞态也不得虚标成功**。
6. **结论产物要从冻结基线重推，不要从上游摘要抄写**——反向约束（「禁止做 X」）抄错方向会把「未做」传播成「已做」。
7. **多行评论的终端回显不等于落库内容**——先读回核实再决定是否重发，凭回显重发只会制造重复评论。

> **第 4 条原文里写的是「相对阈值最容易意外翻红」。这个判断已更正**：相对阈值根本没有实现（见缺口 11）。这条 Memory 本身就是「**正确的经验里也可能嵌着一个错误的前提**」的样本——课堂上拿它当审计练习比拿一条明显错误的记忆更有效。

**5 个角色的 `WORK_STYLES.md`（模板自带，从未改过）九行对照表：**

| Waker | 风格名 | 模板里的原文描述（逐字） | 对应本课程哪一幕 |
| --- | --- | --- | --- |
| Lead | **不粉饰** | 「**绝不带着阻碍报绿**，遇到进度风险会直接说明原因、影响及应对选项」 | 模块 4：宁可停在 `S6_MERGE_BLOCKED` 也不虚标 `DELIVERED` |
| Lead | **重追溯** | 「**绝不凭空捏造**负责人、日期或审批状态，确保所有计划与任务都有据可查」 | G1/G2 批准记录必须持久化 |
| PM | **恪守边界** | 「不擅自修改代码或承诺交付日期，超出职责范围时优先进行产品交接而非盲目越权执行」 | PM 只勘察不改文件 |
| Dev | **保守稳健** | 「优先保持兼容性，**只改必须改的，不做无关改动**」 | 模块 2 的范围红线：**不许顺手给 `referer` 加空值保护** |
| Dev | **坦诚透明** | 「不确定就明说，被阻塞就记录证据，**不假装完成**」 | 同 Lead「不粉饰」 |
| QA | **实事求是** | 「遇到环境阻塞或漏测路径直接坦白，**绝不隐瞒风险或假装全量验证通过**。」 | G2 未覆盖点必须现场重新核对 |
| DevOps | **严守边界** | 「**绝不硬编码密钥或绕过安全扫描**，未经审批拒绝执行不可逆的生产变更」 | 禁止 `--no-verify`、禁止降阈值 |
| DevOps | **证据门控** | 「发布放行必须依赖健康检查和测试扫描等**客观证据**，不凭主观感觉通过」 | 只能引用封装脚本的结构化输出 |
| DevOps | **回滚思维** | 「任何变更都必须提前规划回滚方案，**部署成功绝不等同于服务健康**」 | 热修要可独立回滚；回写桥失败不改判门禁 |

> ⚠️ **顺带把「模板有没有和实验设定打架」这件事查干净了**【内部环境实测】：`WORK_STYLES.md` 的 25 条里**没有**矛盾句。唯一的矛盾句在 **QA-Waker `MEMORY.md`** 的自动生成 Profile 里（「does not run unit tests」，而本实验 QA 必须消费门禁的 `tests`/`jacocoLine`）。**5 个 Waker 各有一份 `MEMORY.md`，课前要逐份读过。**

### B6 toolGuard 七次审批的判据（**已按 daemon 日志逐条重建**）

> ⚠️ **这一节此前的版本是错的，别再用旧讲义**。旧版写「5 个审批请求、3 批 2 拒」，并把其中两条归因到具体规则。从 daemon 日志逐条复原后发现：实际是 **7 个请求、3 批 4 拒**（其中 1 条是超时失败），旧版漏掉的两条恰恰最有教学价值，而两条规则归因都不对。

| # | 角色 | guardian / 规则 | 严重度 | 判定 | 判据 |
| --- | --- | --- | --- | --- | --- |
| 1 | **PM** | `FilePathToolGuardian` / `FILE_GUARD_SENSITIVE_ACCESS`（findings=2） | **CRITICAL** | **拒**（人工，6 秒后） | 平台自己的数据库在 fileGuard 黑名单上。PM 的职责是只读勘察**靶仓**，没有任何理由去读平台存储——**这是全表里最该拒的一条，旧版却完全没记** |
| 2 | Dev | `RuleBasedToolGuardian` / `TOOL_CMD_DANGEROUS_RM` | HIGH | **拒 —— `denied_approval_timeout`**（`durationMs=300035`） | 清理自己的临时复现测试。**全表最重要的一行**：不是人拒的，是**没人来得及批**。这就是全文反复警告的 5 分钟地雷**唯一一次真的炸了** |
| 3 | Dev | `ShellEvasionGuardian` / `SHELL_EVASION_NEWLINE` | HIGH | **批**（2m09s 后） | `git add` 两侧冲突文件 + 由复现测试升格的回归测试 + 流程产物。命令本身预授权低风险，触发的是换行续行——**纯写法问题** |
| 4 | DevOps | `FilePathToolGuardian` / `FILE_GUARD_SENSITIVE_ACCESS` | **CRITICAL** | **拒**（人工，48 秒后） | CI 的 HOME 目录，下面放着 admin token。想绕过凭据隔离封装——**不是误报，是守卫正好抓住了它该抓的东西** |
| 5 | Dev | `ShellEvasionGuardian` / `SHELL_EVASION_QUOTED_NEWLINE` | HIGH | **拒**（人工，1m46s 后） | MR 正文里的 **markdown 标题行**，正好命中规则原文条件「引号内换行且下一行以 `#` 起始」 |
| 6 | Dev | `ShellEvasionGuardian` / **`SHELL_EVASION_COMMENT_QUOTE_DESYNC`** | HIGH | **批**（1m11s 后） | 解析覆盖率 HTML 报告的脚本，**`#` 注释里带了引号**。只读分析、路径都在构建产物目录下，而这正是 G2 要求「以真实覆盖率报告重新核对未覆盖点」的必要动作，拒了就把门禁质量打回「照抄 S2 旧清单」 |
| 7 | Dev | `RuleBasedToolGuardian` / **`TOOL_CMD_DANGEROUS_MV`** | HIGH | **批**（37 秒后） | **文件名误报**：命令是 `git check-ignore -v data/*.mv.db`，H2 数据库文件的**扩展名里就有 `mv`**。动作本身是准出前该做的卫生检查，人正确放行 |

**旧版错在哪，以及为什么这些更正本身就是教材**：

- **有一行根本不是守卫事件**。旧版把一条「我认为该拒」的判断，写成了「守卫拦下、人拒了」的事实。日志里那次操作出现 0 次拦截：那条分支**确实推到了 origin**，但**没有建 MR**、也**没有触发任何规则**。**这两件事在课堂上必须分开讲**：守卫拦不住的事，只能靠提示词纪律与流程设计兜。
- **两条归因错了**：一条先后猜了两次都不对，真凶是 `COMMENT_QUOTE_DESYNC`（一条就在规则目录里、定义与命中片段完全吻合的规则）；另一条旧版说「目录里找不到干净对应的规则」，实际是 `TOOL_CMD_DANGEROUS_MV`——而这比旧版的结论**好得多**：它是一个**真实的文件名误报**，人正确放行了。「守卫会因为文件名里有 `mv` 就拦你」比「有个我们解释不了的拦截」有用一百倍。
- **教训**：先后猜了三次，每次都错，而答案一直躺在日志里。**归因必须查证据，不能靠规则名字面联想。**

> **两个 guardian 不是一回事，别混讲**：#1/#4 的 `FILE_GUARD_SENSITIVE_ACCESS` 来自 **`FilePathToolGuardian`**，严重度 **CRITICAL**；#3/#5/#6 来自 **`ShellEvasionGuardian`**、#2/#7 来自 **`RuleBasedToolGuardian`**，都是 HIGH。枚举出来的那份规则目录是 **toolGuard 的**，fileGuard 的黑名单命中**不在里面**——课上要提前说，否则学员对着目录找不到那条规则会以为环境坏了。

### B7 Group 轨（内部环境时期）

- 冒烟总共**七轮**，分三段：**前四轮**用来判定「绑定 SOP ≠ 读到正文」（第 1 轮「未读到 SOP 正文」，它自己标注了「以上基于 SOP 标题描述的流程名推断，本轮未实际读取 SOP 正文」——**这份如实标注比答案本身更有价值**，可以直接当「事实三态标注」的正面样本；第 2 轮加了会话级副本后读到；第 3 轮标记实验判定两份都能读且已分歧；第 4 轮删掉会话级副本后仍完整读到 105 行正文）。**第 5、6 轮**用来判定「第一个该 @ 谁」的提问歧义。**第 7 轮**在 SOP 升版之后重发重绑，验证新版本正文真的物化可读：报出版本号、成员数、5 个角色映射，(a)(b) 分开答对，并逐字引用了固定路由原文；单行短回复**没有触发 toolGuard 审批**，说明「短结论走 `--text`」的写法纪律是有效的。
- **三段的结论都与靶仓和平台无关**，v4 的第 1、3 轮验证在 GitHub 口径下再次确认了第一段与第三段的结论。

---

## 附录 C：GitHub 治理配置的完整载荷与复核命令

> 这一节是 v4 新增的。理由见 0.2 ③：**配置类写入必须回读校验**，所以讲义里要给出「写什么」和「怎么核」两半，只给一半等于没给。

### C1 规则集的完整载荷（当前生效版本）

```json
{
  "name": "protect-main",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["refs/heads/main"], "exclude": [] } },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": true,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": true
      }
    },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": false,
        "required_status_checks": [ { "context": "jenkins/verify" } ]
      }
    }
  ],
  "bypass_actors": []
}
```

- `required_approving_review_count` 现为 **0**，是临时值（见缺口 3）。升到 1 之前必须先有第二个评审身份，否则**任何 PR 都合不进去**。
- `bypass_actors: []` 是整个配置的要点：**空数组意味着管理员也不得绕过**。给了 admin 就是建议，不给才是控制。
- `strict_required_status_checks_policy: false` 表示不要求分支先与 main 同步。改成 true 会更严，但每次 main 前进都要 rebase，课上会打断节奏。
- `required_status_checks` 是**独立规则类型**，不是 `pull_request` 的参数。写错位置时 `PUT` 返回 200 并静默丢弃、`POST` 返回 422 并说明原因。

### C2 复核命令（非破坏性，课上可当场跑）

| 要核什么 | 命令 | 期望 |
| --- | --- | --- |
| 规则集是否 active、有没有 bypass | `gh api repos/<owner>/<repo>/rulesets/<id>` | `enforcement=active`，`bypass_actors=[]`，`current_user_can_bypass=never` |
| 必需状态检查配置 | 同上，取 `.rules[]｜select(.type=="required_status_checks")` | `context=jenkins/verify` |
| 某个 SHA 上有哪些状态 | `lab/scripts/github-lab.sh commit-status <sha>` | 含 `jenkins/verify` 与其 state |
| 某条 PR 能不能合 | `lab/scripts/github-lab.sh pr-status <n>` | `mergeable` / `mergeStateStatus` / 每个 check 的 context 与 state |
| token 权限够不够 | 推一个 `.github/workflows/` 下的文件 | 缺 `workflow` scope 会被拒（**这条是实测出来的，不是推理**） |
| 有没有第二身份 | `gh api user/orgs`、`gh api repos/<owner>/<repo>/collaborators` | 只有一个账号就说明「1 名评审通过」会导致死锁 |

**破坏性复核（课上不要跑，只在课前准备时跑一次并把输出截图）**：直推 main 看 `GH013`；开一个没有任何状态的探针 PR 看 `BLOCKED` 与 `--admin` 的真实行为（见缺口 5）。

### C3 三层审查的接线顺序

1. Jenkins job 建好、能在 main 上跑出 `GATE SUMMARY`（**先有结论**）
2. 状态回写桥接通，GitHub 上能看到 `jenkins/verify`（**再把结论送过去**）
3. 把 `jenkins/verify` 加进规则集的必需状态检查（**最后才让它有否决权**）

**顺序反了会把自己锁在外面**：先加必需检查再接桥，所有 PR 都会永远等一个不会来的状态。这一条在课前准备时最容易踩，因为三步分别由三个人做的话，谁都不知道另外两步到哪了。
