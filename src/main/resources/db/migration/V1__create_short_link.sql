-- V1：短链本体表。
--
-- 本脚本已合入 main，自此对下游只读：一个字段都不许改、不许重命名、不许删除。
-- 后续 schema 变更只能新增 V2__*.sql（以及 V3、V4……），不得回头修改本文件。
-- 需要回滚某个变更时，也是新增一个反向脚本，而不是编辑历史脚本 ——
-- 已经跑过 V1 的环境不会重新执行它，改历史脚本只会造成环境之间的 schema 分歧。
CREATE TABLE short_link (
    code       VARCHAR(16)  NOT NULL,
    target_url VARCHAR(2048) NOT NULL,
    created_at TIMESTAMP    NOT NULL,
    CONSTRAINT pk_short_link PRIMARY KEY (code)
);
