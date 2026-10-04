# T47：旅记评论、自定义头像、APK 双通道更新

日期：2026-10-03（Asia/Shanghai）

三件事一起做、一起上线：评论与头像都要动 `user_account` / `community_post`，
而调试包更新通道要动 `app_release`，合成一版迁移比拆成三次部署少两个中间态。

## 一、旅记评论

### 数据

新表 `community_comment`：`post_id` / `user_id` / `content(500)` / `status` /
时间戳，两级索引（按旅记取列表、按用户查发言）。
`community_post` 增 `comment_count`。

**为什么计数是冗余列**：信息流一页要渲染十几张卡片，每张都去 `count(*)` 一次
评论表就是 N+1。写/删/隐藏评论时同步维护，并且只允许向非负方向收敛
（`Math.max(0, ...)`）—— 一个因为并发少减了一次的计数，不该变成负数。

**为什么评论不做楼中楼**：层级、折叠规则、通知口径是独立的一块工作量。
首版把"能不能评论"做扎实，比做一个半成品的嵌套结构更有价值。

### 行为

| 动作 | 规则 |
| --- | --- |
| 看评论 | 公开只读，规则跟详情页一致：未过审的旅记只有作者能看到它的评论 |
| 发评论 | 必须登录；只能评论"公开且已过审"的旅记；内容 trim 后 1—500 字 |
| 删评论 | 只有作者本人。删别人的评论返回 404 而不是 403 —— 403 等于告诉对方"这个 id 是真的" |
| 隐藏评论 | 运营端专用，不删行（`HIDDEN`），保留复核与申诉的余地 |
| 删旅记 | 先按 `post_id` 批量删评论再删旅记：评论表有外键，漏掉这一步会直接抛约束冲突 |

**通知**：有人评论时给旅记作者发站内消息，自己评论自己不发电——那只会变成一条
自己看自己的噪音。消息里只带评论前 60 字，回看全文应该点进旅记。

## 二、自定义头像

`user_account` 增 `avatar_url`。与既有的 `avatar_key` 是两种来源：

- 有 `avatar_url` → 显示上传的照片；
- 否则回落到 `avatar_key` 的预设图案，再否则回落到用户名首字。

**优先级只写在一处**：`lib/core/widgets/user_avatar.dart`。每个调用点各写一遍
if/else 的话，早晚会有一处把"已经换了照片"的用户又画成一朵花。

### 存相对路径，不存完整 URL

服务端存 `/media/xxx.jpg`，客户端显示前用 `AppConfig.resolveMediaUrl` 补成
这台设备能访问的地址。把上传时那个主机名写进数据库，换域名或换端口之后，
所有历史头像都会失效。

### 接口与边界

```text
POST   /api/auth/me/avatar   （multipart，与旅记图片共用重编码去 EXIF 的链路）
DELETE /api/auth/me/avatar
PATCH  /api/auth/me          （avatarKey 非空时清空 avatarUrl）
```

规则：**选了预设图案就等于放弃自定义头像**；`avatarKey` 为空表示"没选预设"，
这时自定义头像保持不动 —— 改个昵称不该把头像一起弄丢。换头像后旧文件会被删掉，
但只删本服务 `/media/` 里的文件。

UI 上同一时刻只呈现一种选择方式：有照片就只给"更换/移除"，没有照片才显示预设图案
那排按钮。同时摆着两种，"点完这两个会得到什么"就说不清了。

## 三、APK 双通道更新

### 为什么必须分通道

正式包要求"必须由发布证书签名"，而调试包永远做不到这一点（debug keystore
每台机器都不一样）。只有一条通道的话，要么为了收调试包把正式包的签名约束
一起废掉，要么就永远没法给调试机推送新包。

`app_release` 增 `channel`（`RELEASE` / `DEBUG`），唯一约束从
`(package_name, version_code)` 改为 `(package_name, channel, version_code)`。

| 通道 | 签名校验 |
| --- | --- |
| `RELEASE` | 必须签名有效 + 证书命中 `allowed-certificate-sha256` 白名单 |
| `DEBUG` | 只要求"文件是一份有效签名"，不比对证书白名单（包名与 versionCode 仍然校验） |

客户端的通道由原生侧上报的 `debuggable` 决定，服务端 `channel` 缺省为 `RELEASE`
—— 不带这个参数的旧版 APK 必须继续拿到正式通道的包，否则会被推到一份签名不同、
根本装不上去的包上。

### 强制更新的两条规则

```text
1. 低于该版本发布时配置的 minimumSupportedVersionCode  → 强制
2. 版本跨度 > app.app-release.forced-update-gap（默认 5）→ 强制
```

第 2 条是自动兜底：落后十几个版本的用户手上那份 APK，接口契约、数据状态语义
甚至登录流程都可能已经跟服务端对不上了，再让他"自愿"继续用，只会换来一串
解释不清的报错。

### 客户端

- 设置页新增「检查更新」→ `CheckUpdateScreen`：显示当前版本、最新版本、状态，
  强制更新时说明**为什么**强制（低于最低支持版本 / 落后过多），而不是只丢一句
  "必须更新"。
- 启动时的自动检查（`AppUpdateGate`）保持不变，两者共用同一套接口与判定。

### 关闭运行时可改的服务器地址

按 2026-10-03 的决定，设置页里的「服务器地址」入口已移除，后端地址只在打包时
通过 `--dart-define=API_BASE_URL=...` 固定：

```bash
flutter build apk --debug --no-pub \
  --dart-define=API_BASE_URL=https://your-host/api
```

`AppConfig.resolve()` 的优先级本来就是"编译期常量 > 本地存储"，所以移除入口后
不会出现"改过又自己变回去"的情况。`server_endpoint_screen.dart` 暂时保留在仓库里
（未被引用），需要恢复运行时可配时把它接回设置页即可。

## 四、验证

| 项目 | 结果 |
| --- | --- |
| `flutter analyze` | 0 issue |
| `flutter test` | 162 项全通过（新增评论渲染回归测试） |
| `mvn -o -B test` | 128 项全通过（新增评论 3 项、头像 2 项、更新通道 2 项） |
| `npm run build`（admin） | 通过 |
| 云端 Flyway V3 | 已应用，`flyway_schema_history` 版本 3，success=1 |
| 云端数据 | 迁移前后 user=3 / trip=3 / poi=30 未变 |
| 云端接口 | `/api/community/posts/{id}/comments` 返回空页；详情带 `authorAvatarUrl`；`/api/app-releases/check?channel=DEBUG` 正常 |

## 五、上线记录（2026-10-03 22:09 CST）

```text
Successfully validated 4 migrations
Current version of schema `yujian_travel`: 2
Migrating schema `yujian_travel` to version "3 - comments avatar and release channel"
Successfully applied 1 migration, now at version v3 (0.229s)
Started YujianTravelApplication in 11.005 seconds
```

- 后端 JAR：旧包备份在服务器 `/tmp/yujian-travel-server.prev.jar`
- 管理台改为 `Dockerfile.cloud`：直接搬本地构建好的 `dist`，不在服务器上跑
  `npm install`（一次 npm 源抖动不该让部署失败）
- 四个容器全部 healthy

## 六、还没做

1. **运营端的评论管理界面**：后端 `GET/PATCH /api/admin/community/posts/{id}/comments`
   与 `/comments/{id}` 已经就绪，管理台还没有对应页面。举报处理里目前看不到评论内容。
2. 发布一条调试包并真机走一遍"检查更新 → 下载 → 覆盖安装"的完整链路。
3. 头像上传的真机目视复核（相册权限、大图裁剪表现）。
