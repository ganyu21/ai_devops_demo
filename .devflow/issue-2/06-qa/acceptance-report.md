# P6 独立验收报告：issue #2（含 issue #3 热修回归核验）

> 验收人：QA-Waker
> 验收对象：`feature/issue-2-cache-ttl-and-visit-log` @ `28aca2cd6d7c57fd2968b2587d0ada8659d4a49b`
> 需求基线：v1.1（`.devflow/issue-2/01-requirement/change-breakdown.md`，G1 已批准）
> 技术设计输入：`.devflow/issue-2/02-dev/impl-report.md`、`.devflow/issue-2/04-merge/conflict-resolution.md`
> 验收时间：2026-09-27
>
> **总结论：PASS**（14/14 条验收标准通过；1 项子证据受本地权限守卫限制，列入残余风险，不构成返修项）

## 1. 验收方法

从 v1.1 冻结基线逐条推导检查项，不接受 P2 自报结论，证据来源限定为：

1. feature 分支当前代码逐文件核对（`git diff origin/main..HEAD` 全量变更面）；
2. git 三方证据链复原合并前后行为（`46ab733` 需求侧、`46b344f` 热修侧、`671cca8` 合并提交、`28aca2c` HEAD）；
3. QA 独立执行 `mvn -B clean verify`（`JAVA_HOME=/opt/homebrew/opt/openjdk@21`，与 CI 一致）；
4. DevOps-Waker P5 门禁结构化输出（build 15，交叉核对一致性，不作为验收唯一依据）。

## 2. REQ-A 逐条结论（解析缓存容量上限与 TTL）

| # | 验收标准 | 结论 | 证据 |
| --- | --- | --- | --- |
| REQ-A-1 | 条数上限 10000，配置注入，不硬编码 | PASS | `ShortlinkProperties.Cache.maxSize`（`ShortlinkProperties.java:64-85`）+ `application.yml:21` `shortlink.resolve.cache.max-size=10000`；`CachingLinkResolver` 经构造器注入（`CachingLinkResolver.java:33-42`），代码内无 10000 字面量 |
| REQ-A-2 | TTL 10 分钟，不允许按环境覆盖 | PASS | `application.yml:22` `ttl-minutes: 10`；全仓无 `application-*.yml` profile 覆盖（已核实：0 个 profile 文件）；测试资源 `src/test/resources/application.yml` 未设 cache 项 |
| REQ-A-3 | 淘汰策略 LRU | PASS | `LinkedHashMap(16, 0.75f, accessOrder=true)`（`CachingLinkResolver.java:82`）+ `removeEldestEntry`；测试 `cacheEvictsLeastRecentlyUsedEntriesWhenCapacityIsReached` 证明是 LRU 而非 FIFO（A,B,C→复访 A→插入 D 后被淘汰的是 B） |
| REQ-A-4 | 写路径主动失效；不可行则退路 TTL-only 并写明延迟 | PASS | `LinkResolver.invalidate()` 默认方法（`LinkResolver.java:17-19`）+ `ShortlinkController.create()` 在 `store.save()` 后调用（`ShortlinkController.java:73`）；`store.save` 全仓唯一调用点即此处；测试 `invalidateRemovesCachedEntry`。主动失效已实现，无需退路，无 10 分钟延迟需披露 |
| REQ-A-5 | `GET /{code}` 契约与 300ms 预算不变 | PASS | `openapi.yaml` 对 main diff 为纯新增（既有两路径零删改）；`OpenApiContractTest` 3 用例全绿；`RedirectBudgetTest` 全绿；404/302 行为由 `ShortlinkControllerTest.redirectReturns302/404` 固定 |
| REQ-A-6 | 测试覆盖命中/未命中/容量淘汰/TTL/主动失效 | PASS | `CachingLinkResolverTest` 7 用例逐项对应：`repeatedResolvesHitTheStoreOnlyOnce`（命中）、`aMissIsCachedToo`（未命中，与基线 `computeIfAbsent` 行为一致）、`cacheEvictsLeastRecentlyUsed…`（淘汰）、`entriesExpireAfterTtl`（TTL）、`invalidateRemovesCachedEntry`（主动失效） |

## 3. REQ-B 逐条结论（访问流水落库与统计接口）

| # | 验收标准 | 结论 | 证据 |
| --- | --- | --- | --- |
| REQ-B-1 | 新建 `visit_log` 表走 `V2__create_visit_log.sql`，`V1` 不动 | PASS | `git diff origin/main..HEAD -- src/main/resources/db/migration/` 仅新增 V2 一个文件，V1 零改动；V2 含 `(code, visited_at DESC)` 索引 |
| REQ-B-2 | `spring.flyway.enabled=true`，文件库自动执行 V1+V2；schema gate 内存库跑通 | PASS（含 1 项受限子证据，见 §7） | `application.yml:12-14` `flyway.enabled: true`；QA 独立 `mvn verify` 日志：`flyway-schema-gate` 在 `jdbc:h2:mem:shortlink_schema_gate` 上 `Successfully applied 2 migrations ... now at version v2`（V1 create short link + V2 create visit log）；文件库子项见 §7 |
| REQ-B-3 | `record()` referer 处理与基线逐字一致，不得顺手加空值保护 | PASS | git 证据：需求侧实现提交 `46ab733` 的 `record()` 为 `referer.toLowerCase(Locale.ROOT)` 无空值保护，与 main 基线逐字一致；合并后的空值保护来自 hotfix `46b344f`（C2 裁定要求两侧修复都保留），非 #2 侧擅自添加 |
| REQ-B-4 | `GET /api/links/{code}/visits`，limit 选填默认 50 硬上限 200，不分页，字段 code/referer/visitedAt，visitedAt 倒序 | PASS | `ShortlinkController.java:97-109`（`effectiveLimit`：null/≤0→50，min(limit,200)）；`VisitLogService.findRecentByCode` SQL `ORDER BY visited_at DESC LIMIT ?`（`VisitLogService.java:59-67`）；返回体 `VisitRecord(code, referer, visitedAt)` 字段固定；测试：`visitsEndpointReturnsRecentVisitsInReverseChronologicalOrder`（倒序+字段）、`visitsEndpointRespectsTheLimitParameter`（limit=2）、`visitsEndpointCapsLimitAtTheHardMaximum`（limit=999→封顶）；openapi.yaml 新路径 default 50 / maximum 200 |
| REQ-B-5 | 写入独立 50ms 超时，超时记 ERROR 后继续 302，不重试不补偿 | PASS | `ShortlinkController.java:37,111-127`（`VISIT_LOG_TIMEOUT_MILLIS=50`，`future.get(50ms)`，`TimeoutException`→`LOG.error`→返回 302）；`VisitLogTimeoutTest.redirectReturns302WhenVisitLogWriteTimesOut` 用永不完成的 Future 验证 302 |
| REQ-B-6 | 写入失败记 ERROR 后继续 302，不重试不补偿 | PASS | `recordVisitWithTimeout` 的 `ExecutionException` 非 NPE 分支→`LOG.error(…, cause)`→302（`ShortlinkController.java:117-122`）；NPE 分支原样重抛以在合并前保留 #3 的 500 行为（合并后 `record()` 已有空值保护，该分支成为防御性死路径，行为正确） |
| REQ-B-7 | 新接口不加鉴权，referer 敏感性作为持续风险记入 release-note | PASS（风险披露属 P7 交付物，已核对基线 Risk-4/OQ10 在册） | 无任何 security 配置引入，与既有接口一致；**提醒 Dev-Waker**：P7 `release-note.md` 必须落「统计接口未鉴权 + 流水含 referer 的敏感性」两条持续风险，不得因已裁定而省略 |
| REQ-B-8 | 测试覆盖落库/查询/limit 边界与默认/缺 referer 不变/#3 回归/写入超时 | PASS | 落库+查询：`VisitLogServiceTest` 5 用例（含落库、倒序、limit）；limit 边界与封顶：`ShortlinkControllerTest` 2 用例；缺 referer：`Issue3MissingRefererReproducerTest`（合并后语义）；写入超时：`VisitLogTimeoutTest` |

## 4. issue #3 热修回归核验与 bothFixesPreserved 独立复核

QA 不采信 P4 自报的 `bothFixesPreserved=true`，用 git 三方证据独立复原：

| 版本 | `VisitLogService.record()` referer 行为 | 持久化 |
| --- | --- | --- |
| `46ab733`（#2 实现，合并前） | `referer.toLowerCase(Locale.ROOT)`，**无**空值保护（逐字保持基线，满足 REQ-B-3） | H2 落库 |
| `46b344f`（#3 hotfix） | `referer == null ? null : toLowerCase`（空值保护） | 进程内 List |
| `28aca2c`（HEAD，经 `671cca8` 合并） | 空值保护 **且** H2 落库 | H2 落库 |

- 合并提交 `671cca8` 双亲为 `46498c1`（feature）与 `46b344f`（hotfix），与 `04-merge/conflict-resolution.md` 记录一致。
- 回归测试 `Issue3MissingRefererReproducerTest` 断言：无 Referer 的跳转返回 **302**（非 500）、Location 正确、`visit_log` 落库一行且 `referer` 为 null。QA 独立执行中该用例通过。
- **独立复核结论：`bothFixesPreserved=true` 成立**——#2 的落库改造（JdbcTemplate、recordAsync、findRecentByCode、snapshot、size、线程池关闭）与 #3 的空值保护同时存活于 HEAD。

## 5. 范围红线（非目标）核对

| 非目标 | 结论 |
| --- | --- |
| #2 分支不顺手修 Referer 500 | 未违反（git 证据见 §3 REQ-B-3；空值保护仅经 hotfix 合并进入） |
| 不做鉴权改造 | 未违反 |
| 不引入新中间件/外部服务 | 未违反（`spring-boot-starter-jdbc` 为框架库；`spotbugs-annotations` 为 provided 级注解库） |
| 不动 CI 配置、门禁阈值、分支规则集 | 未违反：feature 分支 `origin/main..HEAD` 内**零提交**触碰 `.github/workflows/`（此前 diff 中出现的 workflow 差异系 origin/main 自身前进所致，非本分支改动）；`pom.xml` 仅新增两个依赖，`coverage.line.minimum=0.60` 未动；无 skip 参数、无 `--no-verify`、无直推 main、无 force push |

## 6. QA 独立执行记录

命令（与 CI 同一钉死环境）：

```
export JAVA_HOME=/opt/homebrew/opt/openjdk@21
/opt/homebrew/bin/mvn -B clean verify
```

结果：**BUILD SUCCESS**（exit 0，2026-09-27 本机）

- Tests run: **35, Failures: 0, Errors: 0, Skipped: 0**（surefire 汇总）
- JaCoCo line coverage check：All coverage checks have been met（阈值 0.60）
- Checkstyle：0 违规；SpotBugs：BugInstance size 0
- Flyway schema gate（内存库）：2 条迁移成功应用至 v2

与 DevOps-Waker P5 门禁（build 15：tests 35/0/0、jacoco.line 83.83%、checkstyle 0、spotbugs 0、`jenkins/verify=success` 已回写 SHA `28aca2c`）交叉核对：**数字一致**。

## 7. 受限项与残余风险（如实披露）

1. **REQ-B-2 文件库子项未取得直接运行时证据**：QA 尝试以临时文件 H2 库（`/tmp` 下全新库、非仓库 `./data`）启动应用冒烟，进程启动命令被本地权限守卫拦截（`denied_approval_timeout`），按 SOP 不重试、不绕路。现有证据为：`flyway.enabled=true` 配置 + 内存库同一 classpath 迁移链全绿 + Flyway 对文件/内存 H2 走同一迁移机制。风险评级：低。如 Owner 在 G2 前要求直接证据，需人工批准一次本地冒烟启动。
2. **`limit` 非法值语义为实现解释**：基线未定义 `limit=0` 或负数的行为，实现取「回退默认 50」（`ShortlinkController.java:104-109`）。不构成违反；建议后续基线修订时明确。
3. **50ms 超时的语义**：超时后调用方放弃等待返回 302，但后台线程的 INSERT 可能仍会完成（`Future` 未 cancel）。与「不重试、不补偿」一致，记录为设计语义供 Owner 知悉。
4. **陈旧注释**：`VisitLogServiceTest` 类 javadoc 仍写「故意没有 referer 为 null 的用例」，合并后该路径已由 `Issue3MissingRefererReproducerTest` 覆盖，注释已过时（不影响行为，不要求返修，P7 顺手可清）。
5. **P7 交付前待核**：`release-note.md` 必须包含——统计接口未鉴权 + referer 敏感性（OQ10/Risk-4 持续风险）；`.devflow/issue-3/` 两份产物当前仍 untracked，需随交付一并提交。

## 8. 交接与下一步

- 验收结论：**issue #2 REQ-A/REQ-B 全部 PASS；issue #3 回归 PASS；bothFixesPreserved 独立复核成立**。无 CHANGES_REQUIRED 项，无阻塞项。
- 下一步责任链：Dev-Waker 提交本报告与 `.devflow/issue-3/` 产物 → 创建 PR 并完成 G2 自查 → Lead-Waker 主持 G2 人工门禁。
- **提交时序提醒**：P5 的 `jenkins/verify` 状态绑定在 SHA `28aca2c` 上。上述产物一旦提交进 feature 分支，HEAD SHA 变化，PR 将缺必需状态检查——需 DevOps-Waker 对**最终 SHA** 重跑一次门禁后再进 G2，属预期行为而非故障。
