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
| `VisitLogService.record()` 未加 referer 空值保护（#2 范围） | ✅ | P2 实现仍调用 `referer.toLowerCase(Locale.ROOT)`，#3 热修不混入 |
| 未调低门禁阈值、未 skip 插件、未 `--no-verify`、未 force push | ✅ | `pom.xml` 与 CI 命令 |
| 未引入外部中间件 | ✅ | 仅 `spring-boot-starter-jdbc` 访问已配置的 H2 数据源 |

## 本地验证

| 检查项 | 结论 | 证据 / 备注 |
| --- | --- | --- |
| `mvn -B clean verify` 通过 | ✅ | 命令：`export JAVA_HOME=/opt/homebrew/opt/openjdk@21 && /opt/homebrew/bin/mvn -B clean verify` |
| 27 tests，0 failures/errors | ✅ | P2 本地验证与 P3 hotfix 本地验证均通过 |
| Checkstyle 0 / SpotBugs 0 / JaCoCo ≥ 0.60 | ✅ | P2 本地验证与 P3 hotfix 本地验证均通过 |

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
| `jenkins/verify` 门禁通过 | ✅ | build 15，`gateVerdict=GREEN`；tests 35/0/0；jacoco.line=83.83%；checkstyle=0；spotbugs=0 |
| commit status 已回写 | ✅ | context `jenkins/verify`，state `success`，SHA `28aca2cd6d7c57fd2968b2587d0ada8659d4a49b` |
| 门禁结论文档已提交 | ✅ | `.devflow/issue-2/05-gate/p5-ci-verdict.md` |

## P6 独立验收

| 检查项 | 结论 | 证据 / 备注 |
| --- | --- | --- |
| QA-Waker 独立验收结论 | ✅ PASS | `.devflow/issue-2/06-qa/acceptance-report.md`：14/14 验收标准通过 |
| issue #3 回归核验 | ✅ PASS | `bothFixesPreserved=true` 经 QA 独立复核成立 |
| 无返修项 / 无阻塞项 | ✅ | 残余风险已披露，不构成返修项 |

## qoderai 自动审查与 G1 基线对照

| qoderai 结论 | 与 G1 基线是否冲突 | 是否采纳 | 不采纳理由 / G2 裁定 |
| --- | --- | --- | --- |
| （待 P7 PR 创建后 qoderai 输出） | — | — | — |

**纪律**：
1. qoderai `reviewDecision` 为合并资格维度，`dismiss` 不可用；修完推送会触发重跑。
2. qoderai 意见若与 G1 基线冲突，以 G1 基线为准，并在 G2 现场由 Requirement Owner 裁定。
3. G2 批准绑定到具体 SHA；批准后推送新提交则批准失效。
4. P5 的 `jenkins/verify` 状态绑定在 SHA `28aca2c` 上；提交 P6/P7 产物后 HEAD 前移，需 DevOps-Waker 对最终 SHA 重跑门禁后再进 G2。

## 人工门禁 G2

| 检查项 | 结论 | 证据 |
| --- | --- | --- |
| Requirement Owner 在群内明确批准合并 | ⏳ | 待 Lead-Waker 主持 G2 |

## 合并资格结论

- 当前状态：P6 验收通过；P7 PR 已创建；待最终 SHA 的 `jenkins/verify`、qoderai `reviewDecision` 与 G2 人工批准
- 是否满足合并资格：⏳ 待 G2 与最终状态检查完成后核定
- 若不满足，阻塞项与解除路径见 `.devflow/issue-2/05-gate/merge-block-criteria.md`
