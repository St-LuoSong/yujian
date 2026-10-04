-- ---------------------------------------------------------------------------
-- 把四个被 Hibernate 建成 tinytext 的 @Lob 列改成 LONGTEXT
-- ---------------------------------------------------------------------------
-- 背景：Hibernate 6.5 的 MySQLDialect 把 `@Lob String` 映射成 tinytext（255 字节）。
-- prompt_version.system_prompt 已经因此炸过一次 —— 写长提示词直接 500，当时是
-- 在服务器上手工 alter 才救回来的。同一个坑上还站着另外三列：
--
--   app_release.release_notes    APK 更新说明，一屏中文就超过 255 字节
--   demo_scenario.payload_json   演示场景 JSON，必然超过 255 字节
--   trip_plan.previous_snapshot  整份行程快照，用于「撤销上一次调整」
--
-- 这四条在线上库里已经是 tinytext/text，改类型不会丢数据（VARCHAR/TEXT 系列之间
-- 的 MODIFY 是长度放宽，不重建数据）。V1 里新库直接建成 LONGTEXT，所以这一版对
-- 新库是新旧一致的重复动作，对老库是必要的修复。
--
-- 想重新跑一遍时不用担心幂等性：Flyway 每个版本只执行一次。
-- ---------------------------------------------------------------------------

alter table prompt_version
    modify column system_prompt longtext not null;

alter table app_release
    modify column release_notes longtext not null;

alter table demo_scenario
    modify column payload_json longtext not null;

alter table trip_plan
    modify column previous_snapshot longtext null;
