-- ---------------------------------------------------------------------------
-- V3：旅记评论、自定义头像、APK 发布通道
-- ---------------------------------------------------------------------------
-- 三块互不相关的功能放在一版里，是因为它们同一次上线：分开只会多几次
-- "部署到一半"的窗口，而这三张表之间没有先后依赖。
--
-- 关于 app_release 上的三处 drop/add：
--   原来唯一约束是 (package_name, version_code)，加上 channel 之后必须改成
--   (package_name, channel, version_code)，否则同一个 versionCode 没法同时
--   存在于正式与调试两条通道上。
--   线上库的这几个索引是 Hibernate 按实体注解建出来的，名字确定；但为了不把
--   启动成败押在"它一定建过"这个假设上，这里一律先查 information_schema 再决定
--   要不要 drop —— MySQL 没有 DROP INDEX IF EXISTS。
-- ---------------------------------------------------------------------------

-- ---------- 1. 自定义头像 ----------

alter table user_account
    add column avatar_url varchar(600) null after avatar_key;

-- ---------- 2. 旅记评论 ----------

alter table community_post
    add column comment_count bigint not null default 0 after favorite_count;

create table if not exists community_comment (
    id         binary(16)   not null,
    post_id    binary(16)   not null,
    user_id    binary(16)   not null,
    content    varchar(500) not null,
    status     varchar(20)  not null default 'ACTIVE',
    created_at datetime(6)  not null,
    updated_at datetime(6)  not null,
    primary key (id),
    index idx_community_comment_post (post_id, status, created_at),
    index idx_community_comment_user (user_id, created_at),
    constraint fk_community_comment_post foreign key (post_id) references community_post (id),
    constraint fk_community_comment_user foreign key (user_id) references user_account (id)
) engine=InnoDB default charset=utf8mb4;

-- ---------- 3. APK 发布通道 ----------

set @drop_package_version := (select if(
    exists(select 1 from information_schema.statistics
           where table_schema = database() and table_name = 'app_release'
             and index_name = 'uk_app_release_package_version'),
    'alter table app_release drop index uk_app_release_package_version',
    'select 1'));
prepare stmt from @drop_package_version;
execute stmt;
deallocate prepare stmt;

set @drop_platform_status := (select if(
    exists(select 1 from information_schema.statistics
           where table_schema = database() and table_name = 'app_release'
             and index_name = 'idx_app_release_platform_status'),
    'alter table app_release drop index idx_app_release_platform_status',
    'select 1'));
prepare stmt from @drop_platform_status;
execute stmt;
deallocate prepare stmt;

set @drop_version_index := (select if(
    exists(select 1 from information_schema.statistics
           where table_schema = database() and table_name = 'app_release'
             and index_name = 'idx_app_release_version'),
    'alter table app_release drop index idx_app_release_version',
    'select 1'));
prepare stmt from @drop_version_index;
execute stmt;
deallocate prepare stmt;

alter table app_release
    add column channel varchar(16) not null default 'RELEASE' after platform;

alter table app_release
    add constraint uk_app_release_channel_version unique (package_name, channel, version_code);

create index idx_app_release_platform_status on app_release (platform, channel, status);
create index idx_app_release_version on app_release (package_name, channel, version_code);
