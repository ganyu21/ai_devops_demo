# P2 实现报告：issue #2 REQ-A / REQ-B

> 基线版本：v1.1（P2 产出时）→ **v1.2**（G2 退回后固化 OQ7 严格口径）  
> 实现分支：`feature/issue-2-cache-ttl-and-visit-log`  
> 阶段：P2 完成 → P3/P4 完成 → **G2 退回返修完成（2026-09-27，见文末返修记录）**

## 变更总览

| REQ | 主要文件 | 关键行为 |
| --- | --- | --- |
| REQ-A | `CachingLinkResolver.java` | 用同步 LRU + TTL 缓存替换无界 `ConcurrentHashMap`；写路径主动失效 |
| REQ-A | `ShortlinkProperties.java`, `application.yml` | 容量上限与 TTL 走配置项注入 |
| REQ-B | `VisitLogService.java` | 流水持久化到 H2；`recordAsync` 完全非阻塞，50ms 预算在旁路任务内部判断（G2 返修后） |
| REQ-B | `ShortlinkController.java` | 新增 `GET /api/links/{code}/visits`；跳转只提交旁路写入，请求线程不等待（G2 返修后） |
| REQ-B | `V2__create_visit_log.sql`, `application.yml` | 新增 visit_log 表并启用 Flyway |
| REQ-B | `openapi.yaml` | 纯新增统计查询路径与 `VisitRecord` schema；`referer` 保留 required + `nullable: true`（G2 返修） |
| 测试 | `CachingLinkResolverTest`, `VisitLogServiceTest`, `ShortlinkControllerTest`, `VisitLogTimeoutTest`, `VisitLogBypassFailureTest`, `OpenApiContractTest`, `VisitLogAwait` | 覆盖新增行为与边界；含旁路超时/失败/提交被拒与契约可空性 |
| 构建 | `pom.xml` | 新增 `spring-boot-starter-jdbc` 以使用 `JdbcTemplate` |

## REQ-A 实现细节

- 缓存实现：基于 `LinkedHashMap`（`accessOrder=true`）+ 显式同步，容量触顶时淘汰最久未访问条目，满足 LRU。
- TTL：每个条目带 `Instant expiresAt`，访问时惰性清理过期条目；`cachedEntries()` 也会先清理过期条目再返回数量。
- 配置绑定：`shortlink.resolve.cache.max-size=10000`、`shortlink.resolve.cache.ttl-minutes=10`，代码中不硬编码。
- 主动失效：`LinkResolver` 接口新增默认 `invalidate(String code)`；`ShortlinkController.create()` 在 `store.save()` 后调用，确保写路径上缓存即时失效。
- 退路：当前实现已完成主动失效；若后续 P4 仲裁或 P5 CI 暴露不可行问题，可退回「仅 TTL 10 分钟」，最长延迟写进交付文档。

## REQ-B 实现细节

- 表结构：`V2__create_visit_log.sql` 新建 `visit_log(code, referer, visited_at)`，并加 `(code, visited_at DESC)` 索引。
- Flyway：`application.yml` 中 `spring.flyway.enabled=true`，schema gate 会在内存 H2 上跑通 V1 + V2。
- `VisitLogService.record()`：对 `referer` 的处理与基线逐字一致——`referer.toLowerCase(Locale.ROOT)`，**没有加空值保护**，保证 #3 热修的对比证据链完整。
- 统计接口：`GET /api/links/{code}/visits`，`limit` 选填、默认 50、硬上限 200、不分页，返回 `code/referer/visitedAt`，按 `visitedAt` 倒序。
- 跳转写入旁路（**G2 返修后版本**）：`ShortlinkController.redirect()` 只调用 `visitLog.recordAsync(code, referer)` 提交后即返回；`VisitLogService.recordAsync()` 内部用 `CompletableFuture.runAsync(...).orTimeout(50ms).whenComplete(...)`，超预算与失败都只记 ERROR。请求线程没有任何等待；返回值是 `void`，调用方没有可等待的句柄。语义细节见 `06-delivery/release-note.md` 第 3 节（超时=不再等待，不取消、不保证未写入）。

## 未覆盖点（G2 返修后核对）

| 未覆盖点 | 位置/场景 | 原因 | 是否可接受 |
| --- | --- | --- | --- |
| `CachingLinkResolver` 中 `removeExpired()` 的迭代分支 | 只有长时间无人访问且容量未触顶时，过期条目才会在 `cachedEntries()` 中被清理 | 惰性清理是设计；访问路径已覆盖 | 是 |
| `VisitLogService.shutdown()` 的 `@PreDestroy` | 应用关闭钩子本身 | 生命周期边界，难以在单元测试中稳定触发；其后果（线程池已关闭时提交）已由单测覆盖 | 是 |
| `logBypassFailure` 的 `CompletionException 且 cause == null` 组合 | 异常解包的一支 | 该组合在 JDK 实现中不会出现（CompletionException 必然带 cause） | 是 |
| `VisitLogService.size()` 的 `count == null` 分支 | 计数查询返回 null | 沿用 P2 既有实现，与本次返修无关 | 是 |
| `ShortlinkController` 的短码碰撞重试循环体、超预算 WARN 分支、`effectiveLimit` 的 `limit <= 0` 分支 | 既有实现 | 沿用 P2 既有实现，与本次返修无关 | 是 |

已消除的旧未覆盖点：原「`ExecutionException` 非 NPE 分支的 ERROR 日志」随 `recordVisitWithTimeout` 一并删除（该分支即 G2 要求移除的 NPE 特判路径）。新增覆盖：旁路超时（含「不取消」断言）、旁路失败含 NPE、旁路提交被拒（线程池已关闭）。

## 本地验证状态

- 命令：`export JAVA_HOME=/opt/homebrew/opt/openjdk@21 && /opt/homebrew/bin/mvn -B clean verify`
- 结果：见 P2 提交后的 CI/Jenkins 运行；**G2 返修后重跑：38 tests / 0 failures，line coverage 88.76%，Checkstyle 0，SpotBugs 0，schema gate 通过。**

## G2 返修记录（2026-09-27）

G2 被 Requirement Owner 退回，真实阻塞项为 `required_review_thread_resolution`（PR #17 上 6 条未解决评审线程）；OQ7 给出严格口径「redirect 请求线程根本不该为统计写入阻塞」。本次返修四项逐项落地：

| # | 返修项（Lead 路由原文序号） | 实现 | 测试证据 |
| --- | --- | --- | --- |
| 1 | `VisitRecord.referer` 保留 required + `nullable: true` + 说明 | `openapi.yaml` | `OpenApiContractTest.visitRecordKeepsRefererRequiredButNullable` |
| 2 | 删除 NPE 特判重抛；旁路失败只记 ERROR 仍 302 | `ShortlinkController.redirect()` 直接提交 `recordAsync`；`recordVisitWithTimeout` 及其 NPE 分支删除 | `VisitLogBypassFailureTest` |
| 3 | 50ms 超时移出请求线程 | `VisitLogService.recordAsync()`：`runAsync + orTimeout(50ms) + whenComplete`，返回 `void` | `VisitLogTimeoutTest`（302 + 预算内 + ERROR + 不取消）；`VisitLogServiceTest.submittingAfterTheExecutorIsShutDownOnlyLogsAndDoesNotThrow` |
| 4 | 交付说明按新架构修订 | `.devflow/issue-2/06-delivery/release-note.md`（超时语义、无界队列建议、单锁与 O(n) 扫描、未经压测） | 本表 + release-note |

下游影响：5 处既有测试改为测试线程有界等待（`VisitLogAwait.untilRecorded`）；倒序用例在两次跳转间等待第一条可见以消除并发排序竞态；断言强度未降低。

## P5/P7 合并门禁口径（新增 qoderai 自动审查）

流程纪律更新：P7 合并资格新增 `qoderai` 自动审查的 `reviewDecision` 维度，`dismiss` 不可用；修复后推送会触发 qoderai 重跑。

对本 feature 的影响：

1. **qoderai 意见若与 G1 基线冲突，以 G1 基线为准**，并在 `cr-checklist.md` 与 G2 现场明确列出冲突点及裁定依据。
2. 若 qoderai 给出 `CHANGES_REQUESTED` 级别的审查结论，即使 Jenkins 门禁通过、GitHub 规则集状态检查通过，PR 仍视为**未满足合并资格**，DevOps-Waker 不得执行合并；须由 `Lead-Waker` 在 G2 人工门禁现场裁定是否按基线接受、要求 Dev-Waker 返修，或明确记录为可接受的例外。
3. 因 qoderai 重跑由推送触发，任何批准后再推送的提交都会让已有 `reviewDecision` 失效，PR 回到待审查态；G2 批准必须落在**当前最新 SHA** 上。
4. 若 qoderai 审查与 GitHub 规则集共同导致 `mergeStateStatus=BLOCKED`，`state.json` 应进入 `S6_MERGE_BLOCKED`，并附：
   - `github-lab.sh pr-status` 原始输出；
   - qoderai `reviewDecision` 状态；
   - 具体阻塞项（缺失 `jenkins/verify` / qoderai 未通过 / 评审线程未解决 / 规则集硬性要求等）；
   - 解除路径（例如由 Requirement Owner 在 G2 裁定、补充 qoderai 所需上下文、或等待 qoderai 重跑完成）。

Dev-Waker 在编制 `cr-checklist.md` 时已把 qoderai 审查结果作为独立检查项列入，并说明其与 G1 基线的对照结论。

## 范围纪律自审

- [x] #2 侧**没有添加** referer 空值保护（基线非目标第 1 条）；现 `record()` 中的 null 保护仅经 #3 hotfix 合并进入，仲裁记录见 `04-merge/conflict-resolution.md`。
- [x] `openapi.yaml` 中既有 `POST /api/links`、`GET /{code}` 定义未被改动。
- [x] `V1__create_short_link.sql` 未被修改。
- [x] 没有调低 `coverage.line.minimum`、没有 skip 参数、没有 `--no-verify`、没有直推 main、没有 force push。
- [x] 未引入中间件或外部服务；`spring-boot-starter-jdbc` 是框架内库，用于访问已配置的 H2 数据源。
- [x] P5/P7 合并门禁口径与 qoderai 自动审查纪律已折入 P2 设计产物与 `cr-checklist.md`。
- [x] G2 返修未改动 `openapi.yaml` 冻结的两条路径（变更仅在本次新增的 `VisitRecord.referer`）、未删除既有断言、未放宽任何门禁阈值、未改动 `.github/workflows/`。
