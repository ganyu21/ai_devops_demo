# 需求拆解：issue #2 解析缓存加容量上限与 TTL；访问流水落库并提供统计查询接口

> 启动方式：新工单 / 冷启动  
> 需求提出人：Requirement Owner（human/owner）  
> 基线版本：v1.0  
> 创建时间：2026-09-27  
> 关联工单：#3（部分短链打开报 500，与 #2 在 `VisitLogService.record()` 上存在冲突风险）

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
  1. 容量上限与 TTL 的具体数值/策略由 OQ1-OQ3 裁定后写入配置，代码中不硬编码。
  2. 缓存条目在超过容量或到期后被淘汰；超过容量时的淘汰策略由 OQ3 裁定。
  3. 短链目标地址更新后，再次访问同一短码不得返回旧的 `targetUrl`（旧缓存条目失效）。
  4. `GET /{code}` 的既有响应码与对外契约保持不变；跳转耗时仍受 `RedirectBudgetTest` 的 300ms 预算约束。
  5. 新增/调整单元测试，覆盖命中、未命中、容量淘汰、TTL 失效、旧条目失效场景。

### REQ-B：把访问流水落库，并提供一个统计查询接口

- 目标：将 `VisitLogService` 的访问流水持久化到 H2 数据库，并提供一个新的统计查询接口，供运营按短码/来源等维度查询。
- affectedPaths（预计）：
  - `src/main/java/com/lab/shortlink/visit/VisitLogService.java`
  - `src/main/java/com/lab/shortlink/api/ShortlinkController.java`
  - `src/main/resources/api/openapi.yaml`（纯新增路径/字段）
  - `src/main/resources/db/migration/V2__create_visit_log.sql`
  - `src/main/resources/application.yml`（按需启用 Flyway）
  - 新增/调整的测试类
- 验收标准：
  1. 访问流水写入 H2 数据库，进程重启后数据不丢失（通过重启类集成测试或 schema gate 验证）。
  2. 新增统计查询接口的路径、参数、分页、字段、排序由 OQ4-OQ5 裁定后写入 `openapi.yaml`，并新增对应的 controller/测试。
  3. schema 变更通过新增 `V2__create_visit_log.sql` 实现；`V1__*.sql` 不被修改。
  4. `VisitLogService.record()` 对 referer 的处理行为与当前基线逐字一致（见「非目标」第 1 条），不得顺手加空值保护。
  5. 流水写入失败不得阻塞主链路 302 跳转；写入必须是在预算内的旁路或带独立短超时。
  6. 新增测试覆盖记录落库、查询返回、边界条件。

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
2. **跳转预算被打破**：如果流水写入或缓存淘汰被同步放入跳转主链路，可能导致 `RedirectBudgetTest` 失败。
3. **缓存命中率与即时生效的矛盾**（Conflict C1）：容量/TTL 设置过短会降低命中率，设置过长会延迟目标地址更新生效。
4. **数据敏感**：访问流水含 referer，统计接口若不加鉴权可能泄露用户来源；本次非目标明确不做鉴权体系改造，属于被接受但需持续携带的风险。
5. **Flyway 启用影响**：当前 `application.yml` 中 `flyway.enabled=false`；REQ-B 若启用 Flyway，需确认 V1 与 V2 在文件 H2 库上的行为符合预期。

## Open Question

以下问题必须由 Requirement Owner 逐条给出带内容的裁定后方可进入实现；「按推荐的来」不算裁定。

1. **OQ1 缓存上限**：按条数还是按内存占用？数值是多少？
2. **OQ2 TTL**：多长时间？是否允许按环境不同？
3. **OQ3 淘汰策略**：LRU / FIFO / LFU 选哪一种？
4. **OQ4 统计接口形态**：路径、参数、是否分页、返回字段、排序分别是什么？
5. **OQ5 「最近的访问」定义**：最近 N 条还是某个时间窗？
6. **OQ6 流水表设计**：存到哪张表？复用 `short_link` 还是新建？要不要启用 Flyway？
7. **OQ7 统计写入是否计入跳转预算**？
8. **OQ8 流水写入失败时的行为**？
9. **OQ9 数据暴露**：要不要把这些数据暴露成监控指标？
10. **OQ10 新接口鉴权**：要不要加鉴权？

## Conflict

- **C1 缓存即时生效 vs 命中率**：「目标地址更正后要马上生效」要求缓存条目短生命周期；「高命中率」要求缓存条目长生命周期。二者在当前实现下对立。需要 Requirement Owner 裁定优先级，或给出让两条不再对立的方案（例如主动失效、双缓存等）。
- **C2 需求 #2 与缺陷 #3 的代码冲突**：REQ-B 重写 `VisitLogService.record()`（字段从内存 List 改为 DB 落库，方法体重写），#3 热修在旧的内存版 `record()` 中增加 `referer` 空值保护。两侧会在 `VisitLogService.java` 的 `record()` 方法产生真实 Git 冲突。仲裁原则：两侧修复必须都保留；整文件取一边会让另一侧修复静默丢失。最终裁决待 Requirement Owner 确认 #3 热修范围是否纳入本交付，以及 #2 是否确实不修 #3（issue #2 非目标已明确不修 #3）。

## Plan Branches

- 需求 #2 实现分支：`feature/issue-2-cache-ttl-and-visit-log`（从 `main` 切出，本基线已提交到该分支）。
- 缺陷 #3 热修分支：`hotfix/issue-3-referer-null`（从 `main` 切出，由 P3 阶段分诊后创建）。
- 合并策略：需求分支与热修分支在 P4 通过合并仲裁解决冲突；严禁 `git checkout --ours/--theirs` 整文件取一边，严禁 `-X ours`/`-X theirs`。
