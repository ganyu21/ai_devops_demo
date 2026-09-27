# Issue #3 线上缺陷分诊报告

## 复现结论

可稳定复现。

从 `main` 切出隔离工作树，运行复现测试 `Issue3MissingRefererReproducerTest`，不带 `Referer` 头的跳转请求会触发 `java.lang.NullPointerException`，表现为 HTTP 500。

## 缺陷位置

- **defectSite**: `src/main/java/com/lab/shortlink/visit/VisitLogService.java:22`
- **触发链路**: `ShortlinkController.redirect()` 第 75 行 -> `VisitLogService.record()` 第 22 行
- **根因**: `record(String code, String referer)` 方法直接调用 `referer.toLowerCase(Locale.ROOT)`，未处理 `referer` 为 `null` 的情况。`ShortlinkController` 第 69 行已将 `Referer` 头声明为 `required = false`，因此空值是合法输入。

## 严重级别

**严重（High / P1）**

依据：

1. 受影响的是**正常流量**，不是异常流量。浏览器在以下常见场景不会发送 `Referer`：
   - 用户从聊天工具直接粘贴/打开短链；
   - 源站配置 `Referrer-Policy: no-referrer`；
   - App 内置浏览器；
   - HTTPS 页面跳转到 HTTP 目标。
2. 触发条件与短码是否存在无关：任何已存在的短码，只要访问者不带 `Referer`，就会 500。
3. 500 的同时访问流水丢失（`VisitLogService.record()` 在落库前抛异常），运营统计会漏记。
4. 该路径在现有测试集中被刻意留空（`ShortlinkControllerTest` 注释明确说明不带 Referer 的路径归 #3 负责），因此 CI 门禁虽然全绿，却不能覆盖此缺陷。

## 真实堆栈

```
jakarta.servlet.ServletException: Request processing failed: java.lang.NullPointerException: Cannot invoke "String.toLowerCase(java.util.Locale)" because "referer" is null
	at org.springframework.web.servlet.FrameworkServlet.processRequest(FrameworkServlet.java:1022)
	at org.springframework.web.servlet.FrameworkServlet.doGet(FrameworkServlet.java:903)
	...
Caused by: java.lang.NullPointerException: Cannot invoke "String.toLowerCase(java.util.Locale)" because "referer" is null
	at com.lab.shortlink.visit.VisitLogService.record(VisitLogService.java:22)
	at com.lab.shortlink.api.ShortlinkController.redirect(ShortlinkController.java:75)
	...
```

完整堆栈与测试输出见 `target/surefire-reports/com.lab.shortlink.api.Issue3MissingRefererReproducerTest.txt`。

## 复现测试

- **文件**: `src/test/java/com/lab/shortlink/api/Issue3MissingRefererReproducerTest.java`
- **绝对路径**: `/Users/ganyu/.qoderwake/data/cloud-conversations/conv_01m3f5pwhsfrehh2375v2y5cw7/workers/0c0cfcd913ac/ai_devops_demo_main/src/test/java/com/lab/shortlink/api/Issue3MissingRefererReproducerTest.java`
- **状态**: untracked，保留在工作区，供下一阶段 `git add` 升格为回归测试。
- **运行方式**: `export JAVA_HOME=/opt/homebrew/opt/openjdk@21 && /opt/homebrew/bin/mvn -B test -Dtest=Issue3MissingRefererReproducerTest`

## 修复建议（供 P4 参考，P3 不改业务代码）

在 `VisitLogService.record()` 中对 `referer` 做空值保护，例如把空 `Referer` 视为合法值（如保留为 `null` 或替换为某个占位串），并确保访问流水仍能落库。注意：需求单 #2 的非目标明确要求「不修缺失 Referer 时的 500，必须逐字保持 `VisitLogService.record()` 现有行为」，因此该修复只能在缺陷 hotfix 分支进行，不能混入 #2 的 feature 分支。

## 与 #2 的冲突预期

#2 的需求侧要把 `VisitLogService.record()` 从内存 `List` 改成落库（方法体与字段重写），缺陷侧要在**旧内存版** `record()` 里加空值保护。同一文件同一方法必然产生真实冲突。仲裁时必须两侧修复都保留，不能整文件取一边。

## P5/P7 合并门禁口径（qoderai 自动审查）

流程已更新：P7 合并资格新增 `qoderai` 自动审查的 `reviewDecision` 维度，`dismiss` 不可用；修复后推送会触发 qoderai 重跑。

对本缺陷热修的影响：

1. **qoderai 意见若与 G1 基线冲突，以 G1 基线为准**，并在 `cr-checklist.md` 与 G2 现场明确列出冲突点及裁定依据。
2. 若 qoderai 给出 `CHANGES_REQUESTED` 级别的审查结论，即使 Jenkins 门禁通过、GitHub 规则集状态检查通过，PR 仍视为**未满足合并资格**，DevOps-Waker 不得执行合并；须由 `Lead-Waker` 在 G2 人工门禁现场裁定是否按基线接受、要求 Dev-Waker 返修，或明确记录为可接受的例外。
3. 因 qoderai 重跑由推送触发，任何批准后再推送的提交都会让已有 `reviewDecision` 失效，PR 回到待审查态；G2 批准必须落在**当前最新 SHA** 上。
4. 若 qoderai 审查与 GitHub 规则集共同导致 `mergeStateStatus=BLOCKED`，`state.json` 应进入 `S6_MERGE_BLOCKED`，并附：
   - `github-lab.sh pr-status` 原始输出；
   - qoderai `reviewDecision` 状态；
   - 具体阻塞项（缺失 `jenkins/verify` / qoderai 未通过 / 评审线程未解决 / 规则集硬性要求等）；
   - 解除路径（例如由 Requirement Owner 在 G2 裁定、补充 qoderai 所需上下文、或等待 qoderai 重跑完成）。

Dev-Waker 在编制 `cr-checklist.md` 时，须把 qoderai 审查结果作为独立检查项列入，并说明其与 G1 基线的对照结论。

## 分诊人

DevOps-Waker
