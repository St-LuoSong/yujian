# 后端服务（backend）

本目录集中存放《豫见智旅》所有**后端相关服务**。前端 APK 与 SDK 工具链不在本目录。

## 目录结构

```text
backend/
├── server/                  # Spring Boot 3.3.5 / Java 17 服务端
│   ├── src/                 # 业务代码：api / ai / service / domain / infrastructure
│   ├── data/                # 本机 H2 文件库与上传图片（忽略，不提交）
│   ├── target/              # Maven 构建产物（忽略，不提交）
│   ├── Dockerfile
│   └── pom.xml
├── admin/                   # Vue 3 + Vite 运营管理台
│   ├── src/
│   ├── dist/                # 构建产物（忽略，不提交）
│   ├── node_modules/        # 依赖（忽略，不提交）
│   ├── Dockerfile
│   └── package.json
├── docker-compose.yml       # 后端本地/演示编排（MySQL + server + admin）
└── .env.example             # 后端环境变量模板，不放真实密钥
```

## 本地运行

在项目根目录执行：

```cmd
rem 后端（H2 内置库，启动时创建运营账号 operator / Operator12345）
scripts\run-server-dev.cmd

rem 管理台 http://localhost:5173
cd backend\admin
npm install
npm run dev
```

切换 MySQL 8：

```cmd
docker compose -f backend\docker-compose.yml up -d mysql
scripts\run-server-mysql.cmd
```

## 容器运行

`docker-compose.yml` 位于本目录，请在项目根目录显式指定文件：

```bash
docker compose -f backend/docker-compose.yml up --build
```

## 配置与密钥

- 真实密钥写在 `scripts\local.env`（已被 `.gitignore` 忽略），不要写进 `.env.example`。
- 模板见 `backend\.env.example` 与 `scripts\local.env.example`。
- 服务端密钥（LLM / 百度地图 / SMTP / JWT）只存在于 `backend/server`，不会下发到 APK 或管理台。
- 生产环境必须覆盖 `JWT_SECRET`、`MYSQL_PASSWORD`、SMTP 与 LLM 配置，不要使用示例默认值。

## 验证

在项目根目录执行（后端已启动）：

```cmd
node scripts\verify-phase7.mjs
node scripts\verify-tools.mjs
node scripts\verify-llm.mjs
node scripts\verify-map.mjs
node scripts\verify-media-upload.mjs
```

后端单元测试：

```cmd
cd backend\server
mvn -o -B test
```
