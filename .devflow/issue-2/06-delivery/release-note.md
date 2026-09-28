# Issue #2 交付说明（release-note）

> 基线：**v1.2**（G2 退回后由 PM 固化 OQ7 严格口径）
> 分支：`feature/issue-2-cache-ttl-and-visit-log`　PR：`#17`
> 本文件对应 **G2 退回后的返修实现**，状态：已合入 main（merge commit `a66c58a`），main 门禁 run `36359920872` 结论 GREEN。

## 1. 交付范围

| REQ | 内容 | 关键落点 |
| --- | --- | --- |
| REQ-A | 解析缓存容量上限 10000 + TTL 10 分钟 + LRU + 写路径主动失效 | `CachingLinkResolver`、`ShortlinkProperties`、`application.yml` |
| REQ-B | 访问流水落库（H2 / Flyway V2）+ 统计查询接口 `GET /api/links/{code}/visits` | `VisitLogService`、`V2__create_visit_log.sql`、`ShortlinkController`、`openapi.yaml`（纯新增） |

## 2. G2 返修内容（2026-09-27，对应 Lead 路由的四项）

| # | 返修项 | 落地 | 证据 |
| --- | --- | --- | --- |
| 1 | `VisitRecord.referer` 保留 required，补 `nullable: true` 并说明缺失 Referer 是正常流量、字段为 null | `openapi.yaml`（VisitRecord.referer） | `OpenApiContractTest.visitRecordKeepsRefererRequiredButNullable` |
| 2 | 删除 `recordVisitWithTimeout` 的 NPE 特判重抛；旁路任何失败（含 NPE）只记 ERROR，仍返回 302 | `ShortlinkController.redirect()` 直接调用 `visitLog.recordAsync(...)` | `VisitLogBypassFailureTest`（旁路 NPE → 302 + Location + ERROR 日志） |
| 3 | 50ms 超时移出 redirect 请求线程，落在旁路任务内部处理 | `VisitLogService.recordAsync()`：`CompletableFuture.runAsync` + `orTimeout(50ms)` + `whenComplete`；返回值改为 `void`，调用方没有可等待的句柄 | `VisitLogTimeoutTest`（慢写：302 + 预算内返回 + ERROR 日志 + 写入未被取消） |
| 4 | 交付说明按新架构如实修订（超时语义、线程池队列、缓存并发与扫描、未压测） | 本文件第 3、4 节 | 本文件 |

## 3. 超时语义（本次返修后的准确表述）

- **请求线程从不等待统计写入**：300ms 跳转预算的计量窗口内不存在任何统计写入等待（原实现有 `future.get(50ms)` 落在窗口内，已删除）。
- 50ms 现在的角色是**旁路预算的告警阈值**：写入超过 50ms 记 ERROR 日志，仅此而已。基线文字里的「超时即放弃这次写入」按 OQ7 严格口径理解为**不再等待**——
- 超时**不取消**写入任务（不 `cancel`、不中断线程），也**不保证未写入**：DB 慢写时数据最终仍可能落库。
- **不重试、不补偿**；跳转与统计查询之间是**最终一致**：存在「已跳转、尚未可见」的短暂窗口。生产代码无同步等待；测试侧用有界等待观察（`VisitLogAwait.untilRecorded`，发生在测试线程）。

## 4. 遗留风险（持续风险，OQ10 等已裁定项也不得删除）

1. **统计接口无鉴权 + referer 数据敏感**（OQ10 已接受风险）：访问流水含 `referer`，比短码本身敏感；新接口按基线不加鉴权，该风险持续存在，需要时另行补访问控制。后续：对外文档写明该接口的可见范围与使用场景；若未来扩展统计字段（如 UA、IP 段），先行评估分级鉴权或脱敏。
2. **旁路线程池为固定 2 线程 + 无界 `LinkedBlockingQueue`**（后续建议，非本次返修项）：写入持续慢于提交时任务在队列中无界堆积（内存增长 + 写入延迟单调增大）；50ms 预算只控制「不再等待」，**不提供背压**。建议后续改为**有界队列 + 拒绝策略**（如队列满时丢弃并记 ERROR）并考虑队列长度监控阈值，本期不做。**关闭语义**：`@PreDestroy shutdownNow()` 会尝试中断在跑任务并拒绝新提交，队列中尚未执行的写入可能被丢弃——目前只有日志、没有更强的闭店协议，同为后续改进项。
3. **缓存实现是单锁 + O(n) 过期扫描**（Owner 已裁定不返修，但必须写清）：`CachingLinkResolver` 的所有读、写、失效在同一把锁上串行化（单锁并发特性）；`removeExpired()` 每次全量扫描，命中越少锁持有时间越长，与淘汰/写入相互放大；上述并发特性**未经压测**——「没测过」不等于「没问题」，不得当成已验证结论继承。后续优化方向：把过期扫描从 `cachedEntries()` 剥离为后台维护任务或分段处理以降低锁粒度；盘点 `cachedEntries()` 调用方，避免监控/指标采集类高频路径反复触发全量扫描。
4. **最终一致性窗口**：见第 3 节，跳转后立刻查询可能看不到该次访问。

## 5. 返修影响面（对既有测试的下游影响）

- 架构改为「请求线程不等待」后，5 处「跳转后立即读库」的既有断言必须改为测试线程有界等待：`ShortlinkControllerTest` 4 处、`Issue3MissingRefererReproducerTest` 1 处（302 / Location / null-referer 落库的断言本身不变）。
- 倒序用例在两次跳转之间增加一次「等待第一条写入可见」，让 `visitedAt` 严格有序、消除并发写入的排序竞态；**断言强度未降低**（仍要求 source-b 在前、source-a 在后）。
- `recordAsync` 由返回 `Future` 改为 `void`：调用方不再拥有「等待/超时控制」的接口形状，从 API 上杜绝回退到请求线程 `get()`。
- 范围未扩：`V1__*.sql`、`openapi.yaml` 冻结路径、门禁阈值、CI 配置均未改动；#2 侧仍未添加 referer 空值保护（该保护只经 #3 hotfix 进入）。
- qoderai 重审（2026-09-27T15:03Z）建议放宽测试观测窗口：`VisitLogAwait` 的等待窗口 5s → 15s，超时消息写明「窗口超时 ≠ 请求线程阻塞」；**断言强度不变**（仍要求记录条数与顺序，真丢写会在窗口耗尽后失败，不静默通过）。

## 6. 门禁轨迹与验证状态

| 项 | 结论 |
| --- | --- |
| 本地 `mvn -B clean verify`（返修后） | ✅ 38 tests / 0 failures；line coverage 88.76%（阈值 0.60）；Checkstyle 0；SpotBugs 0；schema gate 在内存库跑通 V1+V2 |
| Jenkins build 15（返修前历史结论） | ✅ `gateVerdict=GREEN`，35/0/0，jacoco.line=83.83%——**返修后不再作为最终口径** |
| GitHub Actions `mvn-verify`（PR #17 最终 head `b20de48`） | ✅ `github-lab.sh pr-status 17`：`mvn-verify` COMPLETED/SUCCESS，`qoder-review` COMPLETED/SUCCESS，`reviewThreads` 19 total / 0 unresolved，`blockingReasons=[]`，`mergeStateStatus=CLEAN` |
| qoderai 审查（PR #17 最终 head `b20de48`） | ✅ `reviewDecision` 无阻塞结论；全部线程逐条回帖 + `pr-resolve`（判定见 `cr-checklist.md` 对照表） |
| G2 人工门禁 | ✅ Requirement Owner 于 2026-09-27 批准合并 |
| 合入 main 后门禁（run `36359920872`） | ✅ `result=SUCCESS`，`gateVerdict=GREEN`；38 tests / 0 fail / 0 skip；jacoco.line=88.75740%（150/169）；checkstyle.violations=0；spotbugs.bugs=0 |
| P6 独立验收 | ✅ QA-Waker 在 `7f61270` 上独立验收 PASS（含 REQ-B-5 预算维度、REQ-A-5 可空性、旁路 NPE 仍 302） |

## 7. 未覆盖点（分类，见 `02-dev/impl-report.md` 明细）

- 保留（可接受）：`logBypassFailure` 中 `CompletionException 且 cause 为 null` 的组合分支——该组合在 JDK 实现中不会出现；`size()` 的 `count == null` 分支（沿用 P2 既有实现）。
- 保留（与本次返修无关的既有缺口）：`create()` 短码碰撞重试循环体、redirect 超预算 WARN 分支、`effectiveLimit` 的 `limit <= 0` 分支。
- 本次返修**新增覆盖**：旁路超时（含「不取消」）、旁路失败（含 NPE）、旁路提交被拒（线程池已关闭）三条路径均有测试。
