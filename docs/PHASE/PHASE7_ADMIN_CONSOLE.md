# 阶段七：运营管理台真实化与只读分享页

> 阶段名称：阶段七（Vue 3 管理台真实化 + 公开分享页 + 运营数据接口）
> 目标：把"静态原型的运营台"推进为"能真实管理内容、能看到 AI 供应商健康度、能受理反馈"的系统，
> 并补齐比赛演示流程中"生成只读分享"这一步在浏览器里打不开的缺口。
> 日期：2026-10-01（Asia/Shanghai）

## 1. 为什么这一阶段做这两件事

交接摘要里挂着两个 P1：

1. **分享链接打不开**：`GET /api/trip-shares/{token}` 是公开的，但没有面向接收者的页面，比赛演示第 17 步只能停在"生成了链接"。
2. **管理台是静态原型**：`/api/admin/llm/providers` 已经就绪，管理台却只能显示演示数据和写死的图表。

这两件事都属于"系统已经做出来了但外部看不见"，对评委的可感知价值损失最大，因此优先补齐。

## 2. 服务端新增能力

### 2.1 景点内容库（内容从硬编码变为可管理）

此前 `/api/pois` 和 `/api/home` 直接读 `TravelCatalog` 里的四条硬编码记录，管理台改不了任何东西。
现在：

| 文件 | 作用 |
| --- | --- |
| `domain/PoiEntity.java` | 景点内容库实体，含图片、版权、来源链接、上架状态、排序权重 |
| `repository/PoiRepository.java` | 已上架 / 全部 / 按城市查询 |
| `service/PoiContentService.java` | 游客端只读已上架；管理台可读全部并增删改 |
| `service/PoiCatalogSeeder.java` | 首次启动播种三条示范走廊的四个景点，**只在表为空时执行** |
| `api/AdminPoiController.java` | `/api/admin/pois` 增删改查与上下架 |

关键约束：`TravelModels.Poi` 的字段与顺序**完全没有变化**，APK 不需要跟着改。
`id` 是业务主键（例如 `longmen`），更新内容时不改 id，因为行程文本、收藏和分享链接都引用它。

### 2.2 运营统计

`GET /api/admin/stats/overview`（ADMIN）返回：

```text
users    : total / verified / newLast7Days
trips    : total / registered / anonymous / newLast7Days / avgDays
content  : publishedPois / totalPois / openFeedback
tools    : total / succeeded / failed / successRate / mockCalls / realtimeCalls
shares   : total / active / views
daily    : 近 7 天，每天 plans 与 toolCalls
llm      : enabled / lastSuccessfulEngine / selectionOrder / 四家供应商健康度
```

统计实现刻意只查时间戳与计数，不把行程正文或工具输出读进内存；
"演示数据"和"实时数据"分列统计，避免把 Mock 说成真实调用。

### 2.3 游客反馈闭环

| 接口 | 鉴权 | 说明 |
| --- | --- | --- |
| `POST /api/feedback` | 公开（允许匿名） | 只保存内容、可选联系方式与来源页面 |
| `GET /api/admin/feedback` | ADMIN | 按状态筛选 |
| `PATCH /api/admin/feedback/{id}` | ADMIN | 更新处理状态与处理说明 |

服务端不采集设备标识，不要求真实姓名，联系方式是可选字段。

### 2.4 管理员操作日志

`OperationLog` 记录"谁在什么时候改了什么"，写入用 `REQUIRES_NEW`，主操作回滚时仍然留下失败痕迹。
`detail` 只保存人可读摘要，**绝不写入令牌、密码或第三方密钥**。

### 2.5 公开只读分享页

`GET /share/{token}`（公开）返回一份完整的品牌化 HTML 行程单：

- 接收者不需要登录、不需要安装 App；
- 隐藏预算时金额在服务端就已被置零，页面只显示"分享者已隐藏"；
- 所有文本（标题、节点名、描述、风险、来源）都做 HTML 转义，行程标题不能成为注入点；
- 页面不输出分享令牌本身，也不含任何 `<script>`；
- 失效或过期时返回 404/410 的友好页面，而不是 JSON 错误；
- 页面样式沿用 APK 的天青色板，风险提示只在左侧保留一条朱色细线，一屏内不铺满警示色。

`SecurityConfig` 相应放开 `/share/**` 与 `POST /api/feedback`。

## 3. Vue 3 管理台工程化

改造前：`src/App.vue` 单文件容纳布局、导航、总览和四个"待接入"占位页。

改造后：

```text
admin/src/
├── main.ts                  挂载 Pinia + Router
├── App.vue                  只保留 router-view
├── router/index.ts          路由、登录守卫、文档标题
├── layouts/AdminLayout.vue  侧边导航 + 顶栏 + 服务健康指示
├── views/
│   ├── LoginView.vue        管理员登录（校验 ADMIN 角色）
│   ├── OverviewView.vue     指标、趋势图、供应商降级顺序
│   ├── PoisView.vue         景点内容管理（搜索、抽屉表单、上下架、删除）
│   ├── AiRunsView.vue       供应商健康度、尝试记录、密钥零展示
│   ├── FeedbackView.vue     反馈受理
│   └── LogsView.vue         管理员操作日志
├── components/              DataState / MetricCard / TrendChart
├── api/                     token / http / endpoints / types
├── stores/session.ts        管理员会话（sessionStorage）
└── styles/                  tokens.css + admin.css（自研，无 UI 组件库）
```

设计决策：

- **不引入 UI 组件库**：界面由 `tokens.css` 与 `admin.css` 自研，避免默认组件库外观与品牌冲突；
- **令牌放 sessionStorage**：关闭标签页即失效，比 localStorage 少一份长期泄露面；
- **401 自动登出并跳登录**，登录接口自身不参与该逻辑（避免登录失败被当成会话失效）；
- **开发代理**：`vite.config.ts` 把 `/api` 与 `/share` 代理到 `localhost:8080`，前端不存后端地址；
- **ECharts 按需注册**：只注册 LineChart / Grid / Tooltip / Legend / CanvasRenderer。

## 4. 本轮验证证据

```text
mvn -q -o test                     -> 9 项后端单元测试通过
mvn -q -o compile                  -> 编译通过
npm run build (admin)              -> built in 291ms，入口 JS 105KB / gzip 40.8KB，总览页 485KB / gzip 162KB
node scripts/verify-phase7.mjs     -> 通过 39 项，失败 0 项
```

`scripts/verify-phase7.mjs` 覆盖的真实链路（不是 Mock 断言）：

```text
1  健康检查 200；GET /api/pois 返回 4 条内容库数据；响应键与 APK 契约一致；/api/home 同源
2  匿名提交反馈 201；超长内容 400
3  未登录访问管理接口 401；运营账号登录 200；角色 ADMIN/USER
4  新增景点 201 → 游客端立即可见（4→5）→ 下架 → 游客端不可见（回到 4）→ 删除 204
5  统计含 7 天趋势与四家供应商；统计与供应商报告均不含密钥
   操作日志记录 POI_CREATE 与 POI_UNPUBLISH；反馈可被处理为 HANDLED
6  匿名会话 → 生成行程 → 注册 → 合并匿名行程 → 创建分享
   分享 JSON 免登录可读；GET /share/{token} 返回 text/html;charset=UTF-8
   页面含行程标题与数据状态，不含令牌、不含 <script>；失效令牌返回友好 404 页面
7  删除验证景点后游客端数量回到初始值
8  普通用户访问管理接口 403
```

## 5. 运行期才暴露并已修复的问题

1. **健康检查一直是 503**：`spring.mail.host` 为空时 MailHealthIndicator 判定 DOWN。
   SMTP 是首版预留能力，已配置 `management.health.mail.enabled=false`。
2. **`.cmd` 脚本不能写中文注释**：cmd.exe 用 OEM 代码页读取批处理文件，UTF-8 中文注释会被当成命令执行。
   `scripts/run-server-dev.cmd` 已改为纯 ASCII 注释，并在文件头写明原因。
3. **cmd 的 `set VAR=value && ...` 会把尾随空格写进值**：导致管理员密码带上一个空格、登录 401。
   改为用启动脚本里的 `set "VAR=value"` 形式，避免再次踩坑。
4. **ECharts 全量引入让总览页首屏 1.03MB**：改为按需注册后降到 485KB（gzip 339KB → 162KB）。

## 6. 已知遗留

| 级别 | 问题 | 说明 |
| --- | --- | --- |
| P1 | 景点主图仍是 Unsplash 示例素材 | 服务端已在 `image_credit` 标注。**阶段八已补上管理台图片上传能力**，剩下的只是把实拍图传上去 |
| P1 | 主题路线（走廊）仍为硬编码 | 管理台导航里没有"路线管理"，因为服务端还没有对应实体 |
| P2 | 管理台没有分页 | 数据量按比赛演示规模设计，景点与反馈一次返回全部 |
| P2 | 反馈没有限流 | 匿名可提交，公开部署前需要加 IP 或会话级频率限制 |
| P2 | 管理台没有刷新令牌 | access token 过期后需要重新登录；对运营台可接受 |
| P2 | `fl_chart` / `timeline_tile` 已无调用点 | 已在 `THIRD_PARTY_NOTICES.md` 标注，建议随 APK 下一轮一起移除 |

## 7. 本地运行方式

```cmd
rem 终端 1：后端（内置 H2 + 运营账号 operator / Operator12345）
scripts\run-server-dev.cmd

rem 终端 2：管理台（http://localhost:5173）
cd admin
npm run dev
```

生产构建：

```cmd
cd admin
set "VITE_API_BASE=https://your-host/api"
npm run build
```

## 8. 下一阶段建议

1. **路线（走廊）管理**：新增 `CorridorEntity` 与 `/api/admin/routes`，把主题路线也纳入内容库；
2. **素材合规收口**：替换景点图片并逐条填写版权与来源链接；
3. **地图独立验证**：在接入百度地图 SDK 前，先做 Android 10+ 真机的地图显示、标记回传与无密钥降级验证；
4. **APK 依赖清理**：移除已无调用点的 `fl_chart` 与 `timeline_tile`，并重新构建 Release APK 验证。
