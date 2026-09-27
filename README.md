# ai_devops_demo

DevOps 全流程演练靶仓。业务是一个**短链接服务**：把长网址变成短网址，访问短网址时 302 跳回原地址。

选这个题材是因为它不需要任何前置领域知识 —— 一句话就能讲完业务，参与者可以把注意力全部放在流程、门禁、仲裁与治理上，而不是花在理解对象存储或支付清算上。

## 技术栈

Java 17 / Spring Boot 3.2.4 / Maven，H2 存数据，Flyway 管 schema。

## 本地构建

```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@21
/opt/homebrew/bin/mvn -B clean verify
```

`JAVA_HOME` 必须显式指定。`mvn` 默认会挑到机器上最新的 JDK，而 `pom.xml` 锁的是 Java 17 —— 不钉死就会本地与 CI 跑出两套结果，排查问题的人会去追一个只存在于一侧的幽灵失败。

## 启动

```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@21
$JAVA_HOME/bin/java -jar target/shortlink-service-1.0.0.jar
# 监听 8081
curl -X POST http://localhost:8081/api/links \
  -H 'Content-Type: application/json' \
  -d '{"targetUrl":"https://example.com/a/very/long/path"}'
curl -i http://localhost:8081/<返回的 code>
```

## 门禁

`mvn -B clean verify` 一次跑完五道检查，任何一道不过就是红灯：

| 检查 | 配置在哪 | 阈值 |
| --- | --- | --- |
| 单元与集成测试 | `src/test/java` | 0 失败 0 错误 |
| 行覆盖率 | `pom.xml` 的 `coverage.line.minimum` | **绝对阈值 ≥ 60%** |
| Checkstyle | `config/checkstyle/checkstyle.xml` | 0 违规 |
| SpotBugs | `pom.xml`（`effort=Max` / `threshold=Low`） | 0 bug |
| schema 迁移 | `src/main/resources/db/migration` | 在内存库上真的跑一遍，跑不通即红 |

覆盖率是**绝对阈值**，不是「不低于上一次」的相对阈值 —— 相对阈值在机器层面没有实现，它只是对人的纪律要求（不许降阈值）。所以新增未测代码确实会稀释覆盖率，但门禁不会因为「比上次低」而翻红。

**阈值与规则只能由人改。** 为了让构建变绿而调低阈值、关掉插件、加 `-DskipTests` / `-Dcheckstyle.skip`、或者给 SpotBugs 加排除过滤器，都属于绕过门禁，不是修复问题。

## 三条只读边界

1. **对外契约**：`src/main/resources/api/openapi.yaml` 里已发布的两个路径（`POST /api/links`、`GET /{code}`）自需求基线冻结后只读。改动只允许纯新增 —— 新增路径、新增可选字段、新增响应码。`OpenApiContractTest` 会机械地检查既有定义还在、形状没变。
2. **已合入的迁移脚本**：`V1__*.sql` 一个字段都不许改。schema 变更只能新增 `V2__*.sql`；要回滚也是新增反向脚本，因为已经跑过 V1 的环境不会重新执行它。
3. **短码策略**：8 位 base62，至少 47 bit 熵。短码出现在公开 URL 里，能被枚举就等于能遍历别人的链接。这条约束由 `ShortCodeGenerator` 的 javadoc、`ShortCodeGeneratorTest` 的策略断言、需求单的「约束」节三处共同固定。

## 变更怎么进来

`main` 上有一条分支规则集（`protect-main`，`enforcement: active`）：

- 所有变更必须走 Pull Request，**不能直推**；
- `bypass_actors` 为空，所以**管理员也不得绕过**；
- 禁止 force push（`non_fast_forward`）与分支删除（`deletion`）；
- 评审线程必须全部解决之后才能合并（`required_review_thread_resolution: true`）；
- 新提交会 dismiss 已有的审查（`dismiss_stale_reviews_on_push: true`）；
- `required_approving_review_count` 当前是 **0**。这是**临时**状态：单人账号仓库里，PR 作者无法给自己投出有效审查，
  把它设为 1 会让每一轮都卡死在合并这一步、演示不下去。等第二个评审身份（bot 账号）备好就该调回 1，
  那时「结构性无法自审自批」这条治理事实才会重新变成活的教材。另有
  `require_extra_approval_for_unattributed_changes: true` 开着（含义与生效条件未实测，别当结论引用）；
- 必需状态检查：**`mvn-verify`**。

现状可以直接查，不要凭印象：`./lab/scripts/github-lab.sh ruleset` 列出规则集，
`gh api repos/<owner>/<repo>/rulesets/<id>` 看每一条规则的参数。

门禁跑在 GitHub Actions 上（`.github/workflows/gate.yml`，job `mvn-verify`）。check run 本身就是状态，
不需要「构建完再往 PR 上回写一次」这条桥。改这个 workflow 需要 Workflows 权限，而数字员工那张
fine-grained PAT 没有——所以「改门禁让构建必绿、再自己合并」这条路是被权限结构性堵死的，不是靠自觉。

一条实测结论值得单独记：`mergeStateStatus: BLOCKED` **不告诉你为什么**。首轮交付里，数字员工看到
BLOCKED 加上 `reviewDecision` 为空，就把原因写成「需要至少 1 名有权限的评审人」，还在 `state.json` 里
把「评审线程未解决」填成了 `false`——而那条 PR 上实际有 **7 条 qoderai 的评审线程，一条都没解决**，
且 `required_approving_review_count` 当时是 0，所以「至少 1 名评审人」那条规则根本没生效。
根因在工具：当时的 `pr-status` 不返回评审线程，调用方无从得知。

后来用 PR #19 做了一次对照把规则分开了：0 条线程 + 0 个批准时是 `UNSTABLE`（不阻塞），
AI 只留下 **1 条**评审线程、检查全绿时就变成了 `BLOCKED`。所以真正卡住的是
`required_review_thread_resolution`，一条未解决线程就够——这也意味着 AI 审查实际上握有对合并的否决权：
它每留一条意见，人就必须逐条裁定。

`github-lab.sh pr-status <n>` 现在会把每项规则的实况拉出来并自己推出 `blockingReasons`，
就是为了不给调用方留一个「凭印象填原因」的空档；读不到的规则（例如那个需要 Administration
权限才能看的 `required_approving_review_count`）单列进 `possibleAdditionalBlockers`，
不断言成阻塞原因。详见 `lab/README.md`。

## 目录

```
src/main/java/com/lab/shortlink/
  api/       对外接口：创建短链、302 跳转
  code/      短码生成（不可协商的安全约束在这里）
  link/      链接存储
  resolve/   解析与解析缓存
  visit/     访问流水
  config/    配置项
src/main/resources/
  api/openapi.yaml            冻结的对外契约
  db/migration/V1__*.sql      已合入即只读的迁移脚本
config/checkstyle/            静态检查基线
.github/workflows/            CI 门禁 + AI 代码审查（Qoder Action）
AGENTS.md                     审查口径与团队纪律，Qoder CLI 会自动加载
lab/                          数字员工团队的全部可版本化资产（角色、SOP、封装脚本、守护配置）
docs/                         学员版实验手册（讲师版含参考答案，不在本公开仓里）
.devflow/                     每轮的流程产物，是交付物不是临时文件
```
