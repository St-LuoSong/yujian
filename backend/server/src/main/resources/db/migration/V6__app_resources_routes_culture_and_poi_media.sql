-- ---------------------------------------------------------------------------
-- V6：应用视觉资源、主题路线、文化锦囊、景区图集
-- ---------------------------------------------------------------------------
-- 这一版把"平台控制的图片与内容"从代码里搬到库里：首页横幅、个人页背景、
-- 行程默认封面、景区图集、占位图、示范路线、文化锦囊。
--
-- 为什么要这样分：
--   1. loading.png 是启动图，必须随 APK 打包，断网也要能显示，所以它**不**在这张表里；
--   2. 用户头像与旅记图片是用户上传、管理员审核的内容，也不在这里；
--   3. 剩下的平台素材由运营台维护，客户端只认接口，不认本地常量。
--
-- 旧版客户端继续读 /api/home 的 corridors / headline 字段，因此这一版只加
-- 不减：theme_route 里预置的三条路线与原来的硬编码走廊一一对应。
-- ---------------------------------------------------------------------------

-- ---------- 1. 景点补充字段 ----------

alter table poi
    add column opening_hours varchar(200) null after weather_tip;

alter table poi
    add column reservation_note varchar(300) null after opening_hours;

alter table poi
    add column home_featured bit not null default b'0' after reservation_note;

alter table poi
    add column featured_sort_order integer not null default 0 after home_featured;

-- 首页精选是"取少量并排序"的查询，补一条覆盖索引。
create index idx_poi_home_featured on poi (published, home_featured, featured_sort_order);

-- ---------- 2. 全局视觉资源槽 ----------

create table if not exists app_visual_resource (
    slot         varchar(40)  not null,
    image_url    varchar(600) null,
    image_credit varchar(200) null,
    source_url   varchar(300) null,
    enabled      bit          not null default b'1',
    updated_at   datetime(6)  not null,
    primary key (slot)
) engine=InnoDB default charset=utf8mb4;

-- ---------- 3. 主题路线 ----------

create table if not exists theme_route (
    id              varchar(64)  not null,
    title           varchar(120) not null,
    subtitle        varchar(200) not null,
    cities          varchar(120) null,
    duration        varchar(40)  null,
    budget          varchar(40)  null,
    cover_url       varchar(600) null,
    highlights      varchar(500) null,
    planning_prompt varchar(500) null,
    published       bit          not null default b'0',
    sort_order      integer      not null default 0,
    image_credit    varchar(200) null,
    source_url      varchar(300) null,
    updated_at      datetime(6)  not null,
    primary key (id),
    index idx_theme_route_published (published, sort_order)
) engine=InnoDB default charset=utf8mb4;

-- ---------- 4. 文化锦囊 ----------

create table if not exists culture_article (
    id           varchar(64)  not null,
    title        varchar(160) not null,
    summary      varchar(300) null,
    content      longtext     not null,
    category     varchar(40)  not null,
    cover_url    varchar(600) null,
    image_credit varchar(200) null,
    source_url   varchar(300) null,
    published    bit          not null default b'0',
    sort_order   integer      not null default 0,
    created_at   datetime(6)  not null,
    updated_at   datetime(6)  not null,
    primary key (id),
    index idx_culture_article_feed (published, category, sort_order, created_at)
) engine=InnoDB default charset=utf8mb4;

-- ---------- 5. 景区图集 ----------

create table if not exists poi_media (
    id           bigint       not null auto_increment,
    poi_id       varchar(64)  not null,
    image_url    varchar(600) not null,
    caption      varchar(200) null,
    image_credit varchar(200) null,
    source_url   varchar(300) null,
    sort_order   integer      not null default 0,
    published    bit          not null default b'1',
    primary key (id),
    index idx_poi_media_poi (poi_id, published, sort_order)
) engine=InnoDB default charset=utf8mb4;

-- ---------- 6. 预置三条示范走廊 ----------
-- 内容与原 TravelCatalog.corridors() 完全一致：迁移之后 /api/home 返回的
-- 还是同三条路线，运营台改哪条，客户端才跟着变。
-- 用 insert ignore 是为了对已经手工建过同名路线的库保持幂等。

insert ignore into theme_route
    (id, title, subtitle, cities, duration, budget, cover_url, highlights,
     planning_prompt, published, sort_order, image_credit, source_url, updated_at)
values
    ('zheng-kai', '郑州—开封', '古都烟火里的宋韵一日', '郑州 · 开封', '1—2天', '¥300起',
     'https://images.unsplash.com/photo-1518005020951-eccb494ad742?auto=format&fit=crop&w=1200&q=80',
     '古都文化,夜游美食,城市漫游',
     '从郑州出发，用一到两天逛开封，侧重古都文化、夜游与当地美食，节奏轻松。',
     b'1', 10,
     '占位示例图（Unsplash），非河南实景，待运营台替换为有授权照片',
     'https://unsplash.com', now(6)),
    ('zheng-luo', '郑州—洛阳', '沿着伊河读懂千年中原', '郑州 · 洛阳', '2—3天', '¥680起',
     'https://images.unsplash.com/photo-1548013146-72479768bada?auto=format&fit=crop&w=1200&q=80',
     '龙门石窟,博物馆,古都深度游',
     '从郑州出发，用两到三天游洛阳，侧重历史文化、石窟与博物馆，节奏适中。',
     b'1', 20,
     '占位示例图（Unsplash），非河南实景，待运营台替换为有授权照片',
     'https://unsplash.com', now(6)),
    ('jiao-yun', '焦作—云台山', '把山水留给周末的脚步', '焦作 · 云台山', '1—2天', '¥520起',
     'https://images.unsplash.com/photo-1500534623283-312aade485b7?auto=format&fit=crop&w=1200&q=80',
     '红石峡,自然风光,轻户外',
     '周末去云台山看山水，一到两天，侧重自然风光与轻户外，注意天气。',
     b'1', 30,
     '占位示例图（Unsplash），非河南实景，待运营台替换为有授权照片',
     'https://unsplash.com', now(6));
