# 豫见智旅

面向河南自由行游客的 AI 旅行规划与智慧出行平台。

## 工程结构

- `flutter_app/`：Flutter Android APK 游客端
- `backend/server/`：Spring Boot API 服务
- `backend/admin/`：Vue 3 + Vite 管理台
- `tooling/`：本机 Flutter / Android SDK 与构建缓存（忽略，不提交）
- `docs/DELIVERY/`：比赛交付材料（索引见 [`docs/DELIVERY/README.md`](docs/DELIVERY/README.md)）

## 当前阶段能力

首版聚焦郑州—开封、郑州—洛阳、焦作—云台山三条示范走廊，提供免登录浏览、景区内容、匿名规划、行程持久化、行程地图、局部调整、撤销、今日行程、只读分享、收藏、定位附近景点、个性化设置、账号安全和服务端消息中心。

当前已经落地的重点能力：

- APK：一句话规划、结构化行程、地图与时间轴联动、预算/天气/强度分析、局部调整、撤销、收藏星标、历史行程、今日行程、足迹、只读分享、附近景点、运行时服务器地址。
- 账号：注册登录、匿名体验、个人信息（昵称与预设头像）、修改密码、邮箱验证、退出所有设备、删除账号、消息通知。
- 服务端：Spring Boot + MySQL 8、LangChain4j 四家 LLM 供应商、百度地图、Open-Meteo、12306 MCP、提示词版本、Mock 数据覆盖、运营统计与审计日志。
- 管理台：景点内容、图片版权、城市/主题、AI 运行、提示词版本、Mock 数据、用户反馈、操作日志。
- 社区旅记：APK 已有信息流、详情、城市/主题筛选、点赞、举报和“从已保存行程发布旅记”；图片经服务端重编码去除 EXIF。管理台审核页仍待开发。

当前仍未完成或属于交付阶段的事项：

- 河南实景授权图替换、演示视频与界面截图；
- 公网 HTTPS 后端部署与 Release APK 真机验证；
- 正式 Release 签名、正式应用图标与启动页；
- 门票比价真实数据源、自动 OpenAPI、CI/CD 与错误监控。

当前能力边界与真实完成度请先阅读：

- [`docs/DELIVERY/README.md`](docs/DELIVERY/README.md)：**比赛交付材料索引** —— 作品要求对照、演示脚本、系统说明书、技术架构与数据模型、测试说明、需求实现对照
- [`docs/PHASE_AUDIT.md`](docs/PHASE_AUDIT.md)：阶段二、阶段三执行审计与风险分级
- [`docs/PROJECT_STRUCTURE.md`](docs/PROJECT_STRUCTURE.md)：APK、服务端、管理台目录职责与迁移规则
- [`docs/MOBILE_LAYOUT_SPEC.md`](docs/MOBILE_LAYOUT_SPEC.md)：360/390/412dp 移动端适配规范
- [`docs/NEXT_STAGE_PLAN.md`](docs/NEXT_STAGE_PLAN.md)：阶段四任务、验收证据与完成定义
- [`docs/PHASE7_ADMIN_CONSOLE.md`](docs/PHASE7_ADMIN_CONSOLE.md)：运营管理台、景点内容库、公开分享页与验证证据
- [`docs/PHASE8_MEDIA_UPLOAD.md`](docs/PHASE8_MEDIA_UPLOAD.md)：景点配图上传、格式与安全检查、模拟器配置说明
- [`docs/PHASE9_EXTERNAL_TOOLS.md`](docs/PHASE9_EXTERNAL_TOOLS.md)：真实外部数据源（天气 / 路线）、降级口径与验证证据
- [`docs/PHASE10_RAILWAY_AND_TICKETS.md`](docs/PHASE10_RAILWAY_AND_TICKETS.md)：12306 实时车次、百度地图 AK 生效过程、门票比价评估与验证证据
- [`docs/PHASE11_LLM_ENABLED.md`](docs/PHASE11_LLM_ENABLED.md)：真正接上大模型，以及打开开关后暴露并修复的两个真实缺陷
- [`docs/PHASE11_MAP.md`](docs/PHASE11_MAP.md)：行程地图（服务端代理静态底图）、投影反证、底图票据、地理编码判据与降级口径
- [`docs/PROJECT_STATUS.md`](docs/PROJECT_STATUS.md)：**当前进度快照、已完成 / 未实现清单与下一步优先级**
- [`docs/COMMUNITY_PLAN.md`](docs/COMMUNITY_PLAN.md)：社区旅记的分阶段实施计划与当前阶段边界
- [`docs/HTTPS_RELEASE_DEPLOYMENT.md`](docs/HTTPS_RELEASE_DEPLOYMENT.md)：**腾讯云 HTTPS、Docker 部署与 Release APK 真机验证步骤**
- [`docs/UI_REDESIGN.md`](docs/UI_REDESIGN.md)、[`docs/DESIGN_DIRECTION.md`](docs/DESIGN_DIRECTION.md)：v0.3 视觉与交互方向

服务端默认使用 H2 文件数据库，适合本地演示；生产环境通过 `prod` profile 连接 MySQL 8。AI 规划由 LangChain4j 统一适配四家 OpenAI 兼容供应商（OpenAI / DeepSeek / Kimi / 通义千问），按优先级自动降级，全部失败时由 Mock 规划引擎兜底并标注"演示数据"。外部 LLM、地图和 SMTP 均通过环境变量配置，客户端不保存服务端密钥。

APK 侧已经建立 `core/config`、`core/network`、`core/storage`、`core/theme` 基础设施：匿名令牌写入系统安全存储，数据读取按 `远端 → 离线缓存 → 本地演示` 三级降级，并且每条数据都会带上「实时 / 缓存 / 系统资料 / 演示 / 已过期」状态标签。

外部数据按**职责分层**，一层一个端口：景点与开放时间来自运营台内容库（系统资料）；天气走 Open-Meteo 实时预报（免费、无需密钥）；**跨城车次**走 12306 MCP（`mcp-server-12306`，官方车次与余票，未配置时退回明确标注"非实时"的参考时刻表）；**市内路线**走百度地图 Web 服务；门票价格走景区内容库参考价。取不到真实数据时一律带 `errorCode` 降级为"演示数据（降级）"，并在行程提示、依据页和运营台三处保持同一口径——不会把降级结果说成实时数据。

APK 前端**不直连**上表任何一个外部服务：12306 有频率限制、地图 AK 放客户端等于泄漏、天气统一走后端才能共享缓存。客户端只认自己后端的统一契约，`scripts\verify-tools.mjs` 里有断言保证轨迹里不会出现 AK、MCP 地址或会话头。

## 开发环境

本仓库使用一套**项目内工具链**：Flutter SDK、Android SDK、JDK 17 以及 Gradle / Pub 缓存
全部位于项目目录或项目内状态目录，不需要管理员权限，也不污染系统盘。安装步骤、环境变量、
镜像与 Windows 适配说明见 [`docs/DEVELOPMENT_ENVIRONMENT.md`](docs/DEVELOPMENT_ENVIRONMENT.md)。

```cmd
call D:\DESKTOP\ProWeb\toolchain.cmd
cd /d D:\DESKTOP\ProWeb\flutter_app
flutter pub get
flutter build apk --release
```

产物位于 `flutter_app\build\app\outputs\flutter-apk\app-release.apk`。

## 本地启动

```cmd
rem 终端 1：后端（内置 H2，启动时创建运营账号 operator / Operator12345）
scripts\run-server-dev.cmd

rem 终端 2：管理台 http://localhost:5173（已配置 /api 与 /share 代理）
cd backend\admin
npm install
npm run dev
```

1. `backend\server` 使用 JDK 17+ 和 Maven 启动，默认地址为 `http://localhost:8080`。
2. `backend\admin` 使用 Node.js 18+ 安装依赖后启动，默认地址为 `http://localhost:5173`。
3. `flutter_app` 使用项目内 Flutter stable 构建 Android APK，先执行 `call toolchain.cmd` 再构建，详见 `docs/DEVELOPMENT_ENVIRONMENT.md`。
4. SMTP 默认关闭，开发环境验证码只写入服务端日志，响应中的 `debugCode` 仅用于 Mock 演示。

后端启动后可运行端到端验证（真实创建/上下架/删除一条验证景点，覆盖分享页、统计与权限边界）：

```cmd
node scripts\verify-phase7.mjs
node scripts\verify-tools.mjs        rem 工具层与降级口径（37 项）
node scripts\verify-railway-mcp.mjs  rem 12306 端到端（21 项，需先启动 MCP）
node scripts\verify-llm.mjs          rem 大模型是否真在跑（12 项，只花 1 次模型调用）
node scripts\verify-map.mjs          rem 行程地图与底图票据（23 项）
node scripts\verify-media-upload.mjs rem 图片上传与访问
```

### 密钥与外部数据源配置

所有密钥放在 `scripts\local.env`（已被 .gitignore 忽略）。启动脚本只应用**非空**值，
所以留空的键会退回同名系统环境变量，不会被空值覆盖。模板见 `scripts\local.env.example`。

```cmd
rem scripts\local.env
BAIDU_MAP_AK=<百度地图开放平台 AK>
RAILWAY_PROVIDER=12306-mcp
RAILWAY_MCP_URL=http://localhost:8000/mcp
TICKET_PROVIDER=catalog
LLM_ENABLED=false
```

> **不要**把真实密钥写进 `.env.example`。那是随仓库分发的模板
> （`.gitignore` 里 `!.env.example` 显式放行），写进去等于提交密钥。
> 阶段十真的发生过一次：AK 写在 `.env.example` 里，结果是后端始终
> `route=not-configured`（配置没生效），同时密钥进入了版本库。

判断"配置到底生效没有"，看启动日志与健康度接口，不要靠感觉：

```cmd
rem 启动日志应为
rem [dev-server] baidu map ak: configured
rem [dev-server] railway mcp: http://localhost:8000/mcp

rem 健康度里 weather / route / railway / ticket 都应为 ready
node scripts\verify-tools.mjs
```

### 12306 实时车次（可选）

不启动时后端退回明确标注"非实时"的参考时刻表，规划链路不会失败。

```cmd
docker run -d --name yujian-mcp-12306 -p 8000:8000 drfccv/mcp-server-12306:latest
curl http://localhost:8000/health
node scripts\verify-railway-mcp.mjs
```

### 把 APK 装到模拟器上联调

| 产物 | 能否连本地后端 | 用途 |
| --- | --- | --- |
| `app-debug.apk` | **能**：内置 `http://10.0.2.2:8080/api`，且 debug 允许明文流量 | 模拟器联调、看真实数据 |
| `app-release.apk` | 支持运行时在「我的 → 设置 → 服务器地址」填写 HTTPS 地址；也可用 `--dart-define=API_BASE_URL=https://...` 固定 | 交付、公网测试 |

release 构建禁止明文流量，只接受 HTTPS；debug 构建保留 `http://10.0.2.2:8080/api`
回退，方便模拟器联调。运行时地址保存在本机安全存储中，适合部署到云服务器后再切换。

```cmd
rem 模拟器联调（推荐）
cd flutter_app
flutter build apk --debug

rem 交付 / 离线演示
flutter build apk --release
rem 有 HTTPS 后端时指向它
flutter build apk --release --dart-define=API_BASE_URL=https://your-host/api
```

运营台上传的景区图片，由客户端在解析时把回环主机改写成 API 主机
（见 `docs/PHASE10_RAILWAY_AND_TICKETS.md` 第 3.1 节），
所以模拟器**不需要**额外配置 `MEDIA_BASE_URL`。

## 容器启动

`docker-compose.yml` 位于 `backend/`，Compose 命令需要显式指定文件或先进入该目录：

```bash
docker compose -f backend/docker-compose.yml up --build
```

容器启动后：

- 游客端 API：`http://localhost:8080`
- 管理台：`http://localhost:5173`
- MySQL：`localhost:3306`

生产环境必须覆盖 `JWT_SECRET`、`MYSQL_PASSWORD` 和 SMTP 配置，不要使用示例默认值。

> 本机只保留这一套数据库：容器映射到 `3306`，并带 `restart: unless-stopped`，
> Docker Desktop 一起动它就跟着起来。原先装过的原生 MySQL 服务（`MySQL82`）同样抢 3306，
> 已停用；要重新启用它就先 `docker compose -f backend/docker-compose.yml stop mysql`，或给容器换个端口。

### 本机开发：只用容器的 MySQL，不起整套

`docker compose up` 会连后端一起启动并占用 8080，和本机开发用的后端脚本冲突。
只想把后端切到 MySQL 时，用这两条命令：

```bat
:: 本机统一用 docker compose 的 MySQL 8（映射 3306，已随 Docker 自启）
docker compose -f backend/docker-compose.yml up -d mysql
scripts\run-server-mysql.cmd

:: 换了环境、要连别的 MySQL 时再走这条（root 口令跑一次初始化）
:: scripts\init-mysql.cmd
```

默认的 `scripts\run-server-dev.cmd` 仍然用 H2 文件库（`backend\server\data\yujian.mv.db`），
开箱即跑、不需要数据库。H2 与 MySQL 是**两个互不相通的存储**：
`ddl-auto: update` 只建表，不会迁移已有账号与行程。

## 核心接口

### 游客端

- `GET /api/home`：首页推荐与三条示范走廊
- `GET /api/pois`、`GET /api/pois/{id}`：景区内容
- `POST /api/anonymous/session`：创建匿名体验会话
- `POST /api/trip-plans/preview`：旅行需求解析预览
- `POST /api/trip-plans`：生成并持久化行程；首次匿名创建时通过 `X-Anonymous-Token` 响应头返回会话令牌
- `GET /api/trip-plans`、`GET /api/trip-plans/{id}`：行程列表与详情
- `PATCH /api/trip-plans/{id}`、`DELETE /api/trip-plans/{id}`：修改与删除
- `POST /api/trip-plans/{id}/adjust`、`POST /api/trip-plans/{id}/undo`：局部调整与撤销
- `GET /api/trip-plans/{id}/today`：今日行程与下一站
- `GET /api/trip-plans/{id}/trace`：AI 引擎、工具调用与数据来源依据
- `GET /api/trip-plans/{id}/map`：当日行程地图快照（需登录态，含匿名会话）
- `GET /api/map/image`：底图 PNG，由服务端代取（AK 不下发），凭短时票据访问
- `GET /api/map/size`：底图默认尺寸
- `POST /api/trip-plans/{id}/share`、`GET /api/trip-shares/{token}`：只读分享
- `GET /share/{token}`：面向接收者的公开只读分享页（无需登录、无需安装 App）
- `POST /api/feedback`：匿名可提交的用户反馈
- `POST /api/favorites`、`GET /api/favorites`：登录用户收藏

### 运营管理台（需要 ADMIN 角色）

- `GET /api/admin/pois`、`POST /api/admin/pois`、`PUT /api/admin/pois/{id}`、`DELETE /api/admin/pois/{id}`
- `PATCH /api/admin/pois/{id}/publish`：上架 / 下架景点内容
- `POST /api/admin/media/images`：上传景点配图（multipart，仅 ADMIN）
- `POST /api/admin/pois/geocode`：按景点名解析可信坐标（只回参考值、不落库；必须有城市限定，且结果必须落在河南范围内）
- `GET /media/{fileName}`：上传图片的公开只读地址
- `GET /api/admin/stats/overview`：用户、行程、内容、工具调用、分享与近 7 天趋势
- `GET /api/admin/llm/providers`：LLM 供应商健康度与降级顺序（不含任何密钥）
- `GET /api/admin/feedback`、`PATCH /api/admin/feedback/{id}`：反馈受理
- `GET /api/admin/logs`：管理员操作日志

### 账号与安全

- `POST /api/auth/register`、`POST /api/auth/login`
- `POST /api/auth/refresh`、`POST /api/auth/logout`
- `GET /api/auth/me`
- `POST /api/auth/merge-anonymous`：登录后合并匿名行程
- `POST /api/email/send-code`、`POST /api/email/verify-code`：SMTP 预留接口

## 首版安全边界

- 密码使用 BCrypt 哈希存储。
- 访问令牌短期有效，刷新令牌按轮换机制使用。
- 匿名会话只保存令牌哈希和规划次数。
- 分享链接可设置有效期和隐藏预算。
- 不采集身份证号、银行卡号、支付信息和后台持续定位历史。

## 仓库与忽略规则

仓库只提交源代码、文档、脚本和可复现配置，不提交本机工具链与构建产物。以下目录/文件已被忽略：

```text
tooling/                         Flutter SDK、Android SDK、Gradle/Pub 缓存
flutter_app/build/               APK 构建产物
flutter_app/.dart_tool/          Dart 工具缓存
backend/server/target/           Maven 构建产物
backend/server/data/             本地 H2 数据库与上传文件
backend/admin/node_modules/      管理台依赖
backend/admin/dist/              管理台构建产物
backend.zip                      迁移临时压缩包
scripts/local.env                本地真实密钥
*.jks / key.properties           正式签名文件
```

如果换了机器，不要直接提交上述目录；按
[`docs/DEVELOPMENT_ENVIRONMENT.md`](docs/DEVELOPMENT_ENVIRONMENT.md)
重新安装工具链即可。

## 许可证

业务代码为本项目原创。第三方依赖及其许可证见 `THIRD_PARTY_NOTICES.md`。
