# 阶段八：景点配图上传

> 阶段名称：阶段八（运营台图片上传）
> 起因：内容维护不应该靠改后端代码或手填外链。
> 日期：2026-10-01（Asia/Shanghai）

## 1. 这一阶段解决什么

此前景点配图只能填一个 HTTP 地址。实际运营时，一条景点内容要配 1—3 张河南实拍图，
靠手填外链既麻烦又无法保证版权可追溯。

现在：**在管理台选中本地图片 → 上传 → 自动填回景点主图字段 → 保存后游客端立即生效。**

## 2. 服务端实现

| 文件 | 作用 |
| --- | --- |
| `config/AppProperties.Media` | `storage-dir` / `base-url` / `max-size-mb` / `max-dimension` |
| `service/MediaStorageService.java` | 魔数校验、尺寸校验、随机命名、落盘、地址生成 |
| `api/AdminMediaController.java` | `POST /api/admin/media/images`（仅 ADMIN） |
| `api/MediaModels.java` | 上传结果：绝对地址、相对地址、格式、体积、宽高 |
| `config/WebMvcConfig.java` | 把上传目录挂到只读的 `/media/**` |

`SecurityConfig` 中 `/media/**` 放开为公开只读，写入路径仍在 `/api/admin/**` 之下。

## 3. 安全设计（公开部署的必要条件，不是可选优化）

1. **文件名由服务端生成 UUID**，绝不使用客户端提供的文件名 —— 从根上消除路径穿越；
2. **类型只看文件头魔数**，不信任 `Content-Type` 与扩展名 —— 把文本改名为 `.jpg` 会被 415 拒绝；
3. **只读取像素尺寸、不解码整张图** —— 用 `ImageReader.getWidth/getHeight`，避免解压炸弹占满内存；
4. **尺寸与体积双上限** —— 默认 8MB、单边 6000 像素；
5. **只放行 JDK 原生可解析格式** —— JPEG / PNG / GIF，其余明确拒绝并给出可读原因；
6. **静态资源只读** —— `/media/**` 只提供文件读取，不暴露目录列表；路径穿越请求返回 400。

操作日志记录 `MEDIA_UPLOAD`，且**不记录原始文件名**（可能含个人信息），只记录尺寸与体积。

## 4. 管理台实现

- `api/http.ts` 新增 `upload()`，复用同一套 401 / 错误载荷处理，并刻意不手写 `Content-Type`（boundary 必须由浏览器生成）；
- `PoisView.vue` 的主图字段改为「预览 + 地址输入 + 上传按钮 + 清除」；
- 上传成功自动写回 `imageUrl`；上传失败在字段旁就地提示，不清空已有输入；
- 仍然可以直接粘贴外链，两种方式共存。

## 5. 配置与模拟器注意事项

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `MEDIA_STORAGE_DIR` | `./data/uploads` | 相对服务端工作目录，已被 `.gitignore` 忽略 |
| `MEDIA_BASE_URL` | 空 | 留空时按上传请求推导 |
| `MEDIA_MAX_SIZE_MB` | `8` | 应用层上限；Spring 的 multipart 上限另设为 10MB |
| `MEDIA_MAX_DIMENSION` | `6000` | 单边像素上限 |

> **模拟器和真机必须配置 `MEDIA_BASE_URL`。**
> 不配置时地址会推导成 `http://localhost:8080/media/...`，而模拟器里的 `localhost` 指向模拟器自身。
> 模拟器请用 `http://10.0.2.2:8080`，真机请用宿主机局域网 IP。

## 6. 验证证据

```text
mvn -q -o compile                        -> 编译通过
npm run build (admin)                    -> built in 304ms，PoisView chunk 9.53KB
node scripts/verify-media-upload.mjs     -> 通过 21 项，失败 0 项
```

`scripts/verify-media-upload.mjs` 覆盖的真实链路：

```text
1  未登录上传 401；普通用户上传 403；ADMIN 可上传
2  文本伪装成 .jpg 返回 415 MEDIA_TYPE_UNSUPPORTED；空文件返回 400 MEDIA_EMPTY
3  正常上传 201；文件名由服务端生成且不含原始名；返回 1x1 gif 尺寸；文件确实落盘
   GET /media/{name} 返回 200 且 Content-Type 为 image/gif
4  /media/..%2F..%2Fapplication.yml 与编码变体均返回 400
5  用上传地址创建景点 201 → 游客端 /api/pois 读到同一地址 → 该地址可直接加载
6  删除验证景点与验证图片，环境无残留
```

## 7. 已知遗留

| 级别 | 问题 | 说明 |
| --- | --- | --- |
| P1 | 没有缩略图 | 列表页直接加载原图；接入大量高清图后需要生成缩略图或接入对象存储 |
| P1 | 删除景点不会删除图片文件 | 目前没有引用计数，可能产生孤儿文件；管理台后续应提供"未引用素材"清理 |
| P2 | 不支持 WebP | JDK 原生 ImageIO 不支持，需要额外依赖；如要支持需评估 `webp-imageio` |
| P2 | 本地磁盘存储 | 多实例部署时需要换成对象存储或共享盘，接口层已隔离在 `MediaStorageService` |
| P2 | 无上传频率限制 | 仅 ADMIN 可上传，风险有限；公开部署前建议加限流 |

## 8. 下一阶段建议

1. **替换景点图片为河南实拍授权图**，并在管理台逐条补全版权与来源链接；
2. 增加"素材库"视图：查看已上传文件、占用量、是否被引用、批量清理孤儿文件；
3. 主题路线（走廊）管理，把硬编码的三条走廊也纳入内容库。
