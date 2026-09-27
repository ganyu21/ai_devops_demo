# Issue #2 准出自查清单（cr-checklist）

> Dev-Waker 执笔，P5/P7 阶段逐项核对。本清单与 `merge-block-criteria.md`、`state.json` 共同作为合并资格证据。

## 需求与基线

| 检查项 | 结论 | 证据 / 备注 |
| --- | --- | --- |
| REQ-A 缓存容量上限 + TTL + LRU 已实现 | ✅ | `CachingLinkResolver.java`, `ShortlinkProperties.java`, `application.yml` |
| REQ-B 访问流水落库 + 统计查询接口已实现 | ✅ | `VisitLogService.java`, `V2__create_visit_log.sql`, `ShortlinkController.java` |
| G1 v1.1 基线已折入 change-breakdown.md 与验收标准 | ✅ | `.devflow/issue-2/01-requirement/change-breakdown.md` |
| 编号稳定、分支名 slug 未漂移 | ✅ | `feature/issue-2-cache-ttl-and-visit-log` |

## 契约与范围纪律

| 检查项 | 结论 | 证据 / 备注 |
| --- | --- | --- |
| 既有 `POST /api/links`、`GET /{code}` 未改动 | ✅ | `openapi.yaml` diff |
| `V1__create_short_link.sql` 未修改 | ✅ | git diff |
| #2 侧未添加 referer 空值保护 | ✅ | P2 实现为 `referer.toLowerCase(Locale.ROOT)`；现 `record()` 中的 null 保护仅经 #3 hotfix 合并进入（P4 仲裁） |
| 未调低门禁阈值、未 skip 插件、未 `--no-verify`、未 force push | ✅ | `pom.xml` 与 CI 命令 |
| 未引入外部中间件 | ✅ | 仅 `spring-boot-starter-jdbc` 访问已配置的 H2 数据源 |

## 本地验证

| 检查项 | 结论 | 证据 / 备注 |
| --- | --- | --- |
| `mvn -B clean verify` 通过（G2 返修后） | ✅ | 命令：`export JAVA_HOME=/opt/homebrew/opt/openjdk@21 && /opt/homebrew/bin/mvn -B clean verify` |
| 38 tests，0 failures/errors | ✅ | G2 返修后重跑（返修前为 35，新增/改写用例见 impl-report 返修记录） |
| Checkstyle 0 / SpotBugs 0 / JaCoCo ≥ 0.60 | ✅ | G2 返修后重跑：line coverage 88.76%，Checkstyle 0，SpotBugs 0 |

## P4 冲突仲裁

| 检查项 | 结论 | 证据 / 备注 |
| --- | --- | --- |
| #3 hotfix 已合并进 feature 分支 | ✅ | 合并提交 `671cca8`：双亲 `46498c1`（feature）+ `46b344f`（hotfix） |
| `VisitLogService` 两侧修复均保留 | ✅ | DB 持久化（issue #2）+ null-referer 保护（issue #3）+ DB 版 `snapshot()` |
| 冲突仲裁记录已提交 | ✅ | `.devflow/issue-2/04-merge/conflict-resolution.md`；`bothFixesPreserved=true` |
| issue #3 产物已随交付提交 | ✅ | `.devflow/issue-3/03-hotfix/hotfix-report.md`、`.devflow/issue-3/05-gate/merge-block-criteria.md` |

## P5 CI 门禁

| 检查项 | 结论 | 证据 / 备注 |
| --- | --- | --- |
| Jenkins 门禁（历史有效） | ✅ | build 15，`gateVerdict=GREEN`；tests 35/0/0；jacoco.line=83.83%；checkstyle=0；spotbugs=0 |
| commit status 已回写 | ✅ | context `jenkins/verify`，state `success`，SHA `28aca2cd6d7c57fd2968b2587d0ada8659d4a49b` |
| GitHub Actions `mvn-verify` check run（G2/P7 引用口径） | ⏳ | 返修前 HEAD（`2e5f19e`）为 `SUCCESS`；**返修推送后必须取新 SHA 的结论**，旧结论不代表返修后代码 |
| 门禁结论文档已提交 | ✅ | `.devflow/issue-2/05-gate/p5-ci-verdict.md`（已注明 CI 载体变更） |
| P5 复验（G2 返修后） | ⏳ | 待返修提交推送 → GitHub Actions 自动触发 `mvn-verify` → 由 DevOps-Waker 用 `github-lab.sh pr-status` 复核 |

## P6 独立验收

| 检查项 | 结论 | 证据 / 备注 |
| --- | --- | --- |
| QA-Waker 独立验收结论（返修前） | ✅ PASS（已失效） | `.devflow/issue-2/06-qa/acceptance-report.md`：14/14 通过；但 G2 指出 REQ-B-5 的 PASS 证据不足（`VisitLogTimeoutTest` 只验 302 未验预算），且 REQ-A-5 存在测试覆盖缺口（新增 schema 可空性未校验） |
| issue #3 回归核验（返修前） | ✅ PASS（已失效） | `bothFixesPreserved=true` 经 QA 独立复核成立；返修后需重做 |
| P6 复验（G2 返修后） | ⏳ | 待 QA-Waker 补独立验收证据：REQ-B-5 预算维度（慢写不影响 302 与跳转预算）、REQ-A-5 新增 schema 可空性、旁路 NPE 仍 302 |

## qoderai 自动审查与 G1 基线对照

G2 时 PR #17 上有 6 条未解决线程（`github-lab.sh pr-status 17`：`blockingReasons=["required_review_thread_resolution: 6 条评审线程未解决"]`）。逐条裁定如下，返修项对应 `impl-report.md` 的 G2 返修记录：

| threadId | 位置 | 意见摘要 | 与 v1.2 基线关系 | 处理 |
| --- | --- | --- | --- | --- |
| `PRRT_kwDOUs8Szs6mbVcl` | openapi.yaml（VisitRecord） | `required` 声明与「缺 Referer 返回 null」硬冲突 | 不冲突，属契约不精确 | 采纳：referer 保留 required + `nullable: true` + 说明（返修 1） |
| `PRRT_kwDOUs8Szs6maOhO` | openapi.yaml | 同上 + 跳转主链路语义（与 `…mbVdK`/`…maFg_` 合并处理） | 同上 | 采纳（返修 1、2、3） |
| `PRRT_kwDOUs8Szs6maFfl` | openapi.yaml:119 | 契约与实现错位：null 落库 vs 非空声明 | 同上 | 采纳（返修 1） |
| `PRRT_kwDOUs8Szs6mbVdK` | ShortlinkController.java:117 | NPE 特判重抛违背 OQ8 与 AGENTS.md 审查红线 | 与基线一致（旁路故障不得放大成 5xx；#3 合并后该分支已不可达） | 采纳：删除该分支（返修 2） |
| `PRRT_kwDOUs8Szs6maFg_` | ShortlinkController.java:111 | 超时只录日志不 cancel；语义未说明；同步等待落在请求线程 | 与 OQ7 严格口径（v1.2）一致 | 采纳：50ms 超时移入旁路 + 语义写入 release-note（返修 3、4） |
| `PRRT_kwDOUs8Szs6maFgl` | CachingLinkResolver.java:44 | 单锁串行化、O(n) 过期扫描的并发特性 | 不冲突；Owner 已裁定本期不返修 | **不返修**：按裁定把三件事写入 release-note 第 4 节（单锁、O(n) 扫描放大锁持有、**未经压测**） |

处理纪律：先以可核验证据（commit / 文件 / 测试名）在对应线程回帖，再用 `pr-resolve` 写明理由；推送会触发 qoderai 重跑，可能产生新线程，同样逐条裁定——收尾条件是「每条线程都有一次裁定」，不是「意见数归零」。

**纪律**：
1. qoderai `reviewDecision` 为合并资格维度，`dismiss` 不可用；修完推送会触发重跑。
2. qoderai 意见若与 G1 基线冲突，以 G1 基线为准，并在 G2 现场由 Requirement Owner 裁定。
3. G2 批准绑定到具体 SHA；批准后推送新提交则批准失效。
4. P5 的 Jenkins `jenkins/verify` 状态仍有效，但 G2/P7 以 GitHub Actions `mvn-verify` check run 为引用口径；提交 P6/P7 产物后 HEAD 前移，需 DevOps-Waker 确认最终 SHA 的 `mvn-verify` check 与 qoderai `reviewDecision` 均通过后再进 G2。
5. 禁止手动 dispatch `mvn-verify`、禁止 dismiss qoderai review、禁止改动 `.github/workflows/`。

## 人工门禁 G2

| 检查项 | 结论 | 证据 |
| --- | --- | --- |
| G2 首次提交 | ❌ 退回返修 | Requirement Owner 于 2026-09-27 驳回：真实阻塞 `required_review_thread_resolution`（6 条线程）；另裁 OQ7 严格口径并给出返修清单 |
| G2 重新提交 | ⏳ | 待返修提交推送、P5/P6/P7 复验完成后由 Lead-Waker 主持 |

## 合并资格结论

- 当前状态：**G2 返修已提交（代码/测试/文档）**；6 条评审线程按表逐条回帖 + `pr-resolve`；待新 SHA 的 `mvn-verify`、qoderai 重审结果与 P6 复验
- 是否满足合并资格：⏳ 待上述复验完成后核定；6 条线程已有裁定，重审若产生新线程同样逐条裁定
- 若不满足，阻塞项与解除路径见 `.devflow/issue-2/05-gate/merge-block-criteria.md`
