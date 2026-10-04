# T38：APK 可信发布、版本检查与更新提醒

日期：2026-10-03（Asia/Shanghai）

## 1. 已实现的闭环

```text
开发者用正式 keystore 构建 Release APK
  → 管理台「应用发布」上传
  → 服务端验证 APK 签名完整性
  → 校验包名与正式证书 SHA-256 白名单
  → 解析 versionCode / versionName / minSdk / targetSdk
  → 服务端计算 APK 文件 SHA-256
  → 安装包进入 UPLOADED（不会自动发布）
  → 管理员填写更新说明、策略与最低支持版本
  → 发布后 APK 冷启动或回到前台时检查
  → 可选更新显示小卡片；强制更新阻断业务
  → 系统浏览器下载；Android 安装器再次校验签名连续性
```

客户端同时读取当前安装包证书 SHA-256。正式包若与服务端发布清单中的证书不一致，即使
`versionCode` 相同也进入强制更新提示。该比较用于本机风险提示，不作为服务端认证边界；
服务端仍只信任自己从上传 APK 中解析出的签名证书。

## 2. 一次性配置正式签名

keystore、密码与 `android/key.properties` 都不能提交到 Git。项目已经禁止 Release 构建
回退到 Debug 证书：未配置正式签名时，`flutter build apk --release` 会明确失败。

`flutter_app/android/key.properties` 示例：

```properties
storeFile=keystore/yujian-release.jks
storePassword=请填写本机私密值
keyAlias=yujian
keyPassword=请填写本机私密值
```

使用 JDK 自带 `keytool` 查看证书指纹：

```bat
keytool -list -v -keystore flutter_app\android\keystore\yujian-release.jks -alias yujian
```

把输出中的 SHA-256 写进私密环境文件 `scripts/local.env`：

```env
APP_RELEASE_ALLOWED_CERT_SHA256=AA:BB:CC:...
```

服务端会忽略冒号与大小写。密钥轮换期允许用英文逗号配置多个证书，但普通情况下只保留
一个正式证书。

## 3. 构建与发布

每次发布必须同时递增 `flutter_app/pubspec.yaml` 的版本名和构建号，例如：

```yaml
version: 0.2.0+2
```

其中 `0.2.0` 是给用户看的 `versionName`，`2` 是服务端比较的 `versionCode`。

```bat
call D:\DESKTOP\ProWeb\toolchain.cmd
cd /d D:\DESKTOP\ProWeb\flutter_app
flutter build apk --release --dart-define=API_BASE_URL=https://你的域名/api
```

构建后打开管理台「应用发布」，上传 `build\app\outputs\flutter-apk\app-release.apk`，
核对只读的包名、版本、证书摘要和文件摘要，填写更新说明与策略后确认发布。

## 4. 更新策略

| 情况 | 客户端行为 |
| --- | --- |
| 当前版本不低于最新版 | 不提示 |
| 当前版本低于最新版，但仍受支持 | 首页顶部显示可关闭的小卡片 |
| 当前版本低于最低支持版本 | 显示不可绕过的更新页 |
| 发布策略为 `REQUIRED` 且存在新版本 | 显示不可绕过的更新页 |
| 正式包证书与发布清单不一致 | 显示签名风险强制更新页 |
| 版本检查网络失败 | 不阻断业务；回到前台超过 6 小时后重试 |

Debug APK 跳过证书连续性比较，但仍会检查版本，便于本地联调。

## 5. 数据与部署

- APK 文件保存在 `APP_RELEASE_STORAGE_DIR`，默认 `./data/releases`；
- Docker 使用 `server-data:/app/data` 持久卷，同时保护景点图、旅记图和 APK；
- APK 不通过公开 `/media/**` 暴露，只能通过已发布版本的下载接口获取；
- 停止发布后下载接口失效；被新版本替代的旧包保留下载，避免切换瞬间的竞态；
- 版本上传、发布、停用均进入管理员操作日志；
- 管理台 Nginx 与 Spring multipart 上限为 320MB，版本模块仍按自己的上限再次校验。

## 6. 接口

```text
GET   /api/app-releases/check?packageName=...&versionCode=...
GET   /api/app-releases/{id}/download
GET   /api/admin/app-releases
POST  /api/admin/app-releases
POST  /api/admin/app-releases/{id}/publish
PATCH /api/admin/app-releases/{id}/disable
```

## 7. 本轮验证

```text
mvn -B test
  Tests run: 115, Failures: 0, Errors: 0

npm run build
  619 modules transformed

flutter analyze
  No issues found

flutter test test/data/app_update_repository_test.dart
  All tests passed (3)

flutter test
  All tests passed (154)

flutter build apk --debug
  Built build/app/outputs/flutter-apk/app-debug.apk
```

正式 APK 上传验收需在配置 release keystore 与证书白名单后执行，不能用 Debug 包代替。
