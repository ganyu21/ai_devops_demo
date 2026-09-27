# P2 实现报告：issue #2 REQ-A / REQ-B

> 基线版本：v1.1  
> 实现分支：`feature/issue-2-cache-ttl-and-visit-log`  
> 阶段：P2 完成，待进入 P3（#3 缺陷热修）与 P4（冲突仲裁）

## 变更总览

| REQ | 主要文件 | 关键行为 |
| --- | --- | --- |
| REQ-A | `CachingLinkResolver.java` | 用同步 LRU + TTL 缓存替换无界 `ConcurrentHashMap`；写路径主动失效 |
| REQ-A | `ShortlinkProperties.java`, `application.yml` | 容量上限与 TTL 走配置项注入 |
| REQ-B | `VisitLogService.java` | 流水持久化到 H2；保留 `record()` 对 referer 的逐字行为（无空值保护） |
| REQ-B | `ShortlinkController.java` | 新增 `GET /api/links/{code}/visits`；跳转时 50ms 独立超时写入 |
| REQ-B | `V2__create_visit_log.sql`, `application.yml` | 新增 visit_log 表并启用 Flyway |
| REQ-B | `openapi.yaml` | 纯新增统计查询路径与 `VisitRecord` schema |
| 测试 | `CachingLinkResolverTest`, `VisitLogServiceTest`, `ShortlinkControllerTest`, `VisitLogTimeoutTest` | 覆盖新增行为与边界 |
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
- 跳转写入旁路：`ShortlinkController` 调用 `visitLog.recordAsync(...).get(50, MILLISECONDS)`；超时或 DB 失败记 ERROR 日志后继续返回 302；`NullPointerException` 被原样抛出，以保留缺失 Referer 时的 500 行为（#3 范围）。

## 未覆盖点（P2 现场核对）

| 未覆盖点 | 位置/场景 | 原因 | 是否可接受 |
| --- | --- | --- | --- |
| `CachingLinkResolver` 中 `removeExpired()` 的迭代分支 | 只有长时间无人访问且容量未触顶时，过期条目才会在 `cachedEntries()` 中被清理 | 惰性清理是设计；访问路径已覆盖 | 是 |
| `VisitLogService.shutdown()` 的 `@PreDestroy` | 应用关闭钩子 | 生命周期边界，难以在单元测试中稳定触发 | 是 |
| `ShortlinkController.redirect` 中 `ExecutionException` 非 NPE 分支的 ERROR 日志 | 需要模拟 DB 连接失败 | 超时路径已覆盖；DB 失败路径与超时路径日志级别一致 | 是 |

## 本地验证状态

- 命令：`export JAVA_HOME=/opt/homebrew/opt/openjdk@21 && /opt/homebrew/bin/mvn -B clean verify`
- 结果：见 P2 提交后的 CI/Jenkins 运行；本报告产出时本地已全绿。

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

- [x] `VisitLogService.record()` 没有 referer 空值保护。
- [x] `openapi.yaml` 中既有 `POST /api/links`、`GET /{code}` 定义未被改动。
- [x] `V1__create_short_link.sql` 未被修改。
- [x] 没有调低 `coverage.line.minimum`、没有 skip 参数、没有 `--no-verify`、没有直推 main、没有 force push。
- [x] 未引入中间件或外部服务；`spring-boot-starter-jdbc` 是框架内库，用于访问已配置的 H2 数据源。
- [x] P5/P7 合并门禁口径与 qoderai 自动审查纪律已折入 P2 设计产物与 `cr-checklist.md`。
