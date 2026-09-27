# Issue #2 合并门禁与 S6_MERGE_BLOCKED 判定口径

> Dev-Waker 执笔，随 P5/P7 进展更新。合并资格需同时满足 GitHub 规则集、GitHub Actions `mvn-verify` check run 与 qoderai 自动审查 `reviewDecision`。
>
> **CI 载体变更**：P5 已由本地 Jenkins `ai-devops-demo-verify` job 完成（build 15，GREEN），该结果仍有效；G2/P7 阶段以 GitHub Actions `mvn-verify` check run 为引用口径，`pr-status` 同时看 check state 与 qoderai `reviewDecision`。禁止手动 dispatch、禁止 dismiss review、禁止改动 `.github/workflows/`。

## 必需检查清单（全部通过才允许合并）

| 检查项 | 判定命令 / 位置 | 通过标准 |
| --- | --- | --- |
| P5 Jenkins 门禁（历史有效） | `~/jenkins-lab/jenkins-lab.sh build <branch>` | build 15 `gateVerdict=GREEN`；`tests.fail=0`；`jacoco.line ≥ 0.60`；`checkstyle.violations=0`；`spotbugs.bugs=0` |
| GitHub Actions 门禁（G2/P7 引用口径） | GitHub PR `mvn-verify` check run | `conclusion=success`；`status=completed` |
| Commit status / check state 核验 | `lab/scripts/github-lab.sh pr-status <pr_number>` | `mergeable=true`；`mergeStateStatus` 非 `BLOCKED`；`mvn-verify` check 为 `success` |
| qoderai 自动审查 | GitHub PR review 区 / `reviewDecision` | 不是 `CHANGES_REQUESTED` 或等效阻塞结论；建议性意见须在 `cr-checklist.md` 说明是否采纳 |
| 人工门禁 G2 | 群内 Requirement Owner 明确批准 | Owner 在群里明确回复「批准合并」或等效结论 |
| P4 冲突仲裁 | `.devflow/issue-2/04-merge/conflict-resolution.md` | #3 hotfix 与 #2 feature 的冲突已处理，两侧修复均已保留 |

## S6_MERGE_BLOCKED 触发条件

满足以下任一条件时，`state.json` 不得写 `DELIVERED`，必须进入 `S6_MERGE_BLOCKED`：

1. `mergeStateStatus=BLOCKED`（GitHub 规则集未满足，例如缺少 `mvn-verify` check、评审线程未解决、force push 历史等）。
2. GitHub Actions `mvn-verify` check run 未通过或未 completed（含 queued/in_progress 超时）。
3. qoderai `reviewDecision` 为阻塞性结论，且未在 G2 由 Requirement Owner 明确接受。
4. qoderai 意见与 G1 基线冲突，且未在 G2 完成裁定。
5. G2 人工批准尚未获得，或批准后又推送了新提交导致批准失效。
6. P4 冲突仲裁未完成，或仲裁记录未提交。
7. 有人工 dispatch GitHub Actions、dismiss qoderai review、或改动 `.github/workflows/` 等违规操作。

## 阻塞证据模板

```json
{
  "stage": "P7",
  "state": "S6_MERGE_BLOCKED",
  "blockedAtSha": "<当前 PR HEAD SHA>",
  "reasons": [
    {
      "source": "github-lab.sh pr-status",
      "detail": "<原始 JSON 输出或关键字段>",
      "mergeStateStatus": "BLOCKED",
      "missingChecks": ["mvn-verify"],
      "unresolvedReviewThreads": false
    },
    {
      "source": "GitHub Actions mvn-verify check run",
      "detail": "<check run 原始 JSON 或关键字段>",
      "status": "completed",
      "conclusion": "failure"
    },
    {
      "source": "qoderai reviewDecision",
      "detail": "<qoderai 结论及与 G1 基线的冲突点>",
      "conflictWithBaseline": false,
      "g2Ruling": "<若已裁定，记录裁定原话>"
    }
  ],
  "unblockPath": "<解除阻塞的具体动作与责任人>"
}
```

## qoderai 与 G1 基线冲突的处理

- **原则**：qoderai 自动审查的意见仅供参考；当它与 G1 已批准的需求基线（`change-breakdown.md`）冲突时，以 G1 基线为准。
- **操作**：在 `cr-checklist.md` 中单列一条「qoderai 意见 vs G1 基线对照表」，写清 qoderai 建议、G1 基线原文、是否采纳、不采纳的理由。
- **升级**：若 qoderai 给出阻塞性结论且 Dev-Waker 认为该结论与基线冲突，由 `Lead-Waker` 在 G2 人工门禁现场 @ Requirement Owner 裁定，不得由 Agent 自行忽略或绕过。

## 批准失效规则

- G2 批准绑定到具体 SHA。批准后若再往分支推送任何提交（包括 rebase、amend、空提交），原批准自动失效，必须：
  1. 等待 GitHub Actions `mvn-verify` check run 在新 HEAD 上完成且结论为 `success`；
  2. 等待 qoderai 对新 HEAD 给出审查结论；
  3. 重新获得 Requirement Owner 的 G2 批准。
- 禁止手动 dispatch `mvn-verify`、禁止 dismiss qoderai review、禁止改动 `.github/workflows/`。
