# 豫见智旅 HTTPS 后端与 Release APK 部署指南

> 适用范围：把本地 Spring Boot + MySQL + Vue 管理台迁移到腾讯云，并完成
> Android Release APK 的真机验证。
>
> 当前阶段不处理实景授权图和演示视频，只处理运行环境、HTTPS、签名和真机验收。

## 1. 当前状态

本地后端功能基本齐全：

- Spring Boot、MySQL、Vue 管理台都有 Docker 配置；
- `application-prod.yml` 已支持 MySQL；
- 管理台容器已有 Nginx `/api` 反代与 `/healthz`；
- 12306 MCP 有独立的 Compose profile；
- APK 支持编译期地址和运行时地址；
- release 包只接受 HTTPS，debug 包允许 HTTP。

本地还缺的主要是生产运行条件：

| 项目 | 现状 | 上云前需要 |
| --- | --- | --- |
| HTTPS 入口 | 只有本地 HTTP 8080 | 域名 + HTTPS 证书 + Nginx 443 |
| 公网域名 | 无 | 腾讯云域名解析到云服务器 |
| 生产密钥 | 默认开发值 | JWT、MySQL、地图、LLM 密钥全部替换 |
| 数据库备份 | 未做完整演练 | MySQL 持久卷 + 定时备份 + 恢复测试 |
| 上传目录 | 本地目录 | 云上持久卷，容器重建不丢图 |
| SMTP | 默认关闭 | 生产邮箱服务，否则邮箱验证不可用 |
| 监控 | 基本健康检查 | 日志、重启策略、磁盘/内存告警 |
| Release 签名 | 可使用 debug 回退 | 正式 keystore 与签名配置 |

## 2. 目标部署架构

```text
Internet
   │
   ▼
腾讯云安全组：80 / 443
   │
   ▼
Nginx（HTTPS 终止）
   ├── /api/    → Spring Boot 8080
   ├── /media/  → Spring Boot 静态图片
   ├── /share/  → Spring Boot 分享页
   └── /        → Vue 管理台

Docker 内网：
Spring Boot → MySQL
Spring Boot → 12306 MCP
```

MySQL 和 12306 MCP 不对公网开放。生产环境只向公网暴露 80/443。

## 3. 前置准备

### 3.1 本地

- 能运行 Docker Desktop；
- 有 Android 模拟器或真机；
- Flutter 工具链已就绪；
- 已在 `scripts/local.env` 配置本地密钥；
- 百度地图 AK、DeepSeek 等密钥不要提交到仓库。

### 3.2 云端

- 腾讯云 CVM 或轻量应用服务器；
- Ubuntu 22.04/24.04；
- 至少 2 核 4 GB 内存，磁盘建议 40 GB 以上；
- 一个域名；
- 域名 A 记录指向云服务器公网 IP；
- 云服务器安装 Docker 和 Docker Compose。

## 4. 阶段一：本地完整 MySQL 栈验证

### 4.1 启动 MySQL、后端和管理台

```cmd
cd /d D:\DESKTOP\ProWeb
docker compose -f backend\docker-compose.yml up -d --build mysql server admin
```

需要 12306 时：

```cmd
docker compose -f backend\docker-compose.yml --profile railway up -d mcp-12306
```

检查容器：

```cmd
docker compose -f backend\docker-compose.yml ps
```

### 4.2 本机接口检查

```text
http://localhost:8080/actuator/health
http://localhost:8080/api/home
http://localhost:5173
http://localhost:5173/healthz
```

### 4.3 局域网真机检查

1. 查电脑局域网 IPv4，例如 `192.168.1.20`；
2. 在真机浏览器打开：

```text
http://192.168.1.20:8080/api/home
```

3. 真机安装 debug APK；
4. 在 APK 中打开：

```text
我的 → 设置 → 软件设置 → 服务器地址
```

5. 输入：

```text
http://192.168.1.20:8080/api
```

6. 点「测试并保存」。

如果局域网访问失败，先检查 Windows 防火墙是否放行 8080，再确认手机和电脑在同一网段。

## 5. 阶段二：准备云服务器

1. 在腾讯云安全组只放行：

```text
22   SSH（建议限制为你的固定 IP）
80   HTTP
443  HTTPS
```

临时调试才放行 `8080`，正式使用后关闭。

2. 登录服务器安装 Docker：

```bash
sudo apt update
sudo apt install -y docker.io docker-compose-plugin
sudo systemctl enable --now docker
docker --version
docker compose version
```

3. 拷贝或拉取项目到服务器，例如：

```bash
/opt/yujian/ProWeb
```

4. 生产环境不要把 MySQL 的 3306 端口暴露到公网。

## 6. 阶段三：配置生产环境变量

### 6.1 创建私有环境文件

```bash
cd /opt/yujian/ProWeb/backend
cp .env.example .env
```

`backend/.env` 不要提交到 Git。

### 6.2 必须修改的配置

```text
SPRING_PROFILES_ACTIVE=prod

JWT_SECRET=至少 32 位的随机字符串

MYSQL_USER=yujian
MYSQL_PASSWORD=替换成强密码
MYSQL_ROOT_PASSWORD=替换成强密码

APP_TOOLS_MODE=live

BAIDU_MAP_AK=你的百度地图 AK

RAILWAY_PROVIDER=12306-mcp
RAILWAY_MCP_URL=http://mcp-12306:8000/mcp
RAILWAY_CACHE_MINUTES=30

MEDIA_STORAGE_DIR=/data/uploads
MEDIA_BASE_URL=https://travel.example.com/media

SHARE_BASE_URL=https://travel.example.com/share
CORS_ALLOWED_ORIGINS=https://travel.example.com

SMTP_ENABLED=true
SMTP_HOST=smtp.example.com
SMTP_PORT=587
SMTP_USERNAME=你的邮箱账号
SMTP_PASSWORD=你的邮箱授权码
SMTP_FROM=no-reply@example.com
SMTP_MOCK_CODE_LOG=false

LLM_ENABLED=true
LLM_DEEPSEEK_ENABLED=true
LLM_DEEPSEEK_API_KEY=你的 DeepSeek Key
LLM_DEEPSEEK_MODEL=deepseek-chat
```

### 6.3 密钥边界

- 所有第三方密钥只放在服务器环境变量或 `backend/.env`；
- APK 和管理台都不得包含密钥；
- 不要把 `backend/.env`、`scripts/local.env`、keystore 提交到仓库；
- 日志不得打印完整 Key、JWT 或密码。

## 7. 阶段四：启动云端 Docker 服务

### 7.1 启动基础服务

```bash
cd /opt/yujian/ProWeb
docker compose -f backend/docker-compose.yml up -d --build mysql server admin
```

### 7.2 启动 12306 MCP

```bash
docker compose -f backend/docker-compose.yml --profile railway up -d mcp-12306
```

### 7.3 查看状态

```bash
docker compose -f backend/docker-compose.yml ps
docker compose -f backend/docker-compose.yml logs -f server
docker compose -f backend/docker-compose.yml logs -f mcp-12306
```

### 7.4 容器内检查

```bash
curl http://127.0.0.1:8080/actuator/health
curl http://127.0.0.1:8080/api/home
curl http://127.0.0.1:8000/health
```

## 8. 阶段五：配置 Nginx 与 HTTPS

### 8.1 安装 Nginx 和 Certbot

```bash
sudo apt install -y nginx certbot python3-certbot-nginx
```

### 8.2 配置反向代理

将下面内容保存为 `/etc/nginx/sites-available/yujian`：

```nginx
server {
    listen 80;
    server_name travel.example.com;

    location / {
        proxy_pass http://127.0.0.1:5173;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

启用站点：

```bash
sudo ln -s /etc/nginx/sites-available/yujian /etc/nginx/sites-enabled/yujian
sudo nginx -t
sudo systemctl reload nginx
```

### 8.3 签发证书

如果 DNS 已解析到服务器：

```bash
sudo certbot --nginx -d travel.example.com
```

Certbot 会自动增加 443 配置并设置 HTTP → HTTPS 跳转。

### 8.4 补全 API、图片和分享反代

证书签发后，把 443 server 块补成：

```nginx
location /api/ {
    proxy_pass http://127.0.0.1:8080;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}

location /media/ {
    proxy_pass http://127.0.0.1:8080;
}

location /share/ {
    proxy_pass http://127.0.0.1:8080;
}

location / {
    proxy_pass http://127.0.0.1:5173;
}
```

重新加载：

```bash
sudo nginx -t
sudo systemctl reload nginx
```

## 9. 阶段六：公网验证

### 9.1 服务端验证

```bash
curl -i https://travel.example.com/actuator/health
curl -i https://travel.example.com/api/home
curl -I https://travel.example.com/media/
```

### 9.2 管理台验证

浏览器打开：

```text
https://travel.example.com
```

使用运营账号登录，检查：

- 景点列表和图片；
- 数据源健康度；
- AI 供应商；
- 提示词版本；
- Mock 数据；
- 用户反馈和操作日志。

### 9.3 12306 验证

```bash
docker compose -f backend/docker-compose.yml logs -f mcp-12306
```

生成一次跨城行程，检查工具轨迹里的：

- `searchTrain`
- `quoteRailFares`
- `searchTransfer`

必须显示真实来源或明确的缓存状态，不能把参考数据标成实时。

## 10. 阶段七：构建 Release APK

### 10.1 配置正式签名

在 `flutter_app/android/` 下创建 `key.properties`：

```properties
storeFile=keystore/yujian-release.jks
storePassword=******
keyAlias=yujian
keyPassword=******
```

keystore 和 `key.properties` 不要提交。

### 10.2 编译期固定服务器地址

```cmd
call D:\DESKTOP\ProWeb\toolchain.cmd
cd /d D:\DESKTOP\ProWeb\flutter_app
flutter clean
flutter pub get
flutter build apk --release --dart-define=API_BASE_URL=https://travel.example.com/api
```

产物：

```text
flutter_app\build\app\outputs\flutter-apk\app-release.apk
```

### 10.3 使用运行时地址

如果希望测试者自己切服务器：

```cmd
flutter build apk --release
```

安装后在：

```text
我的 → 设置 → 软件设置 → 服务器地址
```

填写：

```text
https://travel.example.com/api
```

release 包不能使用 `http://` 公网地址。

## 11. 阶段八：Release 真机验收

目标设备：Android 10 及以上的常见中端手机。

安装：

```cmd
adb install -r app-release.apk
```

至少验证：

- 首次打开首页；
- 未登录浏览景区；
- 注册与登录；
- 一句话生成行程；
- 工具轨迹显示实时 / 缓存 / 演示；
- 行程地图、路线和时间轴；
- 12306 车次、票价、中转；
- 收藏星标：未收藏空心、收藏后实心；
- 历史行程、今日行程、下一站；
- 分享链接在浏览器打开；
- 修改昵称、预设头像；
- 修改密码后重新登录；
- 邮箱验证；
- 退出所有设备；
- 删除账号；
- 消息中心与已读状态；
- 设置页服务器地址测试；
- 清除离线缓存；
- 断网后读取最近行程；
- 拒绝定位后仍能按城市浏览；
- 系统字体放大；
- 覆盖安装后数据仍可读取。

遇到连接失败时：

```cmd
adb logcat | findstr /i "yujian dio ssl http"
```

重点检查域名解析、证书、HTTPS、安全组和 `API_BASE_URL`。

## 12. 数据库与上传文件持久化

### 12.1 数据库备份

```bash
docker exec yujian-mysql mysqldump \
  -uyujian -p yujian_travel > backup-$(date +%F).sql
```

恢复前先停后端写入，再导入备份并在测试环境验证。

### 12.2 上传目录

生产环境把 `MEDIA_STORAGE_DIR` 指向持久卷，例如：

```text
/data/uploads
```

备份：

```bash
tar -czf uploads-$(date +%F).tar.gz /data/uploads
```

容器重建后必须确认旧图片仍可访问。

## 13. 常见故障

### 13.1 APK 连不上

1. 真机浏览器能否打开 `https://travel.example.com/api/home`；
2. 证书是否被 Android 信任；
3. release 包是否误用了 HTTP；
4. `API_BASE_URL` 是否包含 `/api`；
5. 云安全组是否放行 443；
6. Nginx 是否把 `/api/` 转到 8080。

### 13.2 图片打不开

检查：

```text
MEDIA_BASE_URL=https://travel.example.com/media
```

以及 Nginx `/media/` 是否转发到后端。

### 13.3 分享链接指向 localhost

修改：

```text
SHARE_BASE_URL=https://travel.example.com/share
```

并重启 server。

### 13.4 邮箱没有验证码

检查：

- `SMTP_ENABLED=true`；
- SMTP 主机、端口、用户名、授权码；
- 生产环境不会返回 `debugCode`；
- 云服务器是否能访问 SMTP 端口。

### 13.5 12306 返回参考数据

检查：

```text
RAILWAY_PROVIDER=12306-mcp
RAILWAY_MCP_URL=http://mcp-12306:8000/mcp
```

并确认 `mcp-12306` 容器健康。

## 14. 完成标准

以下全部满足，才算“HTTPS 后端 + Release APK”闭环：

- 云服务器安全组只开放 80/443；
- MySQL、MCP 不暴露公网；
- `https://travel.example.com/api/home` 可访问；
- `/media/`、`/share/` 走公网 HTTPS；
- 管理台可登录并管理内容；
- 12306、地图、天气、LLM 状态可见；
- Release APK 使用正式 keystore 签名；
- Release APK 在真机完成主流程回归；
- 断网、权限拒绝、证书异常都有明确提示；
- MySQL 和上传目录有可执行备份；
- `docs/API.md`、`PROJECT_STATUS.md` 与实际环境一致。

## 15. 边界与注意

1. 本指南不处理支付、购票、酒店预订；
2. 12306 仅做参考查询，购票仍在官方渠道完成；
3. 当前没有自动 CI/CD，部署以 Docker Compose 和手动发布为主；
4. 正式上线前必须替换所有开发密码；
5. 本指南中的域名、IP、密码和 Key 都只是占位符，不要照抄。
