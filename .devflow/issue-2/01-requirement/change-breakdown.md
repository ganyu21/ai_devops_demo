# 需求拆解：issue #2 解析缓存加容量上限与 TTL；访问流水落库并提供统计查询接口

> 启动方式：新工单 / 冷启动  
> 需求提出人：Requirement Owner（human/owner）  
> 基线版本：**v1.2**（上一版本 v1.1，G2 返修后固化 OQ7 严格口径）  
> G1 状态：**已批准进入 P2**（v1.1 有效；v1.2 仅对 OQ7 做严格化解释，不重新打开已裁定问题）  
> G2 状态：**已退回返修**（Requirement Owner 对 OQ7 给出严格口径：统计写入是旁路，redirect 请求线程不得为写入同步等待；PM 已折入本版基线）  
> 创建时间：2026-09-27  
> 关联工单：#3（部分短链打开报 500，热修纳入本轮但走独立分支，仲裁时两侧修复都要保留）

## Fact

- 代码现状以 `main` 当前 HEAD 为准，并已用 `github-lab.sh issue 2` 与 `github-lab.sh issue 3` 核对过 issue 正文。
- `CachingLinkResolver`（`src/main/java/com/lab/shortlink/resolve/CachingLinkResolver.java`）使用无界 `ConcurrentHashMap` 做解析缓存，条目不过期；命中率高，但目标地址被更正后缓存旧条目仍然生效，且长期运行是慢性内存泄漏。
- `VisitLogService`（`src/main/java/com/lab/shortlink/visit/VisitLogService.java`）把流水保存在进程内 `List`：进程重启即丢、多实例不可见；`record(String code, String referer)` 直接对 `referer` 调用 `.toLowerCase(Locale.ROOT)`，缺失 Referer 时会抛出 NPE 并导致 500。
- `openapi.yaml` 里已发布的两个路径 `POST /api/links`、`GET /{code}` 自本基线冻结后只读；`Referer` 为可选 header，且被描述为正常流量。
- `application.yml` 中当前 `flyway.enabled=false`；`V1__create_short_link.sql` 已合入且只读。
- `pom.xml` 门禁阈值：`coverage.line.minimum=0.60`，Checkstyle 0 违规、SpotBugs 0 bug、schema 迁移在内存 H2 库上跑通。
- `main` 分支受规则集保护：必须走 PR、必需状态检查 `jenkins/verify`、评审线程必须解决、禁止 force push 与直推。

## Request

### REQ-A：给解析缓存加容量上限与 TTL

- 目标：替换 `CachingLinkResolver` 中的无界 `ConcurrentHashMap`，使缓存具备可配置的容量上限与 TTL；目标地址更新后，缓存旧条目应失效。
- affectedPaths（预计）：
  - `src/main/java/com/lab/shortlink/resolve/CachingLinkResolver.java`
  - `src/main/java/com/lab/shortlink/config/ShortlinkProperties.java`
  - `src/main/resources/application.yml`
  - `src/test/java/com/lab/shortlink/resolve/CachingLinkResolverTest.java`
- 验收标准：
  1. 容量上限按条数，上限 **10000**，通过配置项 `shortlink.resolve.cache.max-size=10000` 注入，代码中不硬编码。
  2. TTL **10 分钟**，不允许按环境覆盖，配置项 `shortlink.resolve.cache.ttl-minutes=10`。
  3. 淘汰策略为 **LRU**。
  4. 正确性优先：在「更正目标地址」写路径上**主动失效**对应短码的缓存条目；若实现不可行，退路为「只有 TTL 10 分钟」，最长 10 分钟的延迟必须写进交付文档，不得静默。
  5. `GET /{code}` 的既有响应码与对外契约保持不变；跳转耗时仍受 `RedirectBudgetTest` 的 300ms 预算约束。
  6. 新增/调整单元测试，覆盖命中、未命中、容量淘汰、TTL 失效、主动失效/退路场景。

### REQ-B：把访问流水落库，并提供一个统计查询接口

- 目标：将 `VisitLogService` 的访问流水持久化到 H2 数据库，并提供一个新的统计查询接口，供运营按短码查询最近访问。
- affectedPaths（预计）：
  - `src/main/java/com/lab/shortlink/visit/VisitLogService.java`
  - `src/main/java/com/lab/shortlink/api/ShortlinkController.java`
  - `src/main/resources/api/openapi.yaml`（纯新增路径/字段）
  - `src/main/resources/db/migration/V2__create_visit_log.sql`
  - `src/main/resources/application.yml`（启用 Flyway）
  - 新增/调整的测试类
- 验收标准：
  1. 新建 `visit_log` 表，schema 变更通过新增 `V2__create_visit_log.sql` 实现；`V1__*.sql` 不被修改。
  2. `spring.flyway.enabled=true`，确保应用在文件 H2 库上自动执行 V1 与 V2；schema gate 在内存库上跑通。
  3. `VisitLogService.record()` 对 referer 的处理行为与当前基线逐字一致，**不得顺手加空值保护**（issue #2 非目标第 1 条；#3 热修在独立分支 `hotfix/issue-3-referer-null` 处理）。
  4. 新增统计接口 `GET /api/links/{code}/visits`，参数 `limit` 选填、默认 50、硬上限 200，**不分页**；返回字段固定 `code` / `referer` / `visitedAt`；排序按 `visitedAt` **倒序**。
  5. 统计写入**不计入** 300ms 跳转预算，且 **redirect 请求线程不得为写入同步等待**；写入必须在请求线程外以旁路/异步方式执行，并设独立短超时 **50ms**，超时即放弃这次写入并记 ERROR 日志，继续返回 302，不重试、不补偿。
  6. 流水写入失败时记 ERROR 日志后继续返回 302，不重试、不补偿；不得因旁路写入异常（含 NPE）抛出并放大成主链路 5xx。
  7. 新接口**不加鉴权**，与现有接口一致；但访问流水含 `referer` 的敏感性作为持续风险记入 `release-note.md`。
  8. 测试覆盖记录落库、查询返回、`limit` 边界与默认、缺 referer 行为不变（#3 回归测试在 hotfix 分支）、写入超时旁路、旁路 NPE 仍为 302。

## Constraint

- 短码策略：8 位 base62，至少 47 bit 熵，由 `ShortCodeGenerator`、其测试、本约束节共同固定。
- 对外契约冻结：`POST /api/links`、`GET /{code}` 的既有请求结构、响应结构、既有响应码只读；仅允许纯新增。
- schema 变更只能新增：`V1__*.sql` 只读，新增 `V2__*.sql`。
- 跳转预算 300ms：`shortlink.redirect-budget-millis` 是对外承诺，任何进入跳转主链路的操作需先评估预算影响。
- 门禁阈值只能由人改：`coverage.line.minimum=0.60`、Checkstyle 0 违规、SpotBugs 0 bug、schema 迁移在内存库跑通。
- 构建环境钉死：`JAVA_HOME=/opt/homebrew/opt/openjdk@21` + `mvn -B clean verify`。
- 变更必须走 PR；`main` 禁止直推、force push 与管理员绕过。

## Risk / Non-Goal

### 明确的非目标（本次必须不做）

1. 不修缺失 Referer 时的 500；`VisitLogService.record()` 现有 referer 处理行为必须逐字保持。这是 issue #3 的范围，顺手修复会破坏 #3 热修的对比证据链。
2. 不做鉴权体系改造。
3. 不引入新的中间件或外部服务。
4. 不动 CI 配置、门禁阈值与分支规则集。

### 已知风险

1. **与 #3 的代码冲突**：REQ-B 要重写 `VisitLogService.record()` 与方法体/字段，#3 要在旧内存版 `record()` 里加 referer 空值保护；两边合并时会在同一方法产生真实冲突，必须由 Dev 仲裁，严禁整文件取一边。
2. **跳转预算被打破（OQ7 严格口径）**：统计写入必须在 redirect 请求线程外以旁路/异步执行，redirect 线程不得同步等待；任何同步等待（包括 `future.get(50ms)`）都会把写入耗时落入客户端感知的响应时间，违反 300ms 预算承诺。
3. **缓存命中率与即时生效的矛盾**（Conflict C1）：已裁定正确性优先，写路径主动失效；若主动失效不可行，退路为最长 10 分钟延迟，必须写进交付文档。
4. **数据敏感（OQ10 已接受风险）**：访问流水含 `referer`，比短码本身敏感。统计接口不加鉴权，该风险要写成持续风险留在 `release-note.md`，不得因「已经裁定过」而删除。
5. **Flyway 启用影响**：当前 `application.yml` 中 `flyway.enabled=false`；REQ-B 启用 Flyway 后，需验证 V1 与 V2 在文件 H2 库上的行为符合预期，且不破坏既有测试。

## Open Question

以下 10 条问题已由 Requirement Owner 在 G1 裁定，**原话与结论均原样保留**；G2 返修对 OQ7 做了严格化解释，但**不重新打开**已裁定问题。

1. **OQ1 缓存上限**：按条数还是按内存占用？数值是多少？
   - **裁定原话**：按**条数**，上限 **10000**。理由：按内存占用核算要引入对象大小估算，收益不抵复杂度；条数上限足以挡住无界增长。上限值必须走配置项，不得硬编码。
   - **折入验收标准**：REQ-A-1。

2. **OQ2 TTL**：多长时间？允许按环境不同吗？
   - **裁定原话**：**10 分钟**，**不允许按环境覆盖**。理由：环境之间行为漂移，会让「为什么这个短码还跳旧地址」变成猜谜。
   - **折入验收标准**：REQ-A-2。

3. **OQ3 淘汰策略**：LRU / FIFO / LFU 哪一种？
   - **裁定原话**：**LRU**。理由：FIFO 会把热点短码淘汰掉，命中率掉得比 LRU 明显；LFU 要维护频次计数，本期不值得。
   - **折入验收标准**：REQ-A-3。

4. **OQ4 统计接口形态**：路径、参数、是否分页、返回字段、排序分别是什么？
   - **裁定原话**：路径 `GET /api/links/{code}/visits`；参数 `limit` 选填，默认 50，硬上限 200；**不分页**；返回字段固定 `code` / `referer` / `visitedAt`；排序按 `visitedAt` **倒序**。理由：挂在已有资源下属于纯新增，不动 `openapi.yaml` 里两个既有路径的定义；不分页是因为硬上限已经挡住了大响应，多一套分页语义不划算。
   - **折入验收标准**：REQ-B-4。

5. **OQ5 「最近的访问」定义**：最近 N 条还是某个时间窗？
   - **裁定原话**：**最近 N 条**，默认 50，`limit` 可覆盖，硬上限 200。理由：时间窗在流量稀疏的短码上会返回空，运营看到的是「没有数据」而不是「没人访问」，两者分不清。
   - **折入验收标准**：REQ-B-4。

6. **OQ6 流水表设计**：存到哪张表？复用 `short_link` 还是新建？要不要启用 Flyway？
   - **裁定原话**：**新建 `visit_log` 表**，写成 `V2__create_visit_log.sql`，**同时把 `spring.flyway.enabled` 打开**。理由：`V1` 已合入即只读，一个字段都不许改；`short_link` 存的是链接本体，往里塞流水会把两个生命周期绑死。打开 Flyway 之后，schema 门禁会在内存库上真跑一遍 V2，脚本写错就是红灯。
   - **折入验收标准**：REQ-B-1、REQ-B-2。

7. **OQ7 统计写入是否计入跳转预算**？
   - **裁定原话**：**不计入**，但给写入设一个**独立的短超时（50ms）**，超时即放弃这次写入。理由：统计是旁路，不能挤占跳转主链路；但完全不设超时的话，一次慢写入就能把 300ms 的对外承诺打破。
   - **G2 严格口径（Requirement Owner 原话，不重新打开 OQ7）**："OQ7「统计写入不计入 300ms 跳转预算」按严格读法算数：请求线程根本不该为统计写入阻塞。裁定原话的理由部分写的是「统计是旁路，不能挤占跳转主链路」，而当前实现是 redirect() 里先记 startedAt、再调 recordVisitWithTimeout（内部 future.get(50ms)）、之后才算 elapsedMillis，那最多 50ms 落在计量窗口内，也落在客户端感受到的响应时间里。PM-Waker 请把这个口径明确写回 change-breakdown.md 的 OQ7 裁定并升基线版本，否则下一轮还会撞上同一个分歧。"
   - **折入验收标准**：REQ-B-5、Risk-2。

8. **OQ8 流水写入失败时的行为**？
   - **裁定原话**：**记 ERROR 日志后继续返回 302**，不重试、不补偿。理由：旁路故障放大成主链路 5xx，会让本来能打开的短链变成打不开——这正是 issue #3 那个缺陷的成因类型，不能再造一个。
   - **折入验收标准**：REQ-B-6。

9. **OQ9 数据暴露**：要不要把这些数据暴露成监控指标？
   - **裁定原话**：**本期只记日志**，监控指标另开需求。理由：多一个暴露面就多一处要验收的东西，而本期验收重点是落库与查询。
   - **折入验收标准**：无新增产品功能，作为持续风险记录。

10. **OQ10 新接口鉴权**：要不要加鉴权？
    - **裁定原话**：**不加鉴权，与现有接口一致**。但必须附带一条：访问流水含 `referer`，比短码本身敏感（它能看出用户从哪个站点过来）。所以这条要写成**持续风险**记进 `release-note.md`，**不能因为已经裁定过就悄悄删掉**。裁定可以接受风险，交付文档不可以隐藏风险。
    - **折入验收标准**：REQ-B-7、Risk-4。

## Conflict

以下 2 条冲突已由 Requirement Owner 在 G1 裁定，**原话与结论均原样保留**；后续续跑不得重新提出。

- **C1 缓存即时生效 vs 命中率**：
  - **裁定原话**：**正确性优先**。TTL 10 分钟（同 OQ2）；并且**在「更正目标地址」这条写路径上主动失效对应短码的缓存条目**。理由：命中率不该靠长 TTL 维持，而该靠写时失效；这样两条要求不再对立。退路：如果实现下来写时失效不可行，退回「只有 TTL 10 分钟」，接受最长 10 分钟的延迟，**且这个延迟必须写进交付文档**，不得静默。
  - **折入验收标准**：REQ-A-4。

- **C2 需求 #2 与缺陷 #3 的代码冲突**：
  - **裁定原话**（共三条）：
    1. **#3 的热修纳入本轮交付**，但走**独立分支** `hotfix/issue-3-referer-null`，从 `main` 切出，先跑红再修绿。
    2. **#2 侧仍然不得顺手加空值保护**——issue #2「明确的非目标」第 1 条不变。REQ-B 重写 `record()` 时，对 referer 的处理行为必须与当前基线**逐字一致**，把缺陷原样带过去。
    3. **仲裁顺序**：hotfix 合回 feature 时，两侧各自想生效的修复都要保留（落库改造 + 空值保护），**严禁整文件取一边、严禁 `-X ours/-X theirs`**。验收标准是**两侧测试的并集全绿**，并在 `04-merge/conflict-resolution.md` 里逐处记录 ours 语义 / theirs 语义 / decision / rationale，给出 `bothFixesPreserved` 的判定与依据。
  - 理由：热修分支正是真冲突的来源。把 #3 排除在本轮之外，仲裁环节就没有素材，只能靠人手造假冲突——那这一轮最值钱的一段就没了。
  - **折入验收标准**：REQ-B-3、非目标第 1 条、Risk-1、Plan Branches。

## Plan Branches

- 需求 #2 实现分支：`feature/issue-2-cache-ttl-and-visit-log`（从 `main` 切出，本基线已提交到该分支）。
- 缺陷 #3 热修分支：`hotfix/issue-3-referer-null`（从 `main` 切出，由 P3 阶段 DevOps/Dev 创建；热修纳入本轮交付但独立分支）。
- 合并策略：需求分支与热修分支在 P4 通过合并仲裁解决冲突；严禁 `git checkout --ours/--theirs` 整文件取一边，严禁 `-X ours`/`-X theirs`。
