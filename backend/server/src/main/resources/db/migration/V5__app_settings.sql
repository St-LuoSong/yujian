-- ---------------------------------------------------------------------------
-- V5：运行时可改的系统设置
-- ---------------------------------------------------------------------------
-- 只放"运营需要在不停机的情况下调整、而且调错了会立刻有体感"的那几个开关，
-- 不做通用配置中心：多一张能塞任意键值的表，就会有人把业务数据也塞进来。
--
-- 目前承载两类：
--   1. 接口限流（rate.*）—— 每个桶的窗口与额度；
--   2. 外部工具每日配额（quota.*）—— 保护百度 / 12306 / 天气的调用额度。
--
-- 值一律存字符串，由 AppSettingService 按登记的默认值类型解析与校验；
-- 没有登记的键一律拒绝写入，避免这张表变成谁都能改的配置垃圾场。
-- ---------------------------------------------------------------------------

create table if not exists app_setting (
    setting_key   varchar(120) not null,
    setting_value varchar(500) not null,
    updated_at    datetime(6)  not null,
    primary key (setting_key)
) engine=InnoDB default charset=utf8mb4;

-- 工具配额按"某天某个工具调了多少次"统计，走的是已有的调用日志表。
-- 现有索引是 (trip_plan_id, created_at) 与 (correlation_id)，都不适合这个查询，
-- 补一条 (tool_name, created_at)。
create index idx_tool_invocation_quota on tool_invocation_log (tool_name, created_at);
