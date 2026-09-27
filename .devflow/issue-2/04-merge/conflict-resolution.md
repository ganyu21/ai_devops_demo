# P4 冲突仲裁报告：合并 hotfix/issue-3-missing-referer

## 合并概要

| 项目 | 值 |
| --- | --- |
| 目标分支 | `feature/issue-2-cache-ttl-and-visit-log` |
| 合并来源 | `origin/hotfix/issue-3-missing-referer` |
| feature 分支基准提交 | `46498c1a6d6b0ca0cf634cd094f8e6c7f443bb8d` |
| hotfix 分支提交 | `46b344f98f45769ca1365c8a079f3c1d046eeac3` |
| 合并提交 | `671cca8` |
| 仲裁时间 | 2026-09-27T11:00:22Z |

## 分支名映射

Lead-Waker 在 issue/PR 上下文中引用的是 `hotfix/issue-3-referer-null`；
仓库中实际的分支名为 `hotfix/issue-3-missing-referer`。

- `hotfix/issue-3-referer-null`（参考命名） → `hotfix/issue-3-missing-referer`（实际分支名）

## 冲突文件与处理方式

| 文件 | 冲突情况 | 处理结论 |
| --- | --- | --- |
| `src/main/java/com/lab/shortlink/visit/VisitLogService.java` | 文本冲突 | 保留 feature 分支的 DB 持久化实现，注入 issue #3 的 null-referer 保护；删除 hotfix 分支的内存 `List` 实现。详见下文 `bothFixesPreserved`。 |

未出现其他 Git 文本冲突。`src/test/java/com/lab/shortlink/api/Issue3MissingRefererReproducerTest.java` 由 hotfix 分支作为新增文件带入，未触发冲突。

## bothFixesPreserved 裁定

针对 `VisitLogService` 的合并结果同时保住了两侧修复：

1. **issue #2 的 DB 持久化逻辑保留完整**
   - 保留 `JdbcTemplate` 字段与构造方式。
   - 保留 `recordAsync(String, String)` 异步写入与线程池关闭逻辑。
   - 保留 `findRecentByCode(String, int)` 数据库查询能力。
   - 保留 `size()` 数据库计数。
   - 未回退到 hotfix 分支的进程内 `ArrayList` 实现。

2. **issue #3 的 null-referer 保护已加入**
   - `record(String, String)` 中：`String normalized = referer == null ? null : referer.toLowerCase(Locale.ROOT);`
   - 当请求缺少 `Referer` 头时，数据库中写入 `null` 而非抛出 `NullPointerException`。
   - 小写归一化仍使用 `Locale.ROOT`，与 hotfix 行为一致。

3. **为兼容 hotfix 分支引入的回归测试，新增 `snapshot()` 方法**
   - `snapshot()` 从 `visit_log` 表读取全部记录快照，语义与 hotfix 的内存快照等价，但底层仍为 DB 查询。

裁定结果：**`bothFixesPreserved = true`**

## 构建验证

执行命令：

```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@21
/opt/homebrew/bin/mvn -B clean verify
```

结果：**BUILD SUCCESS**

- 测试：35 个运行，0 失败，0 错误，0 跳过
- JaCoCo 行覆盖率：通过
- Checkstyle：0 违规
- SpotBugs：0 bug
- Flyway schema gate：2 条迁移成功应用

## 合并后状态

- `currentPhase`：`P4_MERGE_RESOLVED`
- `nextAction`：进入 P5 CI 门禁与独立验收
