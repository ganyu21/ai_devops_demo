# 操作手册 · v4 GitHub 靶仓版

> **这份是照着敲的**：课前准备、每轮重置、课上两轨操作、演示脚本、速查与排障，一步一条命令。
> **讲为什么、给实测数据、给教学主张与已知缺口在另一份**：《培训大纲与实验手册-v4-GitHub靶仓版.md》。两份互相引用，不重复内容。
>
> **命令的可信度标注**：本手册里的命令分两类。**〔已跑〕** 是本轮在真环境上执行过并核对过输出的；**〔未跑〕** 是写法确定但还没在本环境跑通的（缺凭据或缺权限），执行前先看大纲第五章对应的缺口条目。没标注的一律按〔已跑〕理解。

## 0. 名词与路径

| 记号 | 值 |
| --- | --- |
| `$REPO` | `ganyu21/ai_devops_demo`（GitHub，**PUBLIC**，Free 套餐） |
| `$ROOT` | `~/PycharmProjects/ai_devops_demo`（本地靶仓根） |
| `$QW` | `~/.qoderwake/qoderwake`（QoderWake CLI） |
| `$GL` | `$ROOT/lab/scripts/github-lab.sh`（GitHub 能力唯一入口） |
| `$JL` | `~/jenkins-lab/jenkins-lab.sh`（Jenkins 门禁唯一入口） |
| `$JOB` | `ai-devops-demo-verify` |
| `$CONV` | `conv_01m3f5pwhsfrehh2375v2y5cw7`（群「GitHub 靶仓交付团队」） |
| `$GROUP` | `csgrp_01m3f5pwhg5ye6dbswne4dzea9` |
| `$RULESET` | `24042720`（`protect-main`） |

```bash
export ROOT=~/PycharmProjects/ai_devops_demo
export QW=~/.qoderwake/qoderwake
export GL="$ROOT/lab/scripts/github-lab.sh"
export JL=~/jenkins-lab/jenkins-lab.sh
export JOB=ai-devops-demo-verify
export CONV=conv_01m3f5pwhsfrehh2375v2y5cw7
export GROUP=csgrp_01m3f5pwhg5ye6dbswne4dzea9
export REPO=ganyu21/ai_devops_demo
export RULESET=24042720
# 构建环境必须钉死：mvn 默认会挑机器上最新的 JDK，而 pom 锁 Java 17
export JAVA_HOME=/opt/homebrew/opt/openjdk@21
export MVN=/opt/homebrew/bin/mvn
```

---

## 1. 一次性准备

### 1.1 拉起本机环境

```bash
~/jenkins-lab/lab-up.sh status      # 只看状态，不启动任何东西
~/jenkins-lab/jenkins.sh start      # Jenkins @127.0.0.1:8080
~/jenkins-lab/jenkins.sh status
$QW status                          # daemon @127.0.0.1:19820
$QW restart                         # 有 qodercli 版本错配时用这条对齐（见 6.1）
```

**〔已跑〕** 本轮实测：Jenkins `RUNNING pid=… port=8080`、`login HTTP 200`；daemon 版本 1.1.3。

**开课前必查一次 run 状态**，有 `failed` 或 `running` 的残留就别开跑：

```bash
$QW runs list $CONV
```

### 1.2 GitHub 侧

**规则集**（当前已生效，四条规则；载荷原文见大纲附录 C1）：

```bash
gh api repos/$REPO/rulesets/$RULESET \
  --jq '{enforcement,bypass:.bypass_actors,canBypass:.current_user_can_bypass,
         rules:[.rules[].type]}'
```

**〔已跑〕** 期望：`enforcement=active`、`bypass=[]`、`canBypass="never"`、`rules=["deletion","non_fast_forward","pull_request","required_status_checks"]`。

改规则集用 `PUT`，**改完必须回读校验**——`PUT` 会静默丢弃它不认识的参数（返回 200，响应体里那个键根本不存在）：

```bash
gh api repos/$REPO/rulesets/$RULESET --method PUT --input /tmp/ruleset.json > /tmp/out.json
python3 -c "import json;d=json.load(open('/tmp/out.json'));print([r['type'] for r in d['rules']])"
```

**〔已跑〕本轮踩到的**：把 `required_status_checks` 当成 `pull_request` 的参数写，`PUT` 返回 200 但键不存在；改用 `POST` 新建才报错——`422 Invalid rule 'pull_request': Unexpected parameter required_status_checks`。**它是独立的规则类型。**

**标签与工单**：

```bash
gh label list --repo $REPO --limit 30
gh issue list --repo $REPO --state all --limit 10
gh issue view 2 --repo $REPO --json number,title,labels,body   # 需求单：10 OQ + 1 Conflict + 4 条非目标
gh issue view 3 --repo $REPO --json number,title,labels,body   # 线上问题单：症状级描述
```

**〔已跑〕** 本轮 #2 / #3 已建好并互相交叉引用，标签 `需求,待澄清` 与 `线上问题`。**每轮开课前要重建一对新的**（见 2.1）。

**数字员工的 PAT**〔未跑，缺凭据〕：

1. GitHub → Settings → Developer settings → **Fine-grained personal access tokens** → Generate new token
2. Resource owner `ganyu21`；Repository access **Only select repositories** → `$REPO`
3. Repository permissions 只给三条：**Contents: Read and write**、**Pull requests: Read and write**、**Issues: Read and write**
   **不要给 Administration**（给了就能改规则集，最小权限就废了）；**不要给 Workflows**（给了就能改 CI 定义与自己的审查关卡）
4. Expiration 给短一点（7 天或 30 天）
5. 装到仓库**外面**，绝不入仓：

```bash
mkdir -p ~/.config/ai-devops-lab && chmod 700 ~/.config/ai-devops-lab
umask 077 && cat > ~/.config/ai-devops-lab/github-waker-token   # 粘贴后 Ctrl-D
chmod 600 ~/.config/ai-devops-lab/github-waker-token
```

6. 逐个命令实测权限边界（**四条都要跑，最后一条应当失败**）：

```bash
$GL issue 2                                  # 读得到
$GL pr-status 6                              # 读得到
$GL commit-status $(git -C $ROOT rev-parse main)
$GL ruleset                                  # 读得到
gh api repos/$REPO/rulesets/$RULESET --method DELETE \
  -H "Authorization: Bearer $(cat ~/.config/ai-devops-lab/github-waker-token)"   # 应当 403
```

**〔已跑〕** 无 token 时的失败是结构化的，不会静默：`{"error":"NO_TOKEN","detail":"PAT 文件不存在，用 GITHUB_WAKER_TOKEN_FILE 指定或先装好凭据"}`，退出码 2。

**Projects 看板**〔未跑，缺 scope〕：

```bash
gh auth refresh -s project,read:project -s workflow    # 交互，要人手动完成
gh project create --owner ganyu21 --title "短链靶仓 · DevOps 全流程演练"
```

**〔已跑〕** 未补 scope 时的报错原文：`your authentication token is missing required scopes [project read:project]`。

### 1.3 CI：Jenkins job 与状态回写桥

job 配置用 `config.xml` 创建（Pipeline from SCM，https 克隆公开仓，**Jenkins 侧不存任何 git 凭据**）：

```bash
TOKEN=$(cat ~/jenkins-lab/admin-token.txt)
curl -gs -u "labadmin:$TOKEN" -X POST \
  "http://127.0.0.1:8080/createItem?name=$JOB" \
  -H "Content-Type: application/xml" --data-binary @/tmp/job.xml -w "http_code=%{http_code}\n"
```

**〔已跑〕** 返回 `http_code=200`。要点：`CpsScmFlowDefinition` + `scriptPath=Jenkinsfile` + `lightweight=true`，分支规格 `*/${BRANCH_NAME}`，字符串参数 `BRANCH_NAME` 默认 `main`。

触发构建与读结论：

```bash
curl -gs -u "labadmin:$TOKEN" -X POST \
  "http://127.0.0.1:8080/job/$JOB/buildWithParameters?BRANCH_NAME=<分支名>" -w "%{http_code}\n" -o /dev/null
curl -gs -u "labadmin:$TOKEN" "http://127.0.0.1:8080/job/$JOB/lastBuild/api/json?tree=number,building,result,duration"
curl -gs -u "labadmin:$TOKEN" "http://127.0.0.1:8080/job/$JOB/<n>/consoleText" | grep -A14 "=== GATE SUMMARY ==="
```

**〔已跑〕** 本轮三次构建：#1（20.7s）、#2（19.6s）、#3，全部 `SUCCESS`，`gateVerdict=GREEN`，`tests.total=26`，`jacoco.line=93.05556`。

**核对回写真的到了 GitHub**（这一步不能省——Jenkins 绿不等于 GitHub 收到了状态）：

```bash
$GL commit-status <sha>          # 或： gh api repos/$REPO/commits/<sha>/statuses
```

**〔已跑〕** 期望看到 `{"context":"jenkins/verify","state":"success",…}`。

也可以用封装脚本一次拿到单行 JSON 结论（**注意必须带两个环境变量**，否则它会去驱动旧 job）：

```bash
LAB_JOB=$JOB LAB_REPO=$ROOT $JL build <分支名>
LAB_JOB=$JOB LAB_REPO=$ROOT $JL console <build号>
LAB_JOB=$JOB LAB_REPO=$ROOT $JL status
```

**⚠️ `build` 的第一个参数是分支名不是构建号。** 传错时 Jenkins 会去 checkout 一个叫 `8` 的分支并报 `couldn't find remote ref`——**这条错误在自愈回环看来和真的代码失败长得一模一样**。脚本现在会先 `rev-parse` 验分支，不存在就返回结构化 `NO_SUCH_BRANCH` 并 `exit 6`。

### 1.4 Qoder Action（AI 审查层）〔未跑，缺 scope 与令牌〕

```bash
gh auth refresh -s workflow                        # 补 scope，交互
git push origin <分支>                             # 推 .github/workflows/ 下的文件
gh secret set QODERCN_PERSONAL_ACCESS_TOKEN --repo $REPO   # 存 Qoder CN 令牌
```

**〔已跑〕** 未补 scope 时的拒绝原文：`refusing to allow an OAuth App to create or update workflow '.github/workflows/qoder-assistant.yml' without 'workflow' scope`。**连仓主默认的 token 都推不上去**，这是 GitHub 的结构性控制。

人工前置（只能人做）：在 Qoder Integrations 关联账户 → 把 `qoderai` GitHub App 装到 `$REPO` → 生成 Qoder CN 个人访问令牌。

两条 workflow 已在 `ffa5939`（本地分支 `feat/qoder-action`）：`qoder-code-review.yml`（`pull_request` 的 opened/synchronize/reopened 上跑 `/review-pr`，`OUTPUT_LANGUAGE: Chinese`）、`qoder-assistant.yml`（评论里 `@qoder` 触发）。审查口径来自仓库根的 `AGENTS.md`，Qoder CLI 自动加载。

**接通后的第一件事是核对它有没有犯 `AGENTS.md` 明令禁止的两类错**：把已登记在 issue 里的已知缺陷要求「顺手修」、把刻意保留的未覆盖行一律要求补满。犯了就改 `AGENTS.md`，不是改结论。

### 1.5 QoderWake 侧：装机、SOP、建群

```bash
cd $ROOT
bash lab/install.sh --check     # 只核对：五份描述是否一致、fileGuard 是否已在册、SOP JSON 是否已构建
bash lab/install.sh             # 写描述 + 合并 fileGuard 黑名单 + 构建 SOP JSON
```

**〔已跑〕** 首次装机全部 `ok`，紧接着 `--check` 报「一致」/「已在册」——**幂等**。

发布与绑定（**这三步会改共享状态，`install.sh` 不做**）：

```bash
$QW sop validate lab/sop/github-lab-group-delivery.json     # 位置参数，不是 --file
$QW sop publish  --file lab/sop/github-lab-group-delivery.json
$QW group create --title "GitHub 靶仓交付团队" \
    --waker Lead-Waker --waker PM-Waker --waker Dev-Waker --waker QA-Waker --waker DevOps-Waker \
    --sop github-lab-group-delivery@1.0.1 \
    --param github-lab-group-delivery.delivery_lead=Lead-Waker \
    --param github-lab-group-delivery.product_manager=PM-Waker \
    --param github-lab-group-delivery.engineering_executor=Dev-Waker \
    --param github-lab-group-delivery.qa_reviewer=QA-Waker \
    --param github-lab-group-delivery.ci_gate_keeper=DevOps-Waker --json
```

**〔已跑〕** 当前身份：profile `ccp_01m3f5nszv9p8dnvpbrare6rnv`、release `ccr_01m3f81cace5yda7vd64758h2c`（1.0.1）、digest `801b75b1…`、revision 3。

绑定后核对参数是否真解析到角色（**不能只看绑定成功**）：

```bash
$QW group sop list --json $CONV | python3 -c "
import sys,json; s=json.load(sys.stdin)['systemSkills'][0]
print(s['version'], s['releaseId'], s['digest'][:16])
print({k:v.get('display_name') for k,v in s['parameterValues'].items()})"
$QW group show $GROUP
```

**〔已跑〕** 5 个参数全部解析到真实 Waker，无未解析占位符；成员 6 名（人 + 5 Waker）。

**⚠️ 改了 SOP 正文必须升版本号重发重绑**——release 不可变，同版本号重发会报 `SOP release version already exists with different immutable content`。**〔已跑〕** 本轮就因此从 1.0.0 升到 1.0.1（仓内正文因路径改写多了 9 个字符）。**留着两份就是留着两个事实源。**

### 1.6 预热与验证（**跳过这一步，五个角色会照着 SOP 标题即兴发挥**）

`group sop set` 只是把 SOP **pin** 到群上，正文要等 daemon 惰性物化。**必须先发预热消息触发物化，再发验证消息。**

```bash
$QW messages send $CONV --mention Lead-Waker --intent notify --wait --timeout 240 \
  --text "【预热消息，无副作用】…请回一句「已就绪」并说明读到的 SOP 名称与版本，不要执行任何交付动作…"
$QW runs list $CONV                       # 先确认 run 不是 failed（见 6.1）
$QW messages list $CONV --limit 100 --json
```

**〔已跑〕** 物化产物可以直接看到，这是「正文真的可读了」的物理证据：

```
~/.qoderwake/data/cloud-conversations/$CONV/workers/7125fd7975a6/
  .qoder-sop-runtime/<hash>/plugin/skills/github-lab-group-delivery/SKILL.md
```

**验证消息要问三件事**，本轮实测三轮全部通过：

1. **正文可见性**：要求**逐字引用一句 SOP 正文原文**。引不出来就是只读到了 pin 元数据。
2. **路由判断**：(a) 新 issue 进群，**人**第一个该 @ 谁？(b) 那个角色确认 Requirement Owner 之后，**它**第一个该 @ 谁？**必须分开问**——这是两个问题，合并问会得到不稳定答案。
3. **版本判据**：问一个**只存在于正文里、且新旧版本不一样**的细节（本轮用的是封装脚本的完整路径）。光问版本号不够，它可能从 pin 元数据里读到版本号而没读到正文。

**〔已跑〕** 三轮结果：① 逐字引用了正文（「被 toolGuard / fileGuard 拦下就是边界，不是障碍…」）；② 6 名成员报全、5 参数全解析、(a) 交付负责人 (b) 需求分析，分开答对；③ 报出 1.0.1 并抄出**新**路径。

**发消息的参数纪律**（都是为了不触发 toolGuard 审批）：`--text` 只放短结论；长内容写文件用 `--file`；**不要**把带 markdown 标题行（以 `#` 开头）的多行正文塞进 `--text`——命中的是「引号内换行**且下一行以 `#` 起始**」这条规则，会卡进 5 分钟人工审批，而审批只存内存、超时即失败且无法补批。

---

## 2. 每轮重置

### 2.1 换一对新工单

**冲突是一次性事件**：hotfix 一旦合进 feature，「两侧改同一个方法」这个条件就永久消失，再跑同一对工单，仲裁阶段只会如实报 `conflictedFiles: []`，本模块最核心的环节直接空转。分支名从工单号推导，所以**每轮必须换一对新 issue**。

```bash
gh issue create --repo $REPO --title "<需求标题>" --body-file /tmp/issue-req.md --label "需求,待澄清"
gh issue create --repo $REPO --title "<缺陷标题>" --body-file /tmp/issue-bug.md --label "线上问题"
gh issue edit <需求号> --repo $REPO --body-file /tmp/issue-req.md    # 补上对缺陷单的交叉引用
```

**〔已跑〕** 需求单必须包含五节：背景 / 这次要做的两件事 / **约束（不可协商）** / **明确的非目标** / 需要澄清的地方（10 条）/ 已知的一处矛盾（1 条）/ 验收。「明确的非目标」第 1 条就是**不修缺失 `Referer` 时的 500**，并把理由写进正文（否则缺陷单的热修会变成空提交，它的修复前后对比证据也就没了）。缺陷单只给症状，**不给堆栈、不给行号、不给严重级别**。

### 2.2 七项前置校验（任一不满足就别开跑）

```bash
cd $ROOT
git fetch origin
git branch --show-current                      # 必须是 main
git status --short                             # 必须干净（.devflow/ 流程产物除外）
git branch --list 'feature/issue-*' 'hotfix/issue-*'   # 必须为空，否则是续跑不是冷启动
git show origin/main:src/main/java/com/lab/shortlink/visit/VisitLogService.java \
  | grep -n "synchronizedList"                 # 必须还在：需求侧才有架构可重写
git show origin/main:src/main/java/com/lab/shortlink/visit/VisitLogService.java \
  | grep -n "referer.toLowerCase"              # 必须还在：S3 才能真复现 NPE
git ls-tree -r origin/main --name-only | grep -i "NoReferer\|MissingReferer"   # 必须为空
$QW runs list $CONV | awk 'NR>1{print $3}' | sort -u   # 不得有 running / waiting_input / failed
```

**〔已跑〕** 本轮 pre-flight：HEAD=main、工作区干净、无 `feature/issue-*` 与 `hotfix/issue-*` 残留。

**⚠️ HEAD 必须停在 main** 这条最容易漏也最致命：上一轮跑完 HEAD 会留在旧 feature 分支，而那个分支上 `VisitLogService` 已经是落库版本，S1 的只读勘察会据此写出「访问流水已落库」的错误基线，S2 便无架构可重写。

**⚠️ 一项永远告警的检查等于没有检查**：曾有一条「工作区干净」校验因为过滤规则写得比 git 的折叠输出更精确（git 把未跟踪目录折叠成一行 `?? .devflow/`），永远匹配不上、于是永远告警。人会学会忽略它，等它真报出散落测试文件时也没人看了。**加校验时要确认它能变绿。**

### 2.3 把门禁拨回绿

```bash
LAB_JOB=$JOB LAB_REPO=$ROOT $JL build main
$GL commit-status $(git rev-parse origin/main)
```

**〔已跑〕** 不拨绿，学员看到的第一个画面是红的。

---

## 3. 课上操作

### 3.1 Group 轨：推进一轮交付

```bash
# 以 Requirement Owner 身份发言并唤醒交付负责人
$QW messages send $CONV --mention Lead-Waker --intent request_action \
  --text "新需求 https://github.com/$REPO/issues/<n> ，配套的线上问题 https://github.com/$REPO/issues/<m> 。靶仓根 <绝对路径>。请按 SOP 推进。"

$QW messages list $CONV --limit 100 --json      # 读回复
$QW runs list $CONV                             # 读运行状态（排障先看这条）
$QW trace list --limit 10                       # 任务链路
```

**〔已跑〕读消息的解析口径**：`messages list --json` 返回**顶层数组**（不是 `{data:{messages:[]}}`），按 seq **升序**，正文字段是 `body.text`，发送者是 `senderParticipantId`（要拿 `group show` 里的 participant id 才翻得出名字）。`--limit` 超过服务端上限会**静默返回空且退出码仍是 0**（200 可用、500 不行），表现为「查不到消息」而不是报错。想取最新 seq 必须拉一批再取最大值，`--limit 1` 拿到的是最旧那条。

**〔已跑〕** `messages claim` 只能在活跃的 Conversation Run 内部调用，从外面调报 `this command can only run inside an active QoderWake Conversation Run`——**别拿它当读消息的入口**。

### 3.2 人工门禁的答复

裁定要给内容，不要给「按推荐的来」——无内容答复会让需求拆解阶段原地再问一遍（有实测把某阶段从 14 分钟拉到 66 分钟）。10 条 Open Question 与 1 条 Conflict 的参考裁定见大纲 4.4 模块 1 的表格。

**多行裁定走文件，不要塞进命令行**：

```bash
$QW messages send $CONV --mention Lead-Waker --intent request_action --file /tmp/answer-g1.md \
  --text "G1 裁定见附件，逐条对应 OQ-1..OQ-10 与 C1。"
```

### 3.3 审批值守（**整条流水线最主要的挂死风险**）

审批窗口 **5 分钟**，请求**只存内存不落库**，超时即该步失败且**无法补批**。必须指定专人盯。

```bash
~/jenkins-lab/lab-group.sh approvals     # 拿到能动手的 agentId 与 requestId，并列出命中的规则
~/jenkins-lab/lab-group.sh watch 10      # 轮询新消息 + 待审批
$QW permission approval --help           # CLI 侧的批/拒入口
```

**⚠️ 两个都要挂**：流程 watcher 能告诉你「有会话卡在审批上」，但**给不出批/拒所需的 `agentId` 与 `requestId`**（它不查 `/api/permissions/approvals/pending`）。告诉你「卡住了」却告诉不了你「该批哪一个」，等于没盯。

**判据（七条一致）**：「这个动作是让需求能实现，还是让门禁变绿 / 让边界失效 / 让交付失去单一入口？」拒的时候要在 reason 里写清替代路径，否则 Waker 只会换个写法再撞一次。实测有效的 reason 写法：「用封装脚本拿结论、看日志，凭据由脚本内部持有；**读不到就是边界，不是障碍**」。

**事后复盘审批要查 daemon 日志，不要说「当时没记下规则 id」**——审批请求 5 分钟即焚，但日志是持久的。七次审批的逐条重建见大纲附录 B6。

### 3.4 记忆治理三步

```bash
$QW memory show --waker-id <id> --view index      # 跑之前先看基线（确认是空的，截下来）
$QW memory show --waker-id <id> --view topics
$QW memory lifecycle inspect --waker-id <id>
$QW memory versions --waker-id <id>               # 跑完一轮看快照列表
$QW memory diff --waker-id <id> --from <最早> --to <最新>   # 按行号区间逐条列新增
$QW memory snapshot --waker-id <id>               # 手工打点
$QW memory update --waker-id <id> --path MEMORY.md --old-text "…" --reason "…"   # 默认 dry-run
$QW memory rollback --waker-id <id> --snapshot-id <sid> --apply
```

**⚠️ `memory import` 默认整份替换**，不是增量合并。先跑不带 `--apply` 的 dry-run 核对文件数。

**⚠️ `--reason` 不是客套**：治理记忆最容易犯的错是凭当下判断删掉一条**延迟暴露**的经验，写下 reason 至少让下一次的人看得到当初为什么删。

**⚠️ 课前要读 5 份 `MEMORY.md`**（`~/.qoderwake/data/workers/<agentId>/.qoder/MEMORY.md`）：模板自动生成的 Waker Profile 会作为记忆索引注入，里面可能藏着与实验设定矛盾的句子（QA 模板那句「does not run unit tests」就是），而它**不在** `BIBLE.md`、也**不在**已被整份覆盖的 description 里。

### 3.5 两轨绝不能同时跑

流程脚本里的 `repoRoot` 是**一份共享工作树，没有 per-run worktree**，两条运行同时 `git checkout` 会互相把树抽走。kickoff 前先查：

```bash
$QW runs list $CONV | awk 'NR>1{print $3}' | sort -u
```

**`waiting_input` 也算**——一个停在门禁上没人管的 run 同样是地雷。

---

## 4. 演示脚本

### 4.1 非破坏性（课上可当场跑）

```bash
# 治理控制现状：管理员也不得绕过
gh api repos/$REPO/rulesets/$RULESET --jq '.current_user_can_bypass'      # → "never"

# 某条 PR 的合并资格与每个必需检查
$GL pr-status <n>

# 某个 SHA 上真的回写了哪些状态
$GL commit-status <sha>

# 门禁绿路径与结构化结论
LAB_JOB=$JOB LAB_REPO=$ROOT $JL build main

# 红灯分支：看起来像改进的退化
LAB_JOB=$JOB LAB_REPO=$ROOT $JL build lab/predictable-code
LAB_JOB=$JOB LAB_REPO=$ROOT $JL console <build号>

# 缺陷复现（先 java -jar 起服务）
curl -s -X POST http://localhost:8081/api/links -H 'Content-Type: application/json' \
  -d '{"targetUrl":"https://example.com/a/very/long/path"}'
curl -s -o /dev/null -D - -H "Referer: https://example.com/landing" http://localhost:8081/<code>   # 302
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8081/<code>                              # 500
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8081/unknown1                            # 404

# 未覆盖点分类（G2 的现场核对素材）
python3 - <<'PY'
import xml.etree.ElementTree as ET
r = ET.parse('target/site/jacoco/jacoco.xml').getroot()
for pkg in r.findall('./package'):
    for sf in pkg.findall('sourcefile'):
        rows = [(int(l.get('nr')), int(l.get('mi')), int(l.get('mb'))) for l in sf.findall('line')]
        miss = [x[0] for x in rows if x[1] > 0]
        part = [x[0] for x in rows if x[1] == 0 and x[2] > 0]
        if miss or part:
            print(f"{sf.get('name')}: 未覆盖行 {miss} 部分覆盖分支行 {part}")
PY

# 封装脚本的错误路径（证明它失败得清楚，不会给出看起来像成功的空结果）
GITHUB_WAKER_TOKEN_FILE=/nonexistent $GL issue 2      # → {"error":"NO_TOKEN",…} exit 2
```

**〔已跑〕** 上面每一条本轮都跑过，输出与大纲里的实测数字一致。

### 4.2 破坏性（**只在课前准备时跑一次，把输出截图，课上不要重演**）

```bash
# 直推 main → GH013。再验一次就等于真的往 main 推一次。
git push origin main

# 探针 PR：没有任何 CI 状态时应当 BLOCKED，合并被拒
gh pr merge <n> --merge

# 管理员特权能否绕过必需状态检查 —— 这条至今没有隔离出结论（大纲缺口 5）
gh pr merge <n> --admin --merge
```

**〔已跑〕** 前两条的输出：

```
remote: error: GH013: Repository rule violations found for refs/heads/main.
remote: - Changes must be made through a pull request.
 ! [remote rejected] main -> main (push declined due to repository rule violations)

X Pull request #5 is not mergeable: the base branch policy prohibits the merge.
```

**第三条不要凭印象讲**：本轮那次 `--admin` 试合并发生在 CI 状态已经 success **之后**，所以「合并成功」既可能是因为管理员特权，也可能是因为要求已满足。要验就得开一个**没有任何状态**的探针 PR，立刻试 `--admin`，然后关掉它。

---

## 5. 速查

### 5.1 GitHub

| 要做什么 | 命令 |
| --- | --- |
| 读 issue | `$GL issue <n>` |
| 回写 issue 评论（正文走文件） | `$GL issue-comment <n> <file>` |
| 开 PR（标题与正文都走文件） | `$GL pr-create <branch> <title-file> <body-file>` |
| PR 能不能合 | `$GL pr-status <n>` |
| 某 SHA 的状态 | `$GL commit-status <sha>` |
| 规则集现状 | `$GL ruleset` |
| **推分支（必须走这里）** | `$GL push <branch>` |
| 取远端引用 | `$GL fetch` |

**`git push` 为什么必须走封装脚本**：机器上自己的 credential helper 里存着有 **admin 权限的仓主 token**，Waker 直接 push 会静默提权、绕过最小权限设计。`$GL push` 把 `credential.helper` 置空，改用 `GIT_ASKPASS` 垫片走那张受限 PAT。token 不进 argv、不进 shell 历史、不写进 `.git/config`。

### 5.2 Jenkins

| 要做什么 | 命令 |
| --- | --- |
| 触发并等结论 | `LAB_JOB=$JOB LAB_REPO=$ROOT $JL build <分支名>` |
| 看最近一次结论 | `LAB_JOB=$JOB LAB_REPO=$ROOT $JL last [<分支名>]` |
| 看日志 | `LAB_JOB=$JOB LAB_REPO=$ROOT $JL console <build号> [grep]` |
| 起停 | `~/jenkins-lab/jenkins.sh {start\|stop\|status}` |

### 5.3 QoderWake

| 要做什么 | 命令 |
| --- | --- |
| daemon 状态 / 重启 | `$QW status` / `$QW restart` |
| **run 状态（排障第一条）** | `$QW runs list <convId>` |
| 发消息 / 读消息 | `$QW messages send <convId> --mention <名> --text … [--file …] [--wait --timeout N]` / `$QW messages list <convId> --limit 100 --json` |
| 群与成员 | `$QW group list` / `$QW group show <group>` |
| SOP 绑定与参数解析 | `$QW group sop list --json <convId>` |
| 发布 SOP | `$QW sop validate <file>` / `$QW sop publish --file <file>` / `$QW sop list` |
| 角色描述 | `$QW waker list --json` / `$QW waker update description --waker-id <id> --file <f>` |
| 守护配置 | `$QW permission get --waker-id <id> --format json` / `$QW permission patch file-guard --waker-id <id> --json-file <f>` |
| 规则目录 | `$QW permission builtin tool-guard-rules` |
| 记忆 | `$QW memory {show\|versions\|diff\|snapshot\|update\|remove\|rollback\|export\|import}` |
| 任务链路 | `$QW trace list [--status <s>] [--limit N]` / `$QW trace show --trace-id <tid>` |
| 快照 | `~/jenkins-lab/qw-backup.sh <标签>` |

---

## 6. 排障

### 6.1 消息发出去了没人回

**先看 run，不要先看消息列表**（消息列表是产物，run 状态才是过程）：

```bash
$QW runs list $CONV
```

**〔已跑〕本轮的真实案例**：

```
crun_01m3f66t0cdqhxqn6q5wy0hyxn  Lead-Waker  failed
  remote_employee_session_failed: qodercli version is incompatible with the
  bundled SDK (expected 1.1.48, received 1.1.64)
```

托管的 `qodercli-wake` 被热更新推到了 daemon 里 SDK 期望的版本之前。`$QW update --check` 会说「已是最新」（daemon 确实最新，错配在运行时那一侧），所以别去升级 daemon：

```bash
$QW restart        # 两侧重新对齐；重启后同一条消息的 run 从 failed 变 completed
```

**只看消息列表会误判成「@ 路由没通」**，然后去改 SOP 的路由段落——那是改错了地方。

### 6.2 角色照着 SOP 标题即兴发挥

绑定 SOP ≠ 读到正文。物化是惰性的，第一条消息触发的会话可能赶在物化完成之前挂载。修法见 1.6：预热 → 验证（要求逐字引用正文）→ 才上真需求。

**不要加会话级 skill 副本来「修」它**：pin 自己就会物化，副本是冗余的，而且构成**第二个事实源**——以后 republish 只更新 pin 副本，两者长期分歧，而 Waker 两份都读。

### 6.3 PR 合不进去

按顺序核三件事，**不要一上来看代码**：

```bash
$GL pr-status <n>                              # mergeStateStatus 是 BLOCKED 还是 CLEAN
$GL commit-status <head-sha>                   # jenkins/verify 在不在、state 是什么
gh api repos/$REPO/rulesets/$RULESET --jq '.rules[]|select(.type=="pull_request")|.parameters.required_approving_review_count'
```

| 现象 | 原因 | 解法 |
| --- | --- | --- |
| `BLOCKED`，checks 为空 | head SHA 上没有 `jenkins/verify` | 跑一次 CI。**注意状态绑 SHA 不绑 PR**：批准后再推一个提交，状态就作废了 |
| `BLOCKED`，checks 有但 state 不是 SUCCESS | 门禁真红了 | 读 `console <build号>` 定位，别降阈值 |
| `BLOCKED`，缺评审 | `required_approving_review_count ≥ 1` 而只有一个账号（作者不能批准自己的 PR） | 补第二身份，或临时降到 0。**别用 `--admin` 试**——先把这条隔离清楚（大纲缺口 5） |
| 直推被 `GH013` 拒 | 规则集生效中，这是**期望行为** | 走 PR。不要建议关规则集 |

### 6.4 构建与门禁

| 现象 | 原因 | 解法 |
| --- | --- | --- |
| 本地绿、CI 红（或反之） | `JAVA_HOME` 没钉死，本地与 CI 用了不同 JDK | 两边都显式 `export JAVA_HOME=/opt/homebrew/opt/openjdk@21`。钉死之后覆盖率应当**逐位一致**（本轮实测 93.05556%） |
| `Unknown configuration property: flyway.plugin.version` | `flyway-maven-plugin` 会把 `flyway.` 前缀的 Maven 属性当成自己的配置项解析，`checkstyle-maven-plugin` 同理 | 插件版本属性不要以 `flyway.` / `checkstyle.` 开头（本仓用 `flyway-plugin.version` 这种写法，pom 里有注释） |
| SpotBugs 报 `EI_EXPOSE_REP2` | 把可变对象（如配置 bean）直接存进字段 | **改代码**（在构造器里取出需要的值），**不要加排除过滤器**——加过滤器能让构建变绿，但那正是门禁纪律禁止的事 |
| `couldn't find remote ref 8` | 把构建号当分支名传给了 `build` | 传分支名。脚本现在会先验分支并返回 `NO_SUCH_BRANCH` |
| 门禁红了但 GitHub 上没有状态 | 回写桥断了（构建会标 UNSTABLE 而不是 FAILURE） | 这是**基础设施问题不是代码问题**，但**没回写成功就等于 PR 合不进去**，要如实报成阻塞 |
| `HOOK_FAILED` | 本机全局提交钩子扫到疑似凭据 | 原样上报并升级给人。**严禁 `--no-verify`** |

### 6.5 CLI 形状与 shell 的坑

| 现象 | 真相 |
| --- | --- |
| `permission get --json` 打出来是表格 | 要用 `--format json` 才真给 JSON |
| 解析 `messages list` / `waker list` 报 `'list' object has no attribute 'get'` | 它们返回**顶层数组**，不是 `{data:{…}}` |
| `messages list --limit 500` 什么都不返回、退出码还是 0 | 超过服务端上限会**静默返回空**。200 可用、500 不行 |
| `messages claim` 报只能在 Conversation Run 内部调用 | 它不是读消息的入口，用 `messages list` |
| `sop validate --file x.json` 报参数错 | 文件是**位置参数** |
| `sop init --version 1.0.0` 什么也没建、只打印了 CLI 版本号 | 被全局 `--version` 标志吃掉，必须写 `--version=1.0.0` |
| 多词命令存进变量再执行报 127 | zsh 不做词分割。用数组或直接写全命令 |
| `cmd \| tail` 把失败报成 exit 0 | 管道会掩码前一段的退出码（`$PIPESTATUS` 在 zsh 里叫 `$pipestatus`）。要判成败就别接管道，或输出重定向到文件后再看 |
| 脚本在 `set -u` 下报 `unbound variable`，而本地手工跑没事 | bash 3.2 在 UTF-8 locale 下会把紧跟 `$VAR` 的多字节字符折进变量名。一律写 `${VAR}`，**特别注意错误分支**（成功路径跑通不代表 `die` 那些行没问题，它们平时根本不执行） |
| 读 token 文件偶发 `EPERM`（不是 `EACCES`），随后 401 看着像登录态坏了 | 安全软件按访问云查会偶发挡住这次读，Bearer 头是空的。加重试并报真实原因，别让人去查登录态 |

---

## 7. 收尾与快照

```bash
cd $ROOT && bash lab/install.sh --check      # 装机内容与仓内资产是否一致
$QW memory show --waker-id <Dev> --view index # 这一轮长出了什么
~/jenkins-lab/qw-backup.sh after-class        # 本机快照
git -C $ROOT status --short                   # 流程产物是否都提交了
gh pr list --repo $REPO --state all --limit 10
```

**资产入仓 + 快照，两层各管一件事**：入仓（`lab/`）管「换机器能装回来」，快照管「本机灾难恢复」。

**要备份的核心其实只有一个文件**：`~/.qoderwake/data/store/qoderwake.sqlite`。平台存储被误删时，一次性消失的是 Waker 配置、流程定义、运行事件历史与沉淀的 Memory；**完全不受影响的是 git 仓、Jenkins（job 配置与构建历史）、GitHub（issue / PR / 规则集 / commit status）、登录态与 machine binding**。

**这就是那条课堂结论**：交付产物落在 git / CI / 工单系统里就是安全的，落在 Agent 平台自己的存储里就要单独备份。

跑完一轮记得回填大纲里所有标【待实测】的位置，并把标签改成【GitHub 实测】——**回填时连措辞一起改**，留着「尚未验证」的字样会让下一个讲师以为这条还没跑过。
