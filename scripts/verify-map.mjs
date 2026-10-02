/**
 * 阶段十一验证：行程地图是不是真的画得出来。
 *
 * 用法（先启动后端）：
 *   node scripts\verify-map.mjs
 *   BASE_URL=http://localhost:8080 node scripts\verify-map.mjs
 *   PLAN_ID=<已有行程> node scripts\verify-map.mjs
 *
 * 为什么需要一份行程：地图快照的输入就是某一天的真实行程项，
 * 因此本脚本优先复用**已经存在**的行程；只有在一条都没有时才会新建一份
 * （那会花掉一次模型调用，脚本会明确打印出来）。
 *
 * 全部断言都不额外消耗地图配额以外的资源：底图取一次就会被服务端缓存，
 * 后面的断言都命中缓存。
 */
import { setTimeout as delay } from 'node:timers/promises'

const BASE = (process.env.BASE_URL ?? 'http://localhost:8080').replace(/[/]+$/, '')
const ADMIN_IDENTIFIER = process.env.ADMIN_IDENTIFIER ?? 'operator'
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD ?? 'Operator12345'
const PLAN_ID = process.env.PLAN_ID ?? ''

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

async function call(method, path, { token, headers = {}, body } = {}) {
  const merged = { Accept: 'application/json', ...headers }
  if (body !== undefined) merged['Content-Type'] = 'application/json'
  if (token) merged.Authorization = 'Bearer ' + token
  const response = await fetch(BASE + path, {
    method,
    headers: merged,
    body: body === undefined ? undefined : JSON.stringify(body),
  })
  const text = await response.text()
  let parsed = null
  try {
    parsed = text ? JSON.parse(text) : null
  } catch {
    parsed = null
  }
  return { status: response.status, text, json: parsed }
}

/** 优先复用已有行程，实在没有才新建一份（会消耗一次模型调用）。 */
async function ensurePlan(token) {
  if (PLAN_ID) {
    return { id: PLAN_ID, created: false }
  }
  const list = await call('GET', '/api/trip-plans', { token })
  const items = Array.isArray(list.json) ? list.json : []
  if (items.length > 0) {
    log('  --   复用已有行程 ' + items[0].id + '（' + (items[0].title ?? '') + '）')
    return { id: items[0].id, created: false }
  }
  log('  --   没有任何行程，新建一份用于验证（这次会花 1 次模型调用）')
  const created = await call('POST', '/api/trip-plans', {
    token,
    body: {
      prompt: '周末从郑州去洛阳看历史文化，一天，节奏轻松',
      origin: '郑州',
      destination: '洛阳',
      days: 1,
      travelers: 2,
      pace: '轻松',
      interests: '历史文化',
    },
  })
  return { id: created.json?.id ?? '', created: true, status: created.status }
}

const login = await call('POST', '/api/auth/login', {
  body: { identifier: ADMIN_IDENTIFIER, password: ADMIN_PASSWORD },
})
const token = login.json?.accessToken ?? ''
check('运营账号登录', login.status === 200 && token.length > 0, 'status=' + login.status)
if (!token) {
  log('')
  log('无法继续：请先启动后端并确认管理员账号可用。')
  process.exit(1)
}

const plan = await ensurePlan(token)
check('取得一份行程', Boolean(plan.id), 'id=' + plan.id + (plan.created ? '（新建）' : '（复用）'))
if (!plan.id) {
  log('')
  log('无法继续：没有得到行程 id。')
  process.exit(1)
}

// ---------------------------------------------------------------- 地图快照
const snapshot = await call('GET', '/api/trip-plans/' + plan.id + '/map?day=1', { token })
check('地图快照返回 200', snapshot.status === 200, 'status=' + snapshot.status)
const map = snapshot.json ?? {}
log('  --   dataStatus=' + map.dataStatus + ' source=' + map.source + ' fallback=' + map.fallback)
check('地图没有降级', map.fallback === false && map.imageUrl, 'fallback=' + map.fallback + ' message=' + (map.message ?? '无'))
check('返回了底图地址', typeof map.imageUrl === 'string' && map.imageUrl.startsWith('/api/map/image'), map.imageUrl ?? 'null')
check('底图地址带票据', typeof map.imageUrl === 'string' && map.imageUrl.includes('ticket='))

const viewport = map.viewport ?? {}
check(
  '视窗参数在合法区间',
  viewport.width >= 320 && viewport.width <= 1024 &&
    viewport.height >= 320 && viewport.height <= 1024 &&
    viewport.zoom >= 3 && viewport.zoom <= 19,
  viewport.width + 'x' + viewport.height + ' zoom=' + viewport.zoom,
)

const markers = Array.isArray(map.markers) ? map.markers : []
check('解析出至少一个可打点的站点', markers.length > 0, 'markers=' + markers.length)
check(
  '每个站点都带编号、标题与像素坐标',
  markers.every(
    (m) =>
      Number.isInteger(m.index) &&
      m.index >= 1 &&
      typeof m.title === 'string' &&
      m.title.length > 0 &&
      Number.isFinite(m.x) &&
      Number.isFinite(m.y),
  ),
)
check(
  '至少有编号 1 的站点落在画面内',
  markers.some((m) => m.index === 1 && m.inside === true),
)
check(
  '像素坐标没有飞出量级',
  markers.every((m) => Math.abs(m.x) < 5000 && Math.abs(m.y) < 5000),
  markers.map((m) => m.index + ':' + m.x + ',' + m.y).join(' '),
)
check(
  '折线点数与标记数一致',
  Array.isArray(map.polyline) && map.polyline.length === markers.length,
  'polyline=' + (map.polyline?.length ?? 0),
)
const unplaced = Array.isArray(map.unplaced) ? map.unplaced : []
check(
  '未打点的站点都带原因',
  unplaced.every((entry) => typeof entry.title === 'string' && typeof entry.reason === 'string' && entry.reason.length > 0),
  'unplaced=' + unplaced.length,
)
check(
  '标注了底图来源与局限',
  Array.isArray(map.attribution) && map.attribution.some((line) => line.includes('百度地图')),
  (map.attribution ?? []).join(' / '),
)

// ---------------------------------------------------------------- 底图字节
if (typeof map.imageUrl === 'string' && map.imageUrl.length > 0) {
  const first = await fetch(BASE + map.imageUrl)
  const bytes = Buffer.from(await first.arrayBuffer())
  check('底图请求返回 200', first.status === 200, 'status=' + first.status)
  check(
    '底图是真正的 PNG',
    bytes.length > 2000 && bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47,
    'bytes=' + bytes.length + ' type=' + first.headers.get('content-type'),
  )
  check('底图带缓存头', (first.headers.get('cache-control') ?? '').includes('max-age'), first.headers.get('cache-control') ?? '')


  // 篡改票据本身：改动签名内容后必须失效。
  const brokenTicket = map.imageUrl.replace('ticket=', 'ticket=tampered-')
  const forged = await fetch(BASE + brokenTicket)
  check('票据被改动即失效（403）', forged.status === 403, 'status=' + forged.status)

  // 篡改参数：票据只对签发时那一组参数有效，换一个缩放级别同样无效。
  const zoomPart = map.imageUrl.split('zoom=')[1].split('&')[0]
  const otherZoom = zoomPart === '4' ? '5' : '4'
  const tamperedUrl = map.imageUrl.split('zoom=' + zoomPart).join('zoom=' + otherZoom)
  const tampered = await fetch(BASE + tamperedUrl)
  check('换掉缩放级别后票据失效（403）', tampered.status === 403, 'status=' + tampered.status)

  // 同一张图再取一次：服务端命中缓存，字节数一致。
  await delay(120)
  const again = await fetch(BASE + map.imageUrl)
  const againBytes = Buffer.from(await again.arrayBuffer())
  check('重复取图命中缓存且内容一致', againBytes.length === bytes.length, 'bytes=' + againBytes.length)
}

const anonymous = await call('GET', '/api/trip-plans/' + plan.id + '/map?day=1')
check('未登录访问地图快照被拒绝（401）', anonymous.status === 401, 'status=' + anonymous.status)

const missing = await call('GET', '/api/trip-plans/00000000-0000-0000-0000-000000000000/map?day=1', { token })
check('不存在的行程返回 404', missing.status === 404, 'status=' + missing.status)

const badCenter = await call('GET', '/api/trip-plans/' + plan.id + '/map?day=1&center=abc', { token })
check('非法中心点返回 400', badCenter.status === 400, 'status=' + badCenter.status)

log('')
log('通过 ' + passed + ' 项，失败 ' + failed + ' 项。')
if (failed > 0) {
  log('排查提示：先看后端日志里的 "Static map unavailable" 与 "Geocode failed" 两行，')
  log('再确认 scripts/local.env 里的 BAIDU_MAP_AK 是否仍然有效、配额是否用尽。')
  process.exitCode = 1
}
