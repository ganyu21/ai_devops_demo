# P6 独立验收报告：issue #2（含 issue #3 回归及 G2 返修）

> 验收人：QA-Waker  
> 验收对象：`feature/issue-2-cache-ttl-and-visit-log` @ `7f6127051b74321f4178805801dcd5e787c0e4e7`  
> 需求基线：v1.2（`.devflow/issue-2/01-requirement/change-breakdown.md`）  
> 验收时间：2026-09-27  
> 结论：**PASS（P6）**；P5 已核实为 **CLEAN**，后续仅待 Lead-Waker 向 Requirement Owner 重提 G2 人工门禁，见第 8 节。

## 1. 范围、基准与方法

- 本报告**取代**旧版 P6 报告（旧版验收对象为 `28aca2c`、基线 v1.1，不能用于本轮 G2）。
- 目标 SHA 已由 Lead-Waker 指定为 `7f61270`；相对 `origin/main` 共 19 个提交。返修实现提交为 `8c42c51`，其后到 `7f61270` 的生产代码增量仅有 `VisitLogAwait.java` 的测试观测窗口调整；`a3ac4b5..7f61270` 仅改 gate/release/state 文档。
- 依据 v1.2 的严格 OQ7 口径验收：redirect 请求线程**不得**为统计写入同步等待（基线 `change-breakdown.md:54-55,81,114-117`）。
- 本轮采用运行时观察而非复跑 CI 测试：以 `JAVA_HOME=/opt/homebrew/opt/openjdk@21` 启动当前工作树的 Spring Boot 服务，端口 `18099`，使用全新的临时文件 H2 库；通过 HTTP API 驱动实际创建、跳转、统计与旁路失败路径。没有执行 Maven test/verify。
- 测试源码仅作为「作者在 CI 中覆盖的意图」审阅，不作为本报告的唯一行为结论；CI/gate 结论由 DevOps-Waker 单独复核。
- 本轮没有执行 Maven test/verify，改用运行时 HTTP 观察，CI 结论交给 DevOps。这个分工在三层审查设计下成立，但「P6 独立验收」的独立性因此落在行为轴上、不在构建轴上。

## 2. 运行时证据摘要

### 2.1 启动与迁移（已核实）

应用启动日志显示：Tomcat 监听 18099；对全新文件 H2 库成功校验并应用 V1、V2，两条迁移后 schema 版本为 v2。对应实现/配置为：

- `application.yml:7-14`：文件 H2 数据源、`spring.flyway.enabled=true`、迁移位置；
- `V2__create_visit_log.sql:5-12`：新增 `visit_log` 表及 `(code, visited_at DESC)` 索引。

### 2.2 HTTP 观察（已核实）

1. `POST /api/links` 创建目标 `https://example.com/qa-p6-target`，响应生成短码 `ZzVBFN0h`。
2. 不带 Referer 请求 `GET /ZzVBFN0h`：返回 **302**、`Location: https://example.com/qa-p6-target`，端到端耗时 **4.939ms**；随后 `GET /api/links/ZzVBFN0h/visits` 返回 `code`、`referer: null`、`visitedAt` 三字段。
3. 分别带 `HTTPS://Example.COM/Source-A`、`HTTPS://Example.COM/Source-B` 发起两次跳转，均为 302（2.046ms、2.294ms）；`GET /api/links/ZzVBFN0h/visits?limit=2` 返回小写归一化后的 `source-b` 在前、`source-a` 在后，符合 `visitedAt` 倒序。
4. 相邻参数探针 `?limit=0` 返回 200 和已有三条记录，符合实现将非正 limit 回退默认值的语义（该具体非正数语义未在基线另行规定）。
5. 错误旁路探针：发送 3020 字符 Referer，H2 因 `VARCHAR(2048)` 约束抛出 `DataIntegrityViolationException`；客户端仍在 **5.378ms** 收到 **302** 与正确 Location。服务日志显示失败由 `visit-log-writer-2` 后台线程记录为 ERROR，栈落在 `VisitLogService.record:57` / `recordAsync` lambda:70，未放大为主链路 5xx。

## 3. REQ-A 验收结论（缓存）

| 验收项 | 结论 | 当前 SHA 证据 |
| --- | --- | --- |
| REQ-A-1：容量 10000，配置注入 | PASS | `application.yml:19-22` 配置 `max-size: 10000`；`ShortlinkProperties.java:64-84` 绑定配置；`CachingLinkResolver.java:32-42` 从 properties 注入到缓存构造器。`CachingLinkResolverTest.repeatedResolvesHitTheStoreOnlyOnce` 位于 `:45-53`，作者 CI 用例覆盖命中。 |
| REQ-A-2：TTL 10 分钟、无仓库环境差异 | PASS | `application.yml:19-22` 为 `ttl-minutes: 10`；resolver 在 `CachingLinkResolver.java:33-36` 以配置值创建 Duration；`CachingLinkResolverTest.entriesExpireAfterTtl:99-108` 覆盖 TTL 失效。仓库无 `application-*.yml/properties` 环境覆盖文件。 |
| REQ-A-3：LRU | PASS | `CachingLinkResolver.java:75-89` 使用 access-order `LinkedHashMap` 和 `removeEldestEntry`；CI 用例 `cacheEvictsLeastRecentlyUsedEntriesWhenCapacityIsReached:85-96` 明确复访 A 后插入 D、断言 B 被淘汰。 |
| REQ-A-4：写路径主动失效 | PASS | `ShortlinkController.create:66-68` 在 `store.save` 后调用 `resolver.invalidate`；接口默认方法位于 `LinkResolver.java:12-19`；CI 用例 `invalidateRemovesCachedEntry:111-120` 断言下次 resolve 重查 store。无需 TTL-only 退路。 |
| REQ-A-5：既有 302/404 契约和 300ms 预算 | PASS | `openapi.yaml:15-65` 的既有 `POST /api/links`、`GET /{code}` 形状保持；`ShortlinkController.redirect:75-90` 继续返回 302/404。运行时无 Referer 请求实际获得 302/正确 Location/4.939ms。**补充说明**：Owner 要求的 VisitRecord 可空契约属于 REQ-B-4 新增 schema，已在下表核验。 |
| REQ-A-6：缓存覆盖场景 | PASS | 作者 CI 用例 `CachingLinkResolverTest:45-120` 覆盖命中、miss 缓存、容量 LRU、TTL、主动失效；本轮未复跑该测试套件，运行时 API 冒烟覆盖创建后立即跳转。 |

## 4. REQ-B 验收结论（访问流水与统计）

| 验收项 | 结论 | 当前 SHA 证据 |
| --- | --- | --- |
| REQ-B-1：V2 新表、V1 不改 | PASS | `V2__create_visit_log.sql:5-12` 新增 `visit_log` 与排序索引；`7f61270` 相对 main 的迁移 diff 仅新增 V2。运行时全新文件 H2 成功应用 V1、V2。 |
| REQ-B-2：Flyway 启用、文件 H2 自动迁移 | PASS | `application.yml:7-14` 启用 Flyway；本轮真实启动日志在新文件 H2 上验证两条迁移并达到 v2，不再沿用旧报告的「文件 H2 未取得证据」说法。 |
| REQ-B-3：#2 落库与 #3 空 Referer 热修都保留 | PASS | 当前 `VisitLogService.record:55-59` 落库，并将缺失 Referer 正规化为 null；这是 C2 的合并结果，不是 #2 实现侧顺手修复。仲裁记录 `04-merge/conflict-resolution.md:31-48` 确认 `bothFixesPreserved=true`；运行时无 Referer 302 且 `referer:null` 已复现。 |
| REQ-B-4：统计路径、limit、倒序、字段与可空契约 | PASS | `ShortlinkController.visits/effectiveLimit:92-104` 实现默认 50、最大 200；`VisitLogService.findRecentByCode:95-102` 用 `ORDER BY visited_at DESC LIMIT ?`；`openapi.yaml:66-92` 新增路径；`VisitRecord` 的 `referer` 同时 required（`:120-123`）且 `nullable: true`（`:127-133`）。运行时 `limit=2` 返回 source-b、source-a 倒序；无 Referer 返回字段存在且值为 null。契约作者用例为 `OpenApiContractTest.visitRecordKeepsRefererRequiredButNullable:82-100`。 |
| REQ-B-5：OQ7 严格异步旁路与 50ms 预算 | PASS | `ShortlinkController.redirect:75-90` 仅提交 `recordAsync`，没有 Future/get/wait；`VisitLogService.recordAsync:61-76` 用 `CompletableFuture.runAsync`、`orTimeout(50ms)`、`whenComplete`，返回 `void`，从 API 形状上消除请求线程等待句柄。运行时正常写入与错误旁路均在 5.4ms 内返回 302，低于 300ms。 |
| REQ-B-6：旁路失败（含 NPE）不放大为 5xx | PASS | `VisitLogService.logBypassFailure:78-90` 对 TimeoutException 和其他 failure 均只写 ERROR；`ShortlinkController.redirect:83-89` 无 NPE 特判/重抛。运行时真实 H2 写入失败仍返回 302 并在后台记录 ERROR。NPE 无法由该公共 API 的正常输入构造（缺 Referer 已是 null 合法路径）；作者 CI 用例 `VisitLogBypassFailureTest.failingVisitLogWriteMustNotTurnTheRedirectIntoA5xx:71-84` 用 JdbcTemplate 注入 NPE，断言 302、Location、ERROR，语义与运行时错误探针一致。 |
| REQ-B-7：无鉴权风险持续披露 | PASS | `release-note.md:30-35` 列出无鉴权 referer 敏感数据、固定线程池无界队列、单锁 O(n) 扫描未经压测、最终一致性窗口四项持续风险；未引入 security 配置。 |
| REQ-B-8：落库/查询/边界/#3/旁路覆盖 | PASS | 运行时已复现无 Referer、异步落库可见、倒序、limit、失败旁路；作者 CI 覆盖 `ShortlinkControllerTest:103-200`、`Issue3MissingRefererReproducerTest:47-62`、`VisitLogTimeoutTest:79-118`、`VisitLogBypassFailureTest:71-84`、`VisitLogServiceTest:33-92`。 |

## 5. VisitLogTimeoutTest 返修后意图复核

**结论：原质量意图保留，且与 v1.2 严格 OQ7 对齐；放弃的是旧同步实现的控制方式，而非断言强度。**

- 保留的意图：慢写不得影响 302 / Location，也不得挤占 300ms 跳转预算。`VisitLogTimeoutTest.slowWriteNeverBlocksTheRedirectNorBreaksTheBudget:80-107` 用被阻塞的 JdbcTemplate 写入，断言真实 redirect 302、Location、耗时小于 `redirectBudgetMillis`，且后台任务确实已提交。
- 保留的失败可观测性：同一用例 `:109` 等待 `visit log write exceeded` ERROR，而不是把慢写悄悄吞掉。
- 架构改变后的准确语义：`VisitLogTimeoutTest:111-114` 在释放阻塞后断言写入会完成；这明确验证「超预算 = 不再等待，不取消写入」，与 `release-note.md:23-28` 一致。旧版 `future.get(50ms)` / 调用方 Future 控制已被**有意删除**，因为它违反 OQ7 严格口径。
- 测试观测窗口：`VisitLogAwait.java:9-15,19-37` 的等待只在测试线程，现为 15 秒；它没有放宽记录数量/顺序断言，窗口耗尽仍失败。该调整是高负载 CI 的观测容忍，不会把生产 redirect 的同步等待重新带回。

## 6. 范围红线与质量观察

- `git diff origin/main...7f61270` 未包含 `.github/workflows/`；`pom.xml` 仅新增 JDBC 与 SpotBugs annotations 依赖，`coverage.line.minimum` 仍为 0.60（`pom.xml:20-35`）。
- 既有 OpenAPI 路径未改；V1 迁移未改；没有发现 skip/`--no-verify`、直推 main 或 force push 的代码证据。
- 运行时错误探针暴露一项**已按 REQ-B-6 设计处理的持续风险**：长度在 Tomcat 头上限内、但超过 `visit_log.referer VARCHAR(2048)` 的 Referer 会使统计记录丢失并写 ERROR，跳转仍成功。该行为符合「旁路失败不影响 302、不重试不补偿」，但运营统计对超长 Referer 非完整；后续若需要数据完整性，应另行定义截断/丢弃策略与可观测指标。
- `VisitLogServiceTest:19-24` 的历史 javadoc 仍写“没有 referer 为 null 用例”，而 #3 回归已由 `Issue3MissingRefererReproducerTest` 覆盖；仅为文档陈旧，不影响本次验收。

## 7. P6 结论与残余风险

**P6：PASS。** REQ-A 1-6、REQ-B 1-8 在 v1.2 / `7f61270` 基准下均有当前行号证据；返修重点（required + nullable referer、无同步等待、旁路失败 302、持续风险披露）已在运行时与当前源代码中复核。

残余风险及具名后续责任：

1. 固定两线程无界队列、缓存单锁 O(n) 扫描及未压测风险：已披露于 `release-note.md:32-35`，后续产品优化由 Requirement Owner 决定是否立项。
2. 异步最终一致窗口和超长 Referer 的旁路丢记录：属于当前基线允许的“不重试/不补偿”语义；后续容量/保留策略由 Requirement Owner 决定。
3. 本次 QA 启动的临时服务清理被本地权限守卫拒绝（`denied_approval_timeout`）；已按 SOP 不重试或绕过。它只使用临时 `/tmp` H2 文件库与端口 18099，不影响仓库代码或 PR。

## 8. 与 G2/P7 的边界及下一步

本报告不批准合并。已核实的当前 PR #17 @ `7f61270` 状态为：`mvn-verify=SUCCESS`、`qoder-review=SUCCESS`、`qoderai=APPROVED`、`mergeable=MERGEABLE`、`mergeStateStatus=CLEAN`、`blockingReasons=[]`、评审线程 `16/0 unresolved`。此前 `BLOCKED` / 空 `reviewDecision` 是评审线程处置前的历史读数，不再代表当前合并资格。

P6 验收与 P5 门禁均已满足重提 G2 的前置条件。**下一责任人：Lead-Waker**，向 Requirement Owner 提交绑定冻结 SHA `7f61270` 的 G2 人工门禁；未经该次明确批准，任何角色不得合并。
