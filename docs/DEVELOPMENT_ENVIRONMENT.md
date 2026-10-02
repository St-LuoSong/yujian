# 开发环境与 Android 构建说明

本文档记录《豫见智旅》在本机上使用的**项目内置工具链**：Flutter SDK、Android SDK、
JDK、Gradle 全部放在项目目录或使用项目内状态目录，不依赖系统盘安装、不需要管理员权限。

## 1. 工具链位置

| 组件 | 版本 | 路径 |
| --- | --- | --- |
| Flutter SDK | 3.47.5 stable / Dart 3.13.4 | `D:\DESKTOP\ProWeb\tooling\flutter` |
| Android SDK | Platform 36 / Build-Tools 36.0.0 | `D:\DESKTOP\ProWeb\tooling\android-sdk` |
| JDK | 17.0.16 LTS | `C:\Program Files\Java\jdk-17` |
| Gradle | 9.3.1（由 Wrapper 管理） | `D:\DESKTOP\ProWeb\tooling\.gradle` |
| Android 用户目录 | — | `D:\DESKTOP\ProWeb\tooling\.android` |
| Pub 缓存 | — | `D:\DESKTOP\ProWeb\tooling\.pub-cache` |

Android SDK 组件清单：

```text
build-tools;36.0.0
platform-tools
platforms;android-36
```

> `tooling\flutter`、`tooling\android-sdk`、`tooling\.gradle`、`tooling\.android`、`tooling\.pub-cache`
> 均在 `.gitignore` 中忽略，不会提交到仓库。
> 换一台机器时按第 6 节重新安装即可。

## 2. 环境变量

用户级环境变量（`HKCU\Environment`）由脚本写入，执行后需要**新开一个 cmd 窗口**：

```cmd
scripts\set-user-env.cmd
```

写入内容：

```text
JAVA_HOME                = C:\Program Files\Java\jdk-17
FLUTTER_HOME             = D:\DESKTOP\ProWeb\tooling\flutter
ANDROID_SDK_ROOT         = D:\DESKTOP\ProWeb\tooling\android-sdk
ANDROID_HOME             = D:\DESKTOP\ProWeb\tooling\android-sdk
GRADLE_USER_HOME         = D:\DESKTOP\ProWeb\tooling\.gradle
ANDROID_USER_HOME        = D:\DESKTOP\ProWeb\tooling\.android
PUB_CACHE                = D:\DESKTOP\ProWeb\tooling\.pub-cache
PUB_HOSTED_URL           = https://pub.flutter-io.cn
FLUTTER_STORAGE_BASE_URL = https://storage.flutter-io.cn
```

`PATH` 采用**只追加**策略，依次补充：

```text
%JAVA_HOME%\bin
%FLUTTER_HOME%\bin
%ANDROID_SDK_ROOT%\cmdline-tools\latest\bin
%ANDROID_SDK_ROOT%\platform-tools
```

脚本在修改前会把原注册表项导出为 `scripts\user-env-backup.reg`；若读取
`HKCU\Environment` 失败则直接中止，不会覆盖已有 PATH。

只影响当前命令行窗口的临时方式：

```cmd
call D:\DESKTOP\ProWeb\toolchain.cmd
```

## 3. Gradle 镜像重定向（本机必需）

当前网络**无法访问 `maven.google.com` / `dl.google.com`**（IPv4、IPv6 均超时），
但阿里云镜像提供同样的构件，包含 Flutter 3.47.5 模板要求的 AGP 9.1.0。

源码：`scripts\gradle\alimaven-google.init.gradle`

`toolchain.cmd` 会把它复制到 Gradle 自动加载的目录：

```text
%GRADLE_USER_HOME%\init.d\alimaven-google.init.gradle
```

该 init 脚本只重写 Google Maven 仓库地址，覆盖构建树中的**所有 settings 与 project**，
包括 Flutter SDK 内部的 `packages/flutter_tools/gradle`（该 included build 的
`settings.gradle.kts` 硬编码了 `google()` 且不允许项目级仓库，不能也不需要改动 Flutter SDK）。

设计取舍：

- 镜像属于**环境差异**，因此放在 init 脚本而不是 `flutter_app/android/*.gradle.kts`，
  保证 Android 工程与 `flutter create` 官方模板一致、可移植；
- Maven Central、Gradle Plugin Portal、Flutter 存储站点在本机可直连，保持官方源不变；
- 网络恢复后删除 `.gradle\init.d\alimaven-google.init.gradle` 即可走官方源。

## 4. 环境适配与构建验证

构建过程中遇到并已固化的三个环境特有问题。

### 4.1 Google Maven 不可达

见第 3 节，通过 Gradle init 脚本重定向到阿里云镜像。

### 4.2 Pub 缓存必须与工程同盘

`share_plus` 等插件的 Kotlin 源码位于 Pub 缓存中。若缓存位于 `C:` 而工程位于 `D:`，
Kotlin 增量编译器无法对跨盘符路径求相对路径：

```text
java.lang.IllegalArgumentException: this and base files have different roots:
  C:\Users\<user>\AppData\Local\Pub\Cache\hosted\pub.dev\share_plus-10.1.4\...
  D:\DESKTOP\ProWeb\flutter_app\android
```

因此 `PUB_CACHE` 固定为工程内的 `D:\DESKTOP\ProWeb\tooling\.pub-cache`。
工程换到其他盘时该变量随之变化，始终保持同盘。

### 4.3 关闭 Kotlin 增量编译

Kotlin 2.4 的增量编译在 Windows 上编译插件模块时仍会不稳定地失败：

```text
Could not close incremental caches in ...\caches-jvm\jvm\kotlin: class-fq-name-to-source.tab
java.lang.IllegalStateException: Storage for [...\source-to-output.tab] is already registered
```

已在 `flutter_app\android\gradle.properties` 设置 `kotlin.incremental=false`。
代价仅是二次构建略慢，换来可复现的构建结果。

### 4.4 构建验证结果

本机已实际构建通过：

```text
Running Gradle task 'assembleRelease'...                           44.9s
√ Built build\app\outputs\flutter-apk\app-release.apk (50.1MB)
```

`flutter analyze` 亦为 `No issues found!`。

## 5. 构建 APK

```cmd
call D:\DESKTOP\ProWeb\toolchain.cmd
cd /d D:\DESKTOP\ProWeb\flutter_app
flutter pub get
flutter build apk --release
```

产物：

```text
D:\DESKTOP\ProWeb\flutter_app\build\app\outputs\flutter-apk\app-release.apk
```

调试包：

```cmd
flutter build apk --debug
```

### 静态素材（足迹底图）

```text
flutter_app/assets/images/henan_map.jpg   河南省底图（450×452，自带省界与 18 个地市名）
flutter_app/pubspec.yaml                  已注册 assets/images/，新图片放同一目录即可被打包
```

换底图只要替换这个文件，并重新标定 `_HenanFootprintPainter._labels` 里的 18 个相对坐标
（相对位置，不是经纬度；这条注释也写在该文件的源码里）。

### 后端地址

客户端默认指向 Android 模拟器访问宿主机的地址：

```text
http://10.0.2.2:8080/api
```

真机演示时用编译期变量覆盖：

```cmd
flutter build apk --release --dart-define=API_BASE_URL=http://192.168.1.20:8080/api
```

release 包也支持在「我的 → 设置 → 服务器地址」里运行时配置：填写后先测试
`GET /api/home`，成功再保存；地址写入本机安全存储，下一次启动继续生效。
编译期 `API_BASE_URL` 仍然优先，并且会出现“当前安装包已固定”的提示。
正式交付必须使用 HTTPS；debug 包才允许明文 HTTP。

### 网络安全配置

| 构建类型 | 明文 HTTP | 说明 |
| --- | --- | --- |
| release | 禁止 | 只允许 HTTPS，见 `app/src/main/res/xml/network_security_config.xml` |
| debug | 允许 | 便于连接本机 HTTP 后端与抓包调试，见 `app/src/debug/res/xml/...` |

### 定位权限（「附近的景点」）

APK 声明 `ACCESS_COARSE_LOCATION` 与 `ACCESS_FINE_LOCATION`，**只服务「附近的景点」一个功能**，
权限与调用代码（`lib/core/location/location_service.dart`）是同一轮加入的：

```text
flutter_app/android/app/src/main/AndroidManifest.xml   声明粗/精两个权限
flutter_app/lib/core/location/location_service.dart    唯一的定位调用点
```

规则与取舍：

- 只在用户主动点「在我附近」后才申请权限，不在启动时预弹；
- Android 12+ 用户可只给「大致位置」，3 公里半径判断有粗略权限就够用；
- 拒绝授权不会让应用变残：附近页退回「按城市浏览」（手动选城市看景点）；
- 只有「永久拒绝」或「系统定位总开关关闭」才引导到系统设置；
- 坐标只用于当次 `/api/pois/nearby` 请求，客户端不缓存坐标，服务端不落库；
- 模拟器验证需手动设定位点（Extended controls → Location），
  例如郑州 `113.6254, 34.7466`、洛阳 `112.4540, 34.6197`。

### 正式签名

未提供 `android\key.properties` 时，release 包使用 debug 密钥签名（可安装、可演示）。
比赛提交正式包时在 `flutter_app\android\` 下创建 `key.properties`：

```properties
storeFile=keystore/yujian-release.jks
storePassword=******
keyAlias=yujian
keyPassword=******
```

路径相对于 `flutter_app\android\`。`key.properties`、`*.jks`、`*.keystore` 已被忽略，不会入库。

## 6. 在新机器上重建工具链

1. 解压 Flutter SDK 到 `D:\DESKTOP\ProWeb\tooling\flutter`（使其包含 `bin\flutter.bat`）。
2. 安装 JDK 17 到 `C:\Program Files\Java\jdk-17`。
3. 安装 Android 命令行工具到
   `D:\DESKTOP\ProWeb\tooling\android-sdk\cmdline-tools\latest`，然后执行：

   ```cmd
   scripts\setup-android-sdk.cmd
   ```

   该脚本非交互接受许可并安装 Platform 36、Build-Tools 36、platform-tools，可重复执行。
4. 执行 `scripts\set-user-env.cmd`，然后新开 cmd 窗口。

## 7. 行尾约定

`.editorconfig` 要求 `end_of_line = crlf`。脚手架工具可能写出 LF，因此提供：

```cmd
node scripts\normalize-crlf.mjs flutter_app\android scripts
node scripts\normalize-crlf.mjs --check flutter_app\android scripts
```

`--check` 模式不写文件，仅校验行尾，可用于后续 CI。
无扩展名文件（如 `android\gradlew`）会被有意跳过，以保留 POSIX 脚本所需的 LF。


## 8. 数据库：开发用 H2，交付用 MySQL 8

先说清一件事：**APK 不直接连数据库**。它只通过 HTTP 访问后端，
所以"数据存在哪"是后端 Spring profile 决定的，不是客户端决定的。

| profile | 存储 | 位置 | 用途 |
| --- | --- | --- | --- |
| `dev`（默认） | H2 文件库 | `backend\server\data\yujian.mv.db` | 本机开发、随手跑通，不需要装任何数据库 |
| `prod` | MySQL 8 | `application-prod.yml` 的 `MYSQL_URL` | 交付、演示、真正用上关系型数据库 |

### 8.1 本机统一使用 3306 上的 MySQL 容器

本机只保留一套数据库：docker compose 里的 `mysql` 服务，映射到 `3306`。
它带 `restart: unless-stopped`，Docker Desktop 一起动它就跟着起来，不用每次手动 up。

```cmd
rem 首次、或手动停过之后执行一次
docker compose -f backend\docker-compose.yml up -d mysql

rem 后端直接连它（默认就是 127.0.0.1:3306）
scripts\run-server-mysql.cmd
```

开发机上原本还装过一个原生 MySQL 8.2 服务（`MySQL82`，
`C:\Program Files\MySQL\MySQL Server 8.2`），它同样抢 `3306`，目前已经**停用**，
避免两个 MySQL 争同一个端口。若哪天要重新启用它，先 `docker compose -f backend\docker-compose.yml stop mysql`，
或把容器端口错开：`set MYSQL_PORT=3307 && docker compose -f backend\docker-compose.yml up -d mysql`。

开发用账号（生产必须全部换掉）：

| 账号 | 口令 | 用途 |
| --- | --- | --- |
| `root` | `yujian_root_password` | 只给 `scripts\init-mysql.cmd` 建库用 |
| `yujian` | `yujian_dev_password` | 后端连接（`prod` profile） |
| `operator` | `Operator12345` | 运营管理台管理员，启动时自动引导 |

`init-mysql.cmd` 只做 `CREATE DATABASE IF NOT EXISTS` / `CREATE USER IF NOT EXISTS` /
`GRANT`，且与 `backend\docker-compose.yml` 的默认值一致
（库 `yujian_travel`、账号 `yujian`）。重复执行不会丢数据。

### 8.2 切库之后必须知道的三件事

1. **数据不迁移**：H2 文件库与 MySQL 是两个互不相通的存储，
   `ddl-auto: update` 只建表，不会把 H2 里的账号 / 行程搬过去；
2. **运营账号要重建**：MySQL 侧由 `ADMIN_USERNAME` / `ADMIN_PASSWORD`
   在启动时重新引导（两个启动脚本都已写好开发用默认值）；
3. **端口别打架**：`run-server-dev.cmd` 与 `run-server-mysql.cmd` 都监听 8080，
   同一时间只能开一个；docker compose 的 `server` 服务同样占 8080，
   所以本机开发时**只用 compose 起 mysql**，不要 `docker compose up` 起全套。

## 9. 管理台容器与 `/api` 反代

管理台镜像的 Nginx 配置在 `backend/admin/nginx.conf`，Dockerfile 会把它安装到
`/etc/nginx/conf.d/default.conf`。容器内：

```text
/api/  → http://server:8080
/      → SPA 路由回落 index.html
/healthz → 200 ok（compose 的 admin 健康检查）
```

因此浏览器访问 `http://localhost:5173` 时，管理台默认的 `/api` 请求会由 Nginx
转发给同一 compose 网络里的 `server` 服务，不需要在前端写死宿主机地址，也不会暴露
第三方 AK 或 MCP 地址。
