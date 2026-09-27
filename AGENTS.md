# AGENTS.md

本文件由 Qoder CLI 自动加载为上下文，是本仓所有自动化角色（PR 审查、`@qoder` 协作、数字员工）共同的纪律来源。审查输出用**中文**。

## 这个仓是什么

DevOps 全流程演练靶仓，业务是短链接服务（Java 17 / Spring Boot 3.2.4 / Maven）。它同时是一个**教学环境**：仓里有若干已登记在 issue 里的已知缺陷与刻意留白，由对应的 issue 负责推进。

这一点直接决定审查口径：**发现的缺陷如果已经有对应的 open issue，标注 issue 号即可，不要要求在当前 PR 里顺手修掉。** 「顺手修一下」会破坏另一条工作线的证据链——那张工单的热修会变成空提交，它「修复前红、修复后绿」的对比也就没了。范围纪律优先于代码整洁。

## 构建与门禁

```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@21   # 必须显式指定，见下
/opt/homebrew/bin/mvn -B clean verify
```

`JAVA_HOME` 必须钉死。`mvn` 默认会挑机器上最新的 JDK，而 pom 锁 Java 17 —— 不显式指定就会本地与 CI 跑出两套结果，排查的人会去追一个只存在于一侧的幽灵失败。

`mvn -B clean verify` 一次跑完五道检查，任何一道不过就是红灯：测试（0 失败 0 错误）、JaCoCo 行覆盖率（`pom.xml` 的 `coverage.line.minimum`，**绝对阈值 ≥ 0.60**）、Checkstyle（0 违规）、SpotBugs（`effort=Max` / `threshold=Low`，0 bug）、schema 迁移（在用完即弃的内存库上真的跑一遍）。

覆盖率是绝对阈值，**不存在「不低于上一次」的相对阈值机制**——不要按相对阈值解释红灯，也不要建议去实现它。

## 审查重点（按优先级）

1. **有没有为了让门禁变绿而放宽门禁**：调低 `coverage.line.minimum`、禁用或排除 JaCoCo / Checkstyle / SpotBugs / Flyway、给 SpotBugs 加排除过滤器、加 `-DskipTests` / `-Dcheckstyle.skip` 之类参数、用 `--no-verify` 绕过提交钩子。这类改动一律拒。判断标准是一句话：**这个改动是让需求能实现，还是让门禁变绿。**
2. **冻结契约**：`src/main/resources/api/openapi.yaml` 里已发布的两个路径（`POST /api/links`、`GET /{code}`）的既有请求结构、响应结构、既有响应码不得改动。只允许纯新增：新增路径、新增可选请求字段、新增响应码。看起来必须改既有定义的，退回需求侧裁定。
3. **迁移脚本**：已合入的 `V1__*.sql` 只读，一个字段都不许改。schema 变更只能新增 `V2__*.sql`；回滚也是新增反向脚本——已经跑过 V1 的环境不会重新执行它，改历史脚本只会造成环境之间的 schema 分歧。
4. **短码策略**：8 位 base62、至少 47 bit 熵，`SecureRandom` 生成。短码出现在公开 URL 里，能被枚举就等于能遍历别人的链接。这条约束由 `ShortCodeGenerator` 的 javadoc、`ShortCodeGeneratorTest` 的策略断言、需求单的「约束」节三处共同固定，改任何一处都要同时改另外两处。
5. **跳转预算**：`shortlink.redirect-budget-millis`（默认 300ms）是对外承诺，由 `RedirectBudgetTest` 守着。任何加进跳转主链路的东西（同步写库、远程调用、锁）都要先回答「它会不会把这个承诺打破」。旁路写入要有独立的短超时，超时即放弃；旁路故障不得放大成主链路 5xx。
6. **测试断言的强度**：断言行为（响应码、记录是否真落库、字段值），不是只断言「没抛异常」。仲裁合并后如果调整了断言，要保留原测试意图，不得为了变绿而删断言。
7. **证据与状态**：交付状态必须由「合并是否真的核实成功」推导。合并未经核实成功就写「已交付」属于虚标，一律拒。门禁结论只能引用 CI 的结构化输出（`=== GATE SUMMARY ===` 段），不接受「构建失败」这类复述——要指到具体阶段、具体文件、具体断言消息原文。
8. **凭据**：不得出现硬编码的 token、密码、连接串。GitHub 侧一律走 `lab/scripts/github-lab.sh`，Jenkins 侧一律走 `jenkins-lab.sh`，两者的凭据都由脚本内部持有。

## 可以忽略的检查

- **未覆盖行不要一律要求补到 100%。** 要求的是分类并给出依据：哪些是真的没被验证过的业务逻辑（该补测试）、哪些是框架入口（补了毫无信息量）、哪些是刻意保留的已知未覆盖点（该记进交付文档）。一律「补满」不是答案。
- 靶仓里已登记在 issue 中的已知缺陷与刻意留白（例如配置类里刻意缺失的配置项），不要报成「新发现的问题」，也不要替 issue 回答它的 Open Question。
- `.devflow/` 下的流程产物是**交付物**不是临时文件，随分支提交，不要建议加进 `.gitignore`。

## 团队约定

- 分支：`feature/issue-<n>-<slug>`、`hotfix/issue-<n>-<slug>`，都从 `main` 切出。
- `main` 上有分支规则集：必须走 PR、必需状态检查 `jenkins/verify`、评审线程必须解决、禁止 force push 与分支删除、**管理员也不得绕过**。不要建议直推 `main`，也不要建议用管理员特权合并。
- 提交信息要能回溯到 issue 与 REQ 编号。
- 长文档（需求拆解、实现报告、分诊报告、仲裁记录、准出自查、交付说明）写进 `.devflow/issue-<n>/` 并提交，issue 与 PR 里只放结论、路径与下一步责任人。目录约定见 `.devflow/README.md`。
- 冲突仲裁严禁 `git checkout --ours/--theirs` 整文件取一边，严禁 `-X ours` / `-X theirs`：git 冲突标记只表达文本重叠，真正要保护的单元是「两侧各自想生效的修复」，整文件取一边会让另一侧的修复静默丢失，而门禁还可能照样绿。
