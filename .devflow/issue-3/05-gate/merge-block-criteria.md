# Issue #3 合并门禁与 S6_MERGE_BLOCKED 判定口径

> DevOps-Waker 执笔，随 P5/P7 进展更新。合并资格需同时满足 GitHub 规则集、`jenkins/verify` commit status 与 qoderai 自动审查 `reviewDecision`。

## 必需检查清单（全部通过才允许合并）

| 检查项 | 判定命令 / 位置 | 通过标准 |
| --- | --- | --- |
| Jenkins 门禁 | `~/jenkins-lab/jenkins-lab.sh build <branch>` | `gateVerdict=PASS`；`tests.fail=0`；`jacoco.line ≥ 0.60`；`checkstyle.violations=0`；`spotbugs.bugs=0` |
| Commit status 回写 | `lab/scripts/github-lab.sh commit-status <sha>` | 存在 `context=jenkins/verify` 且 `state=success` |
| GitHub PR 资格 | `lab/scripts/github-lab.sh pr-status <pr_number>` | `mergeable=true`；`mergeStateStatus` 为 `CLEAN`/`HAS_HOOKS`/`UNSTABLE` 等可合并态，非 `BLOCKED` |
| qoderai 自动审查 | GitHub PR review 区 / `reviewDecision` | 不是 `CHANGES_REQUESTED` 或等效阻塞结论；若给出建议性意见，须在 `cr-checklist.md` 中说明是否采纳 |
| 人工门禁 G2 | 群内 Requirement Owner 明确批准 | Owner 在群里明确回复「批准合并」或等效结论 |

## S6_MERGE_BLOCKED 触发条件

满足以下任一条件时，`state.json` 不得写 `DELIVERED`，必须进入 `S6_MERGE_BLOCKED`：

1. `mergeStateStatus=BLOCKED`（GitHub 规则集未满足，例如缺少 `jenkins/verify`、评审线程未解决、force push 历史等）。
2. `jenkins/verify` commit status 未回写成功或未通过。
3. qoderai `reviewDecision` 为阻塞性结论，且未在 G2 由 Requirement Owner 明确接受。
4. qoderai 意见与 G1 基线冲突，且未在 G2 完成裁定。
5. G2 人工批准尚未获得，或批准后又推送了新提交导致批准失效。

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
      "missingContexts": ["jenkins/verify"],
      "unresolvedReviewThreads": false
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
  1. 重新触发 Jenkins 门禁；
  2. 等待 qoderai 对新 HEAD 给出审查结论；
  3. 重新获得 Requirement Owner 的 G2 批准。
