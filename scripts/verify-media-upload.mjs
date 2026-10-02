/**
 * 景点配图上传验证：权限、格式校验、静态访问、路径穿越防护。
 *
 * 用法：
 *   node scripts/verify-media-upload.mjs
 *   BASE_URL=http://localhost:8080 UPLOAD_DIR=D:/DESKTOP/ProWeb/backend/server/data/uploads node scripts/verify-media-upload.mjs
 *
 * 脚本会在结束后删除自己上传的图片和创建的验证景点。
 */
import { existsSync, unlinkSync } from 'node:fs'
import { join } from 'node:path'

const BASE = (process.env.BASE_URL ?? 'http://localhost:8080').replace(/\/+$/, '')
const ADMIN_IDENTIFIER = process.env.ADMIN_IDENTIFIER ?? 'operator'
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD ?? 'Operator12345'
const UPLOAD_DIR = process.env.UPLOAD_DIR ?? new URL('../backend/server/data/uploads/', import.meta.url).pathname.replace(/^\//, '')
const POI_ID = 'media-verify-poi'

let passed = 0
let failed = 0
const log = (message) => console.log(message)

function check(name, condition, detail = '') {
  if (condition) {
    passed += 1
    log('  OK   ' + name + (detail ? '  ->  ' + detail : ''))
  } else {
    failed += 1
    log('  FAIL ' + name + (detail ? '  ->  ' + detail : ''))
  }
}

/** 1x1 GIF89a：格式固定，作为“合法图片”的最小样本。 */
const GIF_BYTES = Buffer.from([
  0x47, 0x49, 0x46, 0x38, 0x39, 0x61,
  0x01, 0x00, 0x01, 0x00,
  0x80, 0x00, 0x00,
  0xff, 0xff, 0xff,
  0x00, 0x00, 0x00,
  0x2c, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
  0x02, 0x02, 0x44, 0x01, 0x00,
  0x3b,
])

async function json(method, path, { token, body } = {}) {
  const headers = { Accept: 'application/json' }
  if (body !== undefined) headers['Content-Type'] = 'application/json'
  if (token) headers.Authorization = 'Bearer ' + token
  const response = await fetch(BASE + path, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  })
  const text = await response.text()
  let parsed = null
  try {
    parsed = text ? JSON.parse(text) : null
  } catch {
    parsed = null
  }
  return { status: response.status, headers: response.headers, text, json: parsed }
}

async function upload(token, bytes, fileName, contentType) {
  const form = new FormData()
  form.append('file', new Blob([bytes], { type: contentType }), fileName)
  const headers = { Accept: 'application/json' }
  if (token) headers.Authorization = 'Bearer ' + token
  const response = await fetch(BASE + '/api/admin/media/images', { method: 'POST', headers, body: form })
  const text = await response.text()
  let parsed = null
  try {
    parsed = text ? JSON.parse(text) : null
  } catch {
    parsed = null
  }
  return { status: response.status, json: parsed, text }
}

async function main() {
  log('== 1. 上传接口的权限边界 ==')
  const anonymous = await upload(null, GIF_BYTES, 'anon.gif', 'image/gif')
  check('未登录上传被拒绝', anonymous.status === 401, 'status=' + anonymous.status)

  const adminLogin = await json('POST', '/api/auth/login', {
    body: { identifier: ADMIN_IDENTIFIER, password: ADMIN_PASSWORD },
  })
  check('运营账号登录', adminLogin.status === 200 && Boolean(adminLogin.json?.accessToken), 'status=' + adminLogin.status)
  const adminToken = adminLogin.json?.accessToken

  const suffix = Date.now().toString().slice(-8)
  const register = await json('POST', '/api/auth/register', {
    body: { username: 'media' + suffix, email: 'media' + suffix + '@yujian.local', password: 'Media12345' },
  })
  const userToken = register.json?.accessToken
  check('普通用户注册', register.status === 201 && Boolean(userToken), 'status=' + register.status)

  const asUser = await upload(userToken, GIF_BYTES, 'user.gif', 'image/gif')
  check('普通用户上传返回 403', asUser.status === 403, 'status=' + asUser.status)

  log('== 2. 格式校验（只看文件头魔数） ==')
  const disguised = await upload(adminToken, Buffer.from('这不是图片，只是文本', 'utf8'), 'fake.jpg', 'image/jpeg')
  check('文本伪装成 .jpg 被拒绝', disguised.status === 415, 'status=' + disguised.status + ' code=' + disguised.json?.code)

  const empty = await upload(adminToken, Buffer.alloc(0), 'empty.png', 'image/png')
  check('空文件被拒绝', empty.status === 400, 'status=' + empty.status + ' code=' + empty.json?.code)

  log('== 3. 正常上传与静态访问 ==')
  const ok = await upload(adminToken, GIF_BYTES, 'scenic-shot.gif', 'image/gif')
  check('ADMIN 上传成功', ok.status === 201 && Boolean(ok.json?.fileName), 'status=' + ok.status)
  check('文件名由服务端生成（不使用原始名）',
    Boolean(ok.json?.fileName) && !ok.json.fileName.includes('scenic') && ok.json.fileName.endsWith('.gif'),
    'fileName=' + ok.json?.fileName)
  check('返回尺寸与格式', ok.json?.format === 'gif' && ok.json?.width === 1 && ok.json?.height === 1,
    JSON.stringify({ w: ok.json?.width, h: ok.json?.height, f: ok.json?.format }))
  check('返回可写入内容的绝对地址', String(ok.json?.url ?? '').includes('/media/'), 'url=' + ok.json?.url)

  const fileName = ok.json?.fileName
  const fileOnDisk = join(UPLOAD_DIR, fileName ?? 'missing')
  check('文件确实落盘', existsSync(fileOnDisk), fileOnDisk)

  const fetched = await fetch(BASE + ok.json.relativeUrl)
  check('静态资源可公开读取', fetched.status === 200, 'status=' + fetched.status)
  check('响应类型为图片', String(fetched.headers.get('content-type') ?? '').includes('image/gif'),
    'type=' + fetched.headers.get('content-type'))
  await fetched.arrayBuffer()

  log('== 4. 路径穿越防护 ==')
  const traversal = await fetch(BASE + '/media/..%2F..%2Fapplication.yml')
  check('路径穿越请求被拒绝', traversal.status >= 400, 'status=' + traversal.status)
  const encoded = await fetch(BASE + '/media/%2e%2e%2f%2e%2e%2fapplication.yml')
  check('编码后的穿越请求同样被拒绝', encoded.status >= 400, 'status=' + encoded.status)

  log('== 5. 上传的图片可以直接用于景点内容 ==')
  await json('DELETE', '/api/admin/pois/' + POI_ID, { token: adminToken })
  const created = await json('POST', '/api/admin/pois', {
    token: adminToken,
    body: {
      name: '配图上传验证景点',
      city: '郑州',
      category: '城市漫游',
      imageUrl: ok.json.url,
      description: '用于验证运营台上传的图片能进入游客端内容。',
      ticketFrom: 0,
      duration: '1小时',
      suitability: '验证用例',
      weatherTip: '不适用',
      dataStatus: '演示数据',
      imageCredit: '自动化脚本上传的测试图',
      sourceUrl: null,
      published: true,
      sortOrder: 998,
    },
  })
  check('使用上传地址创建景点', created.status === 201 && created.json?.imageUrl === ok.json.url,
    'status=' + created.status)

  const publicPois = await json('GET', '/api/pois')
  const published = publicPois.json?.find((item) => item.id === created.json?.id)
  check('游客端读到同一张图片地址', published?.imageUrl === ok.json.url, 'imageUrl=' + published?.imageUrl)

  const uploadedByOther = await fetch(BASE + published.imageUrl.replace(BASE, ''))
  check('游客端图片地址可直接加载', uploadedByOther.status === 200, 'status=' + uploadedByOther.status)
  await uploadedByOther.arrayBuffer()

  const logs = await json('GET', '/api/admin/logs?limit=50', { token: adminToken })
  check('上传动作进入操作日志',
    logs.json?.some((row) => row.action === 'MEDIA_UPLOAD' && row.target === 'media:' + fileName),
    'rows=' + (logs.json?.length ?? 0))

  log('== 6. 清理验证数据 ==')
  const removedPoi = await json('DELETE', '/api/admin/pois/' + created.json.id, { token: adminToken })
  check('删除验证景点', removedPoi.status === 204, 'status=' + removedPoi.status)
  if (existsSync(fileOnDisk)) {
    unlinkSync(fileOnDisk)
  }
  check('删除验证图片', !existsSync(fileOnDisk), fileOnDisk)
}

main()
  .catch((error) => {
    failed += 1
    console.error('验证脚本异常：', error)
  })
  .finally(() => {
    log('')
    log('结果：通过 ' + passed + ' 项，失败 ' + failed + ' 项')
    if (failed > 0) process.exitCode = 1
  })
