# T46：收藏总站、图片单张重试、Flyway 数据库迁移

日期：2026-10-03（Asia/Shanghai）

本轮三件事：把「我的收藏」从一列静态文字改成能点进去的收藏总站；让社区发布页
的上传失败可以单张重试；把 MySQL 的结构交给 Flyway 版本化管理。

## 一、收藏总站（`flutter_app/lib/screens/profile_screens.dart`）

### 改之前

`FavoritesScreen` 只有一个 `favoritesProvider`，把景区收藏竖着排成一列
`_FavoriteRow`：一个星标 + 名称 + 城市 + 一个 ×。整行**没有任何点击行为**，
另外两类收藏（旅记、行程）根本没有入口。

### 改之后

```text
我的收藏
├── 分段控件：景区 / 旅记 / 行程（等宽胶囊，选中态浮起白底，220ms 过渡）
└── AnimatedSwitcher：淡入 + 4% 横移，切换时不闪白
    ├── 景区：卡片（缩略图 + 名称 + 城市 + 查看详情 + 取消收藏）→ DestinationDetail
    ├── 旅记：复用 CommunityFavoritesList（社区页右上角入口用的是同一份实现）
    └── 行程：已保存行程卡片（走廊 / 天数 / 强度 / 预算）→ TripScreen
```

三个设计决定：

1. **行程不做"再收藏一次"。** 用户自己创建并保存的行程本身就是他要留下的东西，
   再叠一层 `trip_favorite` 只会让"取消收藏"和"删除行程"变成两件互相打架的事。
   所以第三块直接读 `GET /api/trip-plans`。
2. **不用 `SegmentedButton`。** 那个控件在 360dp + 1.3 倍字号下会把三个中文标签
   挤成省略号。手写胶囊段每段等宽、文本 `Flexible` + 省略，字号放大也只在极端
   情况才收敛。
3. **收藏里只存了 `poiId`。** 要打开景点详情就必须还原成完整的 `Destination`，
   新增 `_scenicCatalogProvider` 读同一份景点库（在线 + 本地缓存 + 演示兜底），
   不引入第二条内容来源。目录没到、或者这个景点已经下架时，如实提示
   「这个景点当前未上架」，而不是拿收藏记录里那点字段拼一个假详情页。

### 边界情况

| 情况 | 行为 |
| --- | --- |
| 未登录 | 三个板块统一显示一张「登录后查看收藏」+ 去登录，不摆三个空列表 |
| 收藏为空 | 每个板块各自的空态说明，不共用一句泛泛的文案 |
| 目录拉取失败 | 卡片照常显示（用收藏时存下的图片地址），点击时给失败原因 |
| 行程列表来自缓存 | 顶部一条「当前显示本地缓存」提示，仍是可点开的 |
| 连点两下行程 | `_openingId` 挡住第二次 push，避免返回时要按两次 |

## 二、社区图片上传单张重试（`community_publish_screen.dart`）

### 根因

旧实现在失败分支里只把**文件名**记进 `List<String> failed`，`XFile` 随循环结束
就丢了。用户除了重新翻一遍相册"重选全部"，没有别的办法。

### 修复

新增 `_FailedUpload { XFile file; String message; bool retrying; }`，失败的图片
连同原文件一起留在编辑页：

| 位置 | 说明 |
| --- | --- |
| 失败计数 | 失败的图片**也算占名额**，否则用户可以连着挑 9 张再挑 9 张，摆出一屏 18 张 |
| 失败缩略图 | 用本地文件预览（这一张从没上传成功过，服务器上没有它），压一层暗红 + 红框 |
| 重试按钮 | 图片内的一条白色胶囊，只重传这一张；重传中显示小圈 |
| 移除按钮 | 右上角圆形 ×，放弃这一张，不再占名额 |
| 汇总提示 | 「有 N 张没有传上去。点图片上的「重试」只重传那一张，已经成功的不会重来一遍。」 |

`_retryUpload` 与 `_uploading` 互斥：批量上传进行中时单张重试按钮不响应，
避免两条流程同时改 `_imageUrls`。

## 三、Flyway（`backend/server`）

### 为什么

`ddl-auto: update` 已经出过一次线上事故：`prompt_version.system_prompt` 被
Hibernate 6.5 的 MySQL 方言建成 `tinytext`（255 字节），长提示词一写就 500，
当时是在服务器上手工 `alter` 救回来的。

### baseline 是生成出来的，不是手抄的

用一个临时测试（`SpringApplicationBuilder` + `MySQLDialect` +
`jakarta.persistence.schema-generation.scripts.action=create`）让 Hibernate 自己
吐出 `target/schema-mysql.sql`，再整理成 `V1__baseline_schema.sql`。

这不是洁癖：UUID 在 MySQL 上是 `binary(16)` 而不是 `char(36)`，`boolean` 是
`bit` 而不是 `tinyint`，`Instant` 是 `datetime(6)`，`Double` 是 `float(53)` ——
21 张表里任何一列凭印象写错，新库上都会以"类型不匹配"的形式坏掉。

同一个动作还顺手暴露了另外三处同类隐患（见 V2）。

### 迁移脚本

| 脚本 | 作用 |
| --- | --- |
| `V1__baseline_schema.sql` | 完整结构。每句都是 `CREATE TABLE IF NOT EXISTS`，索引/唯一约束/外键全部写在 `CREATE TABLE` 里面 |
| `V2__lob_columns_to_longtext.sql` | 把四个被建成 `tinytext` 的 `@Lob` 列改成 `LONGTEXT` |

**为什么索引不能写在外面**：MySQL 没有 `CREATE INDEX IF NOT EXISTS`。V1 要同时
满足"新库完整建表"和"已有库完全空操作"，拆出来的 `CREATE INDEX` 会在已有库上
直接报错。

**为什么 V2 的 `ALTER` 是安全的**：V1 先跑，所有表在那之后一定存在。

### 生效范围

| Profile | 数据库 | Flyway | ddl-auto |
| --- | --- | --- | --- |
| dev（默认） | H2 文件库 | `enabled: false` | `update` |
| prod | MySQL 8 | `enabled: true` | `none`（可用 `SPRING_JPA_HIBERNATE_DDL_AUTO` 覆盖） |

dev 关掉 Flyway 是刻意的：MySQL 方言的脚本跑 H2 只会多出一个随时会跟实体漂移的
第二事实来源。

### 接管已有库

```yaml
baseline-on-migrate: true
baseline-version: 0
```

线上库是 `ddl-auto=update` 建起来的，里面已经有用户、行程和运营台加的景点。
Flyway 见到"非空但没有版本表"的库时，在版本 0 打一条基线记录，然后正常跑
V1、V2 —— V1 对已有库是空操作，V2 是必要的列类型修复。**不会删表、不会清数据。**

### 还没做的事

`ddl-auto` 目前是 `none` 而不是 `validate`。现有库是 Hibernate 一列一列攒出来的，
在真机上验证过 V1 与实体完全一致之前，`validate` 有可能让服务在启动阶段直接拒绝
起来 —— 那会把一次部署变成一次线上事故。要收紧时：先在一个空的 MySQL 上跑一遍
V1，确认不报错，再设置 `SPRING_JPA_HIBERNATE_DDL_AUTO=validate`。

首次真实迁移之后，补充两点现场观察：

- V1 的 24 条 `CREATE TABLE IF NOT EXISTS` 在已有库上全部走的是 "Table already
  exists (1050)" 这条警告路径，Flyway 把它当 INFO/WARN 处理，**迁移仍然记为成功**。
  这正是"同一份脚本要同时满足空库与已有库"想要的形状。
- V2 的四个 `ALTER` 都在零点几秒内完成（四张表都只有个位数行），没有锁等待。

## 四、验证

| 项目 | 结果 |
| --- | --- |
| `flutter analyze` | 0 issue |
| `flutter test` | 161 项全通过（新增 2 项收藏总站回归测试） |
| `mvn -o -B test` | 121 项全通过，BUILD SUCCESS |
| `flutter build apk --debug` | `build/app/outputs/flutter-apk/app-debug.apk` |
| MySQL 8.4 上的 Flyway 实跑 | 已在真实 MySQL 8.4 实例上验证，见下 |

### MySQL 8.4 首次实跑结果（2026-10-03 21:16 CST）

```text
Database: jdbc:mysql://mysql:3306/yujian_travel (MySQL 8.4)
Schema history table `yujian_travel`.`flyway_schema_history` does not exist yet
Successfully validated 2 migrations
Creating Schema History table `yujian_travel`.`flyway_schema_history` with baseline ...
Successfully baselined schema with version: 0
Migrating schema `yujian_travel` to version "1 - baseline schema"
  （24 条 Table already exists，均为预期）
Migrating schema `yujian_travel` to version "2 - lob columns to longtext"
Successfully applied 2 migrations to schema `yujian_travel`, now at version v2
Started YujianTravelApplication in 10.888 seconds
```

迁移前后数据核对（`select count(*)`）：

| 表 | 迁移前 | 迁移后 |
| --- | --- | --- |
| `user_account` | 3 | 3 |
| `trip_plan` | 3 | 3 |
| `poi` | 30 | 30 |
| `community_post` | 1 | 1 |
| `favorite` | 1 | 1 |
| `prompt_version` | 1 | 1 |

四个 `@Lob` 列的 `data_type` 已全部变为 `longtext`；
`flyway_schema_history` 中 0 / 1 / 2 三条记录的 `success` 均为 1。

### 升级已有库的注意事项

迁移是在一个**已经由 `ddl-auto=update` 建好表的 MySQL 8.4** 上跑的，这也正是
baseline 机制要覆盖的场景。两个容易踩的点：

1. 升级前先备份（`mysqldump`），迁移虽然不删数据，但 `ALTER` 是不可逆的。
2. 永远不要为了"清干净"执行 `docker compose down -v` 或删除数据卷 ——
   MySQL 与上传文件都在里面。

部署步骤见仓库根目录 `README.md` 的「容器部署」一节。

## 五、后续

1. 找一个空 MySQL 跑一遍 V1，确认新库也能一次建成，然后把 `ddl-auto` 收紧到
   `validate`。
2. 加一条"实体 vs V1"的漂移检查测试（本轮已验证该机制可行，但没有留下来，
   因为它需要启动完整 Spring 上下文，会显著拖慢现有 121 项单测）。
