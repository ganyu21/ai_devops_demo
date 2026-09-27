# P5 CI 门禁结论

## 构建信息

| 字段 | 值 |
| --- | --- |
| job | ai-devops-demo-verify |
| build 号 | 15 |
| 分支 | feature/issue-2-cache-ttl-and-visit-log |
| HEAD SHA | `28aca2cd6d7c57fd2968b2587d0ada8659d4a49b` |
| 触发时间 | 2026-09-27T11:05:52+08:00（本地时间） |
| 结果 | SUCCESS |
| gateVerdict | GREEN |

## jenkins-lab.sh 结构化输出

```json
{
  "build": 15,
  "result": "SUCCESS",
  "building": false,
  "durationSec": 25.1,
  "tests": null,
  "jacocoLine": null,
  "jacocoBranch": null,
  "failedTests": [],
  "consoleUrl": "http://127.0.0.1:8080/job/ai-devops-demo-verify/15/consoleText",
  "gateVerdict": "GREEN"
}
```

> 说明：`tests` 与 `jacocoLine` 字段在脚本顶层 verdict 中为 null 是已知行为；脚本通过 `failedTests` 与 console 中的 `=== GATE SUMMARY ===` 提供完整门禁数字。下文已摘录 GATE SUMMARY。

## GATE SUMMARY

```
=== GATE SUMMARY ===
branch=feature/issue-2-cache-ttl-and-visit-log
sha=28aca2cd6d7c57fd2968b2587d0ada8659d4a49b
result=SUCCESS
tests.total=35
tests.fail=0
tests.skip=0
jacoco.line=83.83234
jacoco.lineCovered=140
jacoco.lineTotal=167
jacoco.branch=75.00000
checkstyle.violations=0
spotbugs.bugs=0
gateVerdict=GREEN
```

## GitHub commit status 回写核验

- 命令：`lab/scripts/github-lab.sh commit-status 28aca2cd6d7c57fd2968b2587d0ada8659d4a49b`
- 结果：

```json
[
  {
    "context": "jenkins/verify",
    "created_at": "2026-09-27T11:06:19Z",
    "description": "mvn -B clean verify on feature/issue-2-cache-ttl-and-visit-log",
    "state": "success"
  }
]
```

回写成功，context `jenkins/verify` 状态为 `success`。

## 自愈轮次

本次 P5 无需代码自愈轮次。门禁一次通过。

## 工具修复记录

触发构建时发现 `~/jenkins-lab/jenkins-lab.sh` 的 `build` 与 `last` 子命令把 Jenkins 参数名写成了 `BRANCH`，而 Jenkinsfile 中定义的参数名为 `BRANCH_NAME`，导致首次构建（build 14）实际落到了 `main` 分支，回写状态也写到了 main 的 SHA。DevOps-Waker 已在本地修正该脚本参数名为 `BRANCH_NAME`，并重新触发 build 15，确认 feature 分支构建与状态回写均正确。该修定位为本地实验环境工具修复，未改动靶仓业务代码、未调低任何门禁阈值。

## 下一步

P5 门禁 GREEN，commit status 已回写成功。等待 QA-Waker 完成 P6 独立验收后进入 G2 人工门禁。
