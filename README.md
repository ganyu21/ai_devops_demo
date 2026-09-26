# ai_devops_demo

DevOps 全流程演练靶仓。业务是一个**短链接服务**：把长网址变成短网址，访问短网址时 302 跳回原地址。

选这个题材是因为它不需要任何前置领域知识 —— 一句话就能讲完业务，参与者可以把注意力全部放在流程、门禁、仲裁与治理上，而不是花在理解对象存储或支付清算上。

## 技术栈

Java 17 / Spring Boot 3.2.4 / Maven，H2 存数据，Flyway 管 schema。

## 本地构建

```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@21
/opt/homebrew/bin/mvn -B clean verify
```

`JAVA_HOME` 必须显式指定。`mvn` 默认会挑到机器上最新的 JDK，而 `pom.xml` 锁的是 Java 17 —— 不钉死就会本地与 CI 跑出两套结果，排查问题的人会去追一个只存在于一侧的幽灵失败。

## 启动

```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@21
$JAVA_HOME/bin/java -jar target/shortlink-service-1.0.0.jar
# 监听 8081
curl -X POST http://localhost:8081/api/links \
  -H 'Content-Type: application/json' \
  -d '{"targetUrl":"https://example.com/a/very/long/path"}'
curl -i http://localhost:8081/<返回的 code>
```

## 门禁

`mvn -B clean verify` 一次跑完五道检查，任何一道不过就是红灯：

| 检查 | 配置在哪 | 阈值 |
| --- | --- | --- |
| 单元与集成测试 | `src/test/java` | 0 失败 0 错误 |
| 行覆盖率 | `pom.xml` 的 `coverage.line.minimum` | **绝对阈值 ≥ 60%** |
| Checkstyle | `config/checkstyle/checkstyle.xml` | 0 违规 |
| SpotBugs | `pom.xml`（`effort=Max` / `threshold=Low`） | 0 bug |
| schema 迁移 | `src/main/resources/db/migration` | 在内存库上真的跑一遍，跑不通即红 |

覆盖率是**绝对阈值**，不是「不低于上一次」的相对阈值 —— 相对阈值在机器层面没有实现，它只是对人的纪律要求（不许降阈值）。所以新增未测代码确实会稀释覆盖率，但门禁不会因为「比上次低」而翻红。

**阈值与规则只能由人改。** 为了让构建变绿而调低阈值、关掉插件、加 `-DskipTests` / `-Dcheckstyle.skip`、或者给 SpotBugs 加排除过滤器，都属于绕过门禁，不是修复问题。

## 三条只读边界

1. **对外契约**：`src/main/resources/api/openapi.yaml` 里已发布的两个路径（`POST /api/links`、`GET /{code}`）自需求基线冻结后只读。改动只允许纯新增 —— 新增路径、新增可选字段、新增响应码。`OpenApiContractTest` 会机械地检查既有定义还在、形状没变。
2. **已合入的迁移脚本**：`V1__*.sql` 一个字段都不许改。schema 变更只能新增 `V2__*.sql`；要回滚也是新增反向脚本，因为已经跑过 V1 的环境不会重新执行它。
3. **短码策略**：8 位 base62，至少 47 bit 熵。短码出现在公开 URL 里，能被枚举就等于能遍历别人的链接。这条约束由 `ShortCodeGenerator` 的 javadoc、`ShortCodeGeneratorTest` 的策略断言、需求单的「约束」节三处共同固定。

## 变更怎么进来

`main` 上有分支规则集：

- 所有变更必须走 Pull Request，**不能直推**；
- 管理员也不得绕过（`bypass_actors` 为空）；
- 禁止 force push 与分支删除；
- 评审线程必须解决之后才能合并。

CI 由 Jenkins 跑，结论通过 commit status 回写到 GitHub（context `jenkins/verify`），见 `Jenkinsfile`。凭据只存在 Jenkins 的 credential store 里，参与流程的自动化角色看不到它。

## 目录

```
src/main/java/com/lab/shortlink/
  api/       对外接口：创建短链、302 跳转
  code/      短码生成（不可协商的安全约束在这里）
  link/      链接存储
  resolve/   解析与解析缓存
  visit/     访问流水
  config/    配置项
src/main/resources/
  api/openapi.yaml            冻结的对外契约
  db/migration/V1__*.sql      已合入即只读的迁移脚本
config/checkstyle/            静态检查基线
Jenkinsfile                   CI 门禁 + GitHub 状态回写桥
docs/                         培训大纲、实验手册、操作手册
```
