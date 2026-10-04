# 豫见智旅

面向河南自由行游客的 AI 旅行规划与智慧出行平台：一句话描述需求，得到一份**有数据依据、可调整、可执行**的河南行程。

不是聊天机器人，也不是旅游资讯浏览器——重点是"**为什么这个方案走得通**"：路线耗时、开放时间、天气影响、预算构成都逐项给出，并标注每条数据是实时、缓存、系统资料还是演示数据。

## 组成

| 模块 | 目录 | 技术栈 | 产物 |
| --- | --- | --- | --- |
| 游客端 | `flutter_app/` | Flutter + Riverpod + Dio | Android APK（主交付物） |
| 服务端 | `backend/server/` | Spring Boot + JPA + MySQL 8 + LangChain4j | REST API |
| 管理台 | `backend/admin/` | Vue 3 + Vite + TypeScript | 浏览器访问 |

主要能力：一句话规划、结构化行程、地图与时间轴联动、预算/天气/强度分析、局部调整与撤销、收藏、历史行程、今日行程与下一站、只读分享、附近景点；社区旅记（信息流 / 详情 / 发布审核 / 点赞 / 收藏 / 二级评论）；账号与消息中心；运营台内容管理、审核、统计、限流与工具配额。

## 快速开始

需要 JDK 17+、Node.js 18+、Docker（可选）。Flutter 与 Android SDK 由项目内 `toolchain.cmd` 提供，不污染系统盘。

```cmd
rem 1) 服务端：内置 H2 文件库，开箱即跑（默认运营账号 operator / Operator12345）
scripts\run-server-dev.cmd

rem 2) 管理台：http://localhost:5173（已配置 /api 与 /share 代理）
cd backend\admin
npm install
npm run dev

rem 3) APK：先加载工具链，产物在 flutter_app\build\app\outputs\flutter-apk\
call toolchain.cmd
cd flutter_app
flutter build apk --debug
```

H2 与 MySQL 是两套互不相通的存储，`ddl-auto` 只建表、不迁移数据。要改用容器里的 MySQL，见下一节。

## 配置

### 密钥

**所有真实密钥都放在 `scripts\local.env`，它已被 .gitignore 忽略。** 从模板复制后按需填写：

```cmd
copy scripts\local.env.example scripts\local.env
```

启动脚本只应用**非空**值，留空的键会退回同名系统环境变量。`scripts\run-server-dev.cmd` 会在启动时打印哪些数据源真的配上了——判断配置是否生效看这行日志，不要靠感觉。

> ⚠️ **不要**把真实密钥写进 `.env.example`。那是随仓库分发的模板（`.gitignore` 里用 `!.env.example` 显式放行），写进去等于提交密钥。

### 关键配置项

| 变量 | 说明 | 不配置的后果 |
| --- | --- | --- |
| `BAIDU_MAP_AK` | 百度地图 Web 服务 AK，用于路线规划 | 路线带原因降级为演示数据 |
| `LLM_ENABLED` + 各厂商 `*_API_KEY` | OpenAI / DeepSeek / Kimi / 通义千问，按 priority 降级 | 全部走 Mock 规划引擎 |
| `RAILWAY_PROVIDER` | 设为 `12306-mcp` 时走实时车次 | 用明确标注"非参考实时"的时刻表 |
| `MEDIA_BASE_URL` | 反向代理或局域网访问时的图片地址前缀 | 上传图片地址会推导成容器内 localhost |
| `JWT_SECRET` / `MYSQL_PASSWORD` | 生产环境必须覆盖 | 使用示例默认值，等同于没有保护 |

### 12306 实时车次（可选）

```cmd
docker compose -f backend/docker-compose.yml --profile railway up -d mcp-12306
rem 然后把 RAILWAY_PROVIDER 设为 12306-mcp
```

## 打包 APK

**后端地址在打包时固定**——运行时可改的入口已从设置页移除，避免"改过又自己变回去"。

```cmd
call toolchain.cmd
cd flutter_app

rem 模拟器联调：内置 http://10.0.2.2:8080/api，且 debug 允许明文流量
flutter build apk --debug

rem 指向真实后端（release 只接受 HTTPS，明文会被拒绝）
flutter build apk --release --dart-define=API_BASE_URL=https://your-host/api
```

`--dart-define` 的优先级高于任何本地存储，所以地址一旦打进去就不会被运行时改动覆盖。debug 包体积较大（JIT + 三个 ABI），要减小可用 `--split-per-abi` 或 `--target-platform android-arm64`。

## 容器部署

```bash
docker compose -f backend/docker-compose.yml up --build -d
```

| 服务 | 地址 |
| --- | --- |
| 游客端 API | http://localhost:8080 |
| 管理台 | http://localhost:5173 |
| MySQL | localhost:3306 |

启动前请在 `backend/` 下准备 `.env`（参考 `backend/.env.example`），至少覆盖 `MYSQL_PASSWORD`、`MYSQL_ROOT_PASSWORD`、`JWT_SECRET`、`ADMIN_USERNAME`、`ADMIN_PASSWORD`。

生产环境还要注意：

- **必须上 HTTPS。** 本项目的 debug APK 走明文 HTTP，登录口令与访问令牌在网络路径上是明文；release 构建会直接拒绝明文后端。
- **数据库结构由 Flyway 管理。** 生产 profile 下 `ddl-auto=none`，迁移脚本在 `backend/server/src/main/resources/db/migration/`，启动时自动执行。
- **不要执行 `docker compose down -v`**，除非确定要连同 MySQL 数据卷与上传文件一起删除。

## 测试

```cmd
rem 服务端
cd backend\server && mvn -o -B test

rem APK
call toolchain.cmd
cd flutter_app && flutter analyze && flutter test

rem 管理台
cd backend\admin && npm run build
```

后端起来后还可以跑端到端脚本（会真实创建/上下架/删除一条验证数据）：

```cmd
node scripts\verify-tools.mjs         rem 工具层与降级口径
node scripts\verify-map.mjs           rem 行程地图与底图票据
node scripts\verify-llm.mjs           rem 大模型是否真在跑（只花 1 次调用）
node scripts\verify-railway-mcp.mjs   rem 12306 端到端（需先启动 MCP）
node scripts\verify-media-upload.mjs  rem 图片上传与访问
```

## 数据来源与诚实标注

外部数据按职责分层，**APK 前端不直连任何外部服务**（12306 有频率限制、地图 AK 放客户端等于泄漏、统一走后端才能共享缓存）。数据源取不到时一律带原因降级为演示数据，并在行程提示、依据页和运营台三处保持同一口径——不会把降级结果说成实时数据。

| 数据 | 来源 |
| --- | --- |
| 景点、开放时间、门票参考价 | 运营台内容库（系统资料） |
| 天气 | Open-Meteo（免费，无需密钥） |
| 跨城车次 | 12306 MCP（未配置时退回参考时刻表） |
| 市内路线 | 百度地图 Web 服务 |

外部工具调用有**每日配额**（天气 / 路线 / 铁路三组，可在管理台「安全与限流」调整），额度用尽时熔断并如实标注"未取到实时数据"，不会继续消耗上游额度。接口侧另有分桶限流（登录、生成行程、上传、写操作、读接口）。

## 文档

| 文档 | 内容 |
| --- | --- |
| [`docs/PROJECT_STATUS.md`](docs/PROJECT_STATUS.md) | 当前进度、已完成 / 未完成清单、下一步优先级 |
| [`docs/SECURITY_AUDIT.md`](docs/SECURITY_AUDIT.md) | 安全与稳定性审计：已挡住的、新补的、剩下的风险 |
| [`docs/API.md`](docs/API.md) | 对外接口、鉴权矩阵、错误码、数据状态语义 |
| [`docs/DEVELOPMENT_ENVIRONMENT.md`](docs/DEVELOPMENT_ENVIRONMENT.md) | 项目内工具链安装与环境变量 |
| [`docs/DELIVERY/README.md`](docs/DELIVERY/README.md) | 比赛交付材料索引（说明书、架构、测试、演示脚本） |
| [`docs/PROJECT_STRUCTURE.md`](docs/PROJECT_STRUCTURE.md) | 三个模块的目录职责与迁移规则 |

## 仓库约定

仓库只提交源代码、文档、脚本与可复现配置。**不提交**：本机工具链（`tooling/flutter/`、`tooling/android-sdk/`）、构建产物（`flutter_app/build/`、`backend/server/target/`、`backend/admin/dist/`）、本地数据（`backend/server/data/`）、真实密钥（`scripts/local.env`、`.env`）、签名文件（`*.jks`、`key.properties`）。

换机器时不要直接提交这些目录，按 `docs/DEVELOPMENT_ENVIRONMENT.md` 重新安装即可。

## 许可证

业务代码为本项目原创。第三方依赖及其许可证见 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)。
