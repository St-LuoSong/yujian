-- ---------------------------------------------------------------------------
-- 豫见智旅 · MySQL 8 基线结构
-- ---------------------------------------------------------------------------
-- 这份脚本是"实体映射的完整快照"，由 Hibernate 6.5 按其 MySQLDialect 生成后
-- 整理而来，不是手抄的。之所以要生成而不是手写：UUID 在 MySQL 上是 binary(16)
-- 不是 char(36)，boolean 是 bit 不是 tinyint，Instant 是 datetime(6) —— 任何
-- 一处凭印象写错，都会让新库上的读写以"类型不匹配"的形式坏掉。
--
-- 为什么每一句都是 CREATE TABLE IF NOT EXISTS：
--   线上库是 Hibernate 的 ddl-auto=update 建的，表已经在那里。Flyway 用
--   baseline-on-migrate 接管它时，V1 必须对已有库是空操作、对新库是完整建表，
--   同一份脚本要同时满足这两种情况。索引、唯一约束、外键一律写在 CREATE TABLE
--   里面，因为 MySQL 没有 CREATE INDEX IF NOT EXISTS，拆出来会在已有库上直接报错。
--
-- 与 Hibernate 生成结果的两处刻意差异（见 V2，那里也修了已有库）：
--   app_release.release_notes、demo_scenario.payload_json、
--   prompt_version.system_prompt、trip_plan.previous_snapshot
--   这四个 @Lob 字段在 Hibernate 6.5 的 MySQL 方言下会被建成 tinytext（上限
--   255 字节），而它们装的是 APK 更新说明、演示场景 JSON、系统提示词和行程
--   快照 —— 都是必然写爆的内容。这里统一用 LONGTEXT。
-- ---------------------------------------------------------------------------

create table if not exists anonymous_session (
    planning_count          integer      not null,
    created_at              datetime(6)  not null,
    expires_at              datetime(6)  not null,
    last_seen_at            datetime(6)  not null,
    converted_user_id       binary(16),
    id                      binary(16)   not null,
    device_fingerprint_hash varchar(64),
    token_hash              varchar(64)  not null,
    primary key (id),
    constraint idx_anonymous_token_hash unique (token_hash)
) engine=InnoDB default charset=utf8mb4;

create table if not exists app_release (
    minimum_sdk                    integer      null,
    target_sdk                     integer      null,
    created_at                     datetime(6)  not null,
    file_size                      bigint       not null,
    minimum_supported_version_code bigint       not null,
    published_at                   datetime(6)  null,
    updated_at                     datetime(6)  not null,
    version_code                   bigint       not null,
    id                             binary(16)   not null,
    platform                       varchar(20)  not null,
    status                         varchar(20)  not null,
    update_mode                    varchar(20)  not null,
    file_sha256                    varchar(64)  not null,
    signing_certificate_sha256     varchar(64)  not null,
    version_name                   varchar(80)  not null,
    release_title                  varchar(120) not null,
    package_name                   varchar(160) not null,
    original_file_name             varchar(180) not null,
    storage_key                    varchar(180) not null,
    release_notes                  longtext     not null,
    primary key (id),
    constraint uk_app_release_package_version unique (package_name, version_code),
    constraint uk_app_release_storage_key unique (storage_key),
    index idx_app_release_platform_status (platform, status),
    index idx_app_release_version (package_name, version_code)
) engine=InnoDB default charset=utf8mb4;

create table if not exists user_account (
    email_verified bit          not null,
    created_at     datetime(6)  not null,
    updated_at     datetime(6)  not null,
    id             binary(16)   not null,
    avatar_key     varchar(32),
    nickname       varchar(40),
    username       varchar(64)  not null,
    password_hash  varchar(100) not null,
    email          varchar(160),
    primary key (id),
    constraint uk_user_account_username unique (username),
    constraint uk_user_account_email unique (email)
) engine=InnoDB default charset=utf8mb4;

create table if not exists user_role (
    user_id   binary(16)  not null,
    role_name varchar(32) not null,
    primary key (user_id, role_name)
) engine=InnoDB default charset=utf8mb4;

create table if not exists refresh_token (
    revoked          bit         not null,
    created_at       datetime(6) not null,
    expires_at       datetime(6) not null,
    revoked_at       datetime(6),
    id               binary(16)  not null,
    user_id          binary(16)  not null,
    replaced_by_hash varchar(64),
    token_hash       varchar(64) not null,
    primary key (id),
    constraint idx_refresh_token_hash unique (token_hash)
) engine=InnoDB default charset=utf8mb4;

create table if not exists email_verification (
    attempts           integer      not null,
    consumed_at        datetime(6),
    created_at         datetime(6)  not null,
    expires_at         datetime(6)  not null,
    id                 binary(16)   not null,
    purpose            varchar(32)  not null,
    code_hash          varchar(64)  not null,
    requester_key_hash varchar(64),
    email              varchar(160) not null,
    primary key (id),
    index idx_email_verification_lookup (email, purpose, created_at)
) engine=InnoDB default charset=utf8mb4;

create table if not exists poi (
    lat          double       null,
    lng          double       null,
    published    bit          not null,
    sort_order   integer      not null,
    ticket_from  integer      not null,
    created_at   datetime(6)  not null,
    updated_at   datetime(6)  not null,
    data_status  varchar(32)  not null,
    category     varchar(40)  not null,
    city         varchar(40)  not null,
    duration     varchar(40)  not null,
    id           varchar(64)  not null,
    name         varchar(80)  not null,
    suitability  varchar(120),
    image_credit varchar(200),
    source_url   varchar(300),
    weather_tip  varchar(300),
    description  varchar(500) not null,
    image_url    varchar(500),
    primary key (id),
    index idx_poi_published_sort (published, sort_order),
    index idx_poi_city (city)
) engine=InnoDB default charset=utf8mb4;

create table if not exists prompt_version (
    active        bit         not null,
    created_at    datetime(6) not null,
    id            binary(16)  not null,
    version       varchar(64) not null,
    note          varchar(200),
    system_prompt longtext    not null,
    primary key (id),
    constraint uk_prompt_version_version unique (version),
    index idx_prompt_version_active (active, created_at)
) engine=InnoDB default charset=utf8mb4;

create table if not exists trip_plan (
    budget_per_person    integer      null,
    days_count           integer      not null,
    per_person_cost      integer      not null,
    snapshot_version     integer      not null,
    tool_mock_count      integer      null,
    total_cost           integer      not null,
    travelers            integer      not null,
    created_at           datetime(6)  not null,
    updated_at           datetime(6)  not null,
    anonymous_session_id binary(16)   null,
    id                   binary(16)   not null,
    user_id              binary(16)   null,
    data_status          varchar(32)  not null,
    intensity            varchar(32)  not null,
    planning_engine      varchar(64),
    prompt_version       varchar(64),
    corridor             varchar(80)  not null,
    destination          varchar(80),
    origin               varchar(80),
    title                varchar(160) not null,
    summary              varchar(600) not null,
    prompt               varchar(1000) not null,
    previous_snapshot    longtext,
    primary key (id),
    index idx_trip_plan_owner (user_id, updated_at),
    index idx_trip_plan_anonymous (anonymous_session_id, updated_at)
) engine=InnoDB default charset=utf8mb4;

create table if not exists trip_plan_warning (
    trip_plan_id binary(16)  not null,
    warning_text varchar(500) not null
) engine=InnoDB default charset=utf8mb4;

create table if not exists trip_day (
    sort_order   integer     not null,
    id           binary(16)  not null,
    trip_plan_id binary(16)  not null,
    label        varchar(32) not null,
    date_label   varchar(64) not null,
    primary key (id),
    constraint fk_trip_day_plan foreign key (trip_plan_id) references trip_plan (id)
) engine=InnoDB default charset=utf8mb4;

create table if not exists trip_item (
    distance_meters    integer      null,
    duration_minutes   integer      null,
    estimated_cost     integer      not null,
    sort_order         integer      not null,
    updated_at         datetime(6)  not null,
    end_time           varchar(16),
    id                 binary(16)   not null,
    start_time         varchar(16),
    trip_day_id        binary(16)   not null,
    data_status        varchar(32)  not null,
    feasibility_status varchar(32)  not null,
    item_type          varchar(32)  not null,
    transport_mode     varchar(80),
    alternative_title  varchar(160),
    source             varchar(160),
    title              varchar(160) not null,
    description        varchar(600),
    risk_warnings      varchar(1000),
    primary key (id),
    constraint fk_trip_item_day foreign key (trip_day_id) references trip_day (id)
) engine=InnoDB default charset=utf8mb4;

create table if not exists trip_share (
    enabled      bit         not null,
    hide_budget  bit         not null,
    created_at   datetime(6) not null,
    expires_at   datetime(6),
    revoked_at   datetime(6),
    view_count   bigint      not null,
    id           binary(16)  not null,
    trip_plan_id binary(16)  not null,
    token_hash   varchar(64) not null,
    primary key (id),
    constraint idx_trip_share_token_hash unique (token_hash),
    constraint fk_trip_share_plan foreign key (trip_plan_id) references trip_plan (id)
) engine=InnoDB default charset=utf8mb4;

create table if not exists favorite (
    created_at datetime(6)  not null,
    id         binary(16)   not null,
    user_id    binary(16)   not null,
    city       varchar(64),
    poi_id     varchar(64)  not null,
    poi_name   varchar(160) not null,
    image_url  varchar(600),
    primary key (id),
    constraint uk_favorite_user_poi unique (user_id, poi_id),
    constraint fk_favorite_user foreign key (user_id) references user_account (id)
) engine=InnoDB default charset=utf8mb4;

create table if not exists feedback (
    created_at           datetime(6)  not null,
    updated_at           datetime(6)  not null,
    anonymous_session_id binary(16),
    id                   binary(16)   not null,
    user_id              binary(16),
    category             varchar(32)  not null,
    status               varchar(32)  not null,
    page                 varchar(120),
    contact              varchar(160),
    handler_note         varchar(500),
    content              varchar(1000) not null,
    primary key (id),
    index idx_feedback_status_created (status, created_at)
) engine=InnoDB default charset=utf8mb4;

create table if not exists operation_log (
    created_at datetime(6)  not null,
    actor_id   binary(16),
    id         binary(16)   not null,
    action     varchar(80)  not null,
    actor_name varchar(80),
    target     varchar(160) not null,
    detail     varchar(500),
    primary key (id),
    index idx_operation_log_created (created_at),
    index idx_operation_log_action (action)
) engine=InnoDB default charset=utf8mb4;

create table if not exists tool_invocation_log (
    success        bit          not null,
    created_at     datetime(6)  not null,
    duration_ms    bigint,
    correlation_id binary(16)   not null,
    id             binary(16)   not null,
    trip_plan_id   binary(16),
    data_status    varchar(32),
    error_code     varchar(80),
    tool_name      varchar(80)  not null,
    source         varchar(160),
    input_summary  varchar(500),
    output_summary varchar(1000),
    primary key (id),
    index idx_tool_invocation_trip (trip_plan_id, created_at),
    index idx_tool_invocation_correlation (correlation_id)
) engine=InnoDB default charset=utf8mb4;

create table if not exists demo_scenario (
    enabled      bit         not null,
    updated_at   datetime(6) not null,
    id           binary(16)  not null,
    scenario_key varchar(48) not null,
    match_key    varchar(120) not null,
    name         varchar(120) not null,
    note         varchar(300),
    payload_json longtext    not null,
    primary key (id),
    constraint uk_demo_scenario_key_match unique (scenario_key, match_key),
    index idx_demo_scenario_type (scenario_key, enabled)
) engine=InnoDB default charset=utf8mb4;

create table if not exists user_message (
    read_flag  bit          not null,
    created_at datetime(6)  not null,
    read_at    datetime(6),
    id         binary(16)   not null,
    user_id    binary(16)   not null,
    type       varchar(32)  not null,
    title      varchar(120) not null,
    body       varchar(1000) not null,
    primary key (id),
    index idx_user_message_user (user_id, created_at),
    index idx_user_message_unread (user_id, read_flag),
    constraint fk_user_message_user foreign key (user_id) references user_account (id)
) engine=InnoDB default charset=utf8mb4;

create table if not exists community_post (
    created_at     datetime(6)  not null,
    favorite_count bigint       not null,
    like_count     bigint       not null,
    published_at   datetime(6),
    reviewed_at    datetime(6),
    updated_at     datetime(6)  not null,
    view_count     bigint       not null,
    id             binary(16)   not null,
    trip_plan_id   binary(16),
    user_id        binary(16)   not null,
    visibility     varchar(16)  not null,
    status         varchar(20)  not null,
    city           varchar(80)  not null,
    title          varchar(80)  not null,
    tags           varchar(200),
    moderation_note varchar(500),
    content        varchar(3000) not null,
    primary key (id),
    index idx_community_post_status_created (status, created_at),
    index idx_community_post_city_status (city, status),
    index idx_community_post_user (user_id, created_at),
    constraint fk_community_post_user foreign key (user_id) references user_account (id),
    constraint fk_community_post_trip foreign key (trip_plan_id) references trip_plan (id)
) engine=InnoDB default charset=utf8mb4;

create table if not exists community_post_image (
    sort_order integer       not null,
    post_id    binary(16)    not null,
    image_url  varchar(1024) not null,
    primary key (sort_order, post_id),
    constraint fk_community_post_image_post foreign key (post_id) references community_post (id)
) engine=InnoDB default charset=utf8mb4;

create table if not exists community_like (
    created_at datetime(6) not null,
    id         binary(16)  not null,
    post_id    binary(16)  not null,
    user_id    binary(16)  not null,
    primary key (id),
    constraint uk_community_like_user_post unique (user_id, post_id),
    constraint fk_community_like_post foreign key (post_id) references community_post (id),
    constraint fk_community_like_user foreign key (user_id) references user_account (id)
) engine=InnoDB default charset=utf8mb4;

create table if not exists community_favorite (
    created_at datetime(6) not null,
    id         binary(16)  not null,
    post_id    binary(16)  not null,
    user_id    binary(16)  not null,
    primary key (id),
    constraint uk_community_favorite_user_post unique (user_id, post_id),
    constraint fk_community_favorite_post foreign key (post_id) references community_post (id),
    constraint fk_community_favorite_user foreign key (user_id) references user_account (id)
) engine=InnoDB default charset=utf8mb4;

create table if not exists community_report (
    created_at   datetime(6)  not null,
    handled_at   datetime(6),
    id           binary(16)   not null,
    post_id      binary(16)   not null,
    reporter_id  binary(16)   not null,
    status       varchar(20)  not null,
    handler_note varchar(500),
    reason       varchar(500) not null,
    primary key (id),
    constraint uk_community_report_user_post unique (reporter_id, post_id),
    constraint fk_community_report_post foreign key (post_id) references community_post (id),
    constraint fk_community_report_reporter foreign key (reporter_id) references user_account (id)
) engine=InnoDB default charset=utf8mb4;
