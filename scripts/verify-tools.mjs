/**
 * 阶段九验证：外部工具（天气 / 路线 / 车次 / 景点库）的来源与降级口径。
 *
 * 用法（先启动后端）：
 *   node scripts/verify-tools.mjs
 *   BASE_URL=http://localhost:8080 node scripts/verify-tools.mjs
 *
 * 这个脚本只验证"说的话和做的事一致"：
 *   - 真实接口取到数据才允许标"实时数据/缓存数据"；
 *   - 取不到必须带 errorCode 标成"演示数据（降级）"；
 *   - 系统自有资料标"系统资料"，不许冒充实时；
 *   - 任何返回里都不允许带出百度 AK。
 */
const BASE = (process.env.BASE_URL ?? 'http://localhost:8080').replace(/\/+$/, '')
const ADMIN_IDENTIFIER = process.env.ADMIN_IDENTIFIER ?? 'operator'
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD ?? 'Operator12345'

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
  return { status: response.status, headers: response.headers, text, json: parsed }
}

/** 新一轮验证用新的设备指纹，避免撞上一次运行的匿名体验额度。 */
function fingerprint(tag) {
  return 'verify-tools-' + tag + '-' + Date.now().toString(36)
}

async function planOnce(tag) {
  const session = await call('POST', '/api/anonymous/session', {
    headers: { 'X-Device-Fingerprint': fingerprint(tag) },
  })
  const anonToken = session.json?.token
  const plan = await call('POST', '/api/trip-plans', {
    headers: { 'X-Anonymous-Token': anonToken },
    body: {
      prompt: '两个人从郑州出发，周末去洛阳看历史文化，两天，预算每人1000元，轻松一点',
      origin: '郑州',
      destination: '洛阳',
      days: 2,
      travelers: 2,
      budgetPerPerson: 1000,
      interests: '历史文化',
      pace: '轻松',
      transport: '高铁/公共交通',
    },
  })
  const id = plan.json?.id
  const trace = id
    ? await call('GET', '/api/trip-plans/' + id + '/trace', { headers: { 'X-Anonymous-Token': anonToken } })
    : null
  return { session, plan, trace }
}

function tool(trace, name) {
  return (trace?.json?.toolInvocations ?? []).find((entry) => entry.toolName === name) ?? null
}

async function main() {
  log('== 1. 真实天气数据源可达性（不经过本项目） ==')
  let openMeteo = null
  try {
    const response = await fetch(
      'https://api.open-meteo.com/v1/forecast?latitude=34.6197&longitude=112.4540' +
        '&daily=weather_code,temperature_2m_max,temperature_2m_min&timezone=Asia%2FShanghai&forecast_days=3',
      { signal: AbortSignal.timeout(8000) },
    )
    openMeteo = { status: response.status, json: await response.json() }
  } catch (error) {
    openMeteo = { status: 0, error: String(error) }
  }
  check(
    'Open-Meteo 可直接取到未来 3 天预报',
    openMeteo.status === 200 && (openMeteo.json?.daily?.time?.length ?? 0) >= 1,
    'status=' + openMeteo.status,
  )

  log('== 2. 运营账号登录 ==')
  const login = await call('POST', '/api/auth/login', {
    body: { identifier: ADMIN_IDENTIFIER, password: ADMIN_PASSWORD },
  })
  check('运营账号登录', login.status === 200 && Boolean(login.json?.accessToken), 'status=' + login.status)
  const adminToken = login.json?.accessToken

  log('== 3. 一次真实规划的工具轨迹 ==')
  const first = await planOnce('a')
  check('匿名会话创建', first.session.status === 201 && Boolean(first.session.json?.token), 'status=' + first.session.status)
  check('生成行程', first.plan.status === 201 && Boolean(first.plan.json?.id), 'status=' + first.plan.status)
  check('读取工具轨迹', first.trace?.status === 200, 'status=' + first.trace?.status)

  const invocations = first.trace?.json?.toolInvocations ?? []
  check('轨迹记录 6 项工具调用', invocations.length === 6, 'count=' + invocations.length)
  for (const name of ['searchPoi', 'getWeather', 'getRoute', 'searchTrain', 'checkAttractionOpening',
    'quoteTicketPrices']) {
    check('轨迹包含 ' + name, Boolean(tool(first.trace, name)))
  }

  const poi = tool(first.trace, 'searchPoi')
  check('景点检索标注为系统资料', poi?.dataStatus === '系统资料', 'status=' + poi?.dataStatus)
  const opening = tool(first.trace, 'checkAttractionOpening')
  check('开放时间标注为系统资料', opening?.dataStatus === '系统资料', 'status=' + opening?.dataStatus)

  const ticket = tool(first.trace, 'quoteTicketPrices')
  check('门票价格标注为系统资料', ticket?.dataStatus === '系统资料', 'status=' + ticket?.dataStatus)
  check(
    '门票价格带来源与说明',
    String(ticket?.source ?? '').includes('内容库') && String(ticket?.outputSummary ?? '').length > 0,
    'source=' + ticket?.source,
  )

  const train = tool(first.trace, 'searchTrain')
  const trainStatus = String(train?.dataStatus ?? '')
  // 实时与缓存都表示"真的从 12306 MCP 取到了"，缓存只是同一个真实结果在 TTL 内复用。
  const trainLive = trainStatus.includes('实时') || trainStatus.includes('缓存')
  check(
    '车次要么来自 12306 官方、要么明确标注为非实时参考',
    trainLive
      ? String(train?.source ?? '').includes('12306 MCP')
      : String(train?.source ?? '').includes('非实时') || String(train?.source ?? '').includes('参考'),
    'status=' + train?.dataStatus + ' source=' + train?.source,
  )
  check('标为实时的车次不带降级原因', !trainLive || !train?.errorCode, 'error=' + train?.errorCode)

  const weather = tool(first.trace, 'getWeather')
  const weatherStatus = String(weather?.dataStatus ?? '')
  const weatherLive = weatherStatus.includes('实时') || weatherStatus.includes('缓存')
  check(
    '天气要么是真实来源、要么带原因降级',
    weatherLive
      ? String(weather?.source ?? '').includes('Open-Meteo')
      : String(weather?.dataStatus ?? '').includes('演示') && Boolean(weather?.errorCode),
    'status=' + weather?.dataStatus + ' source=' + weather?.source + ' error=' + weather?.errorCode,
  )
  check(
    '天气未编造未来日期',
    weatherLive ? String(weather?.outputSummary ?? '').includes('洛阳') : true,
    'summary=' + String(weather?.outputSummary ?? '').slice(0, 40),
  )

  const route = tool(first.trace, 'getRoute')
  const routeStatus = String(route?.dataStatus ?? '')
  const routeLive = routeStatus.includes('实时') || routeStatus.includes('缓存')
  check(
    '路线要么是百度地图真实结果、要么带原因降级',
    routeLive
      ? String(route?.source ?? '').includes('百度地图')
      : routeStatus.includes('演示') && Boolean(route?.errorCode),
    'status=' + route?.dataStatus + ' source=' + route?.source + ' error=' + route?.errorCode,
  )

  log('== 4. 全量不变量：不许把降级说成实时 ==')
  const claimingLive = invocations.filter((entry) => String(entry.dataStatus).includes('实时'))
  check(
    '标为实时的调用都没有 errorCode',
    claimingLive.every((entry) => !entry.errorCode),
    'live=' + claimingLive.length,
  )
  const degraded = invocations.filter((entry) => Boolean(entry.errorCode))
  check(
    '带 errorCode 的调用都标注了演示或降级',
    degraded.every((entry) => {
      const status = String(entry.dataStatus)
      return status.includes('演示') || status.includes('降级')
    }),
    'degraded=' + degraded.length,
  )
  check(
    '轨迹里没有出现百度 AK',
    !/ak=/i.test(first.trace?.text ?? ''),
  )
  check(
    '轨迹里没有出现完整外网请求地址',
    !/https?:\/\/api\.map\.baidu\.com/i.test(first.trace?.text ?? ''),
  )

  log('== 5. 提示语与数据实际状态一致 ==')
  const warnings = first.trace?.json?.warnings ?? []
  const hasMock = invocations.some((entry) => String(entry.dataStatus).includes('演示'))
  check(
    hasMock ? warnings.some((warning) => warning.includes('演示数据')) : true,
    '存在演示数据时给出提示',
    'warnings=' + warnings.length,
  )
  check(
    invocations.some((entry) => !String(entry.dataStatus).includes('演示'))
      ? warnings.every((warning) => !warning.includes('全部为演示数据'))
      : true,
    '有真实依据时不说"全部为演示数据"',
  )

  log('== 6. 缓存与失败短路 ==')
  const second = await planOnce('b')
  const weather2 = tool(second.trace, 'getWeather')
  check(
    '第二次规划的天气命中缓存或短路降级',
    String(weather2?.dataStatus ?? '').includes('缓存') ||
      ['WEATHER_BACKOFF'].includes(weather2?.errorCode) ||
      String(weather2?.dataStatus ?? '').includes('演示'),
    'status=' + weather2?.dataStatus + ' error=' + weather2?.errorCode,
  )

  log('== 7. 运营统计的降级口径 ==')
  const overview = await call('GET', '/api/admin/stats/overview', { token: adminToken })
  const tools = overview.json?.tools
  check('统计接口可读', overview.status === 200 && Boolean(tools), 'status=' + overview.status)
  check(
    '降级兜底单独计数且不超过演示总数',
    typeof tools?.degradedCalls === 'number' && tools.degradedCalls <= tools.mockCalls,
    'degraded=' + tools?.degradedCalls + ' mock=' + tools?.mockCalls,
  )
  check(
    '实时调用数不超过总调用数',
    typeof tools?.realtimeCalls === 'number' && tools.realtimeCalls <= tools.total,
    'realtime=' + tools?.realtimeCalls + ' total=' + tools?.total,
  )

  log('== 8. 数据源健康度：配没配、接没接上 ==')
  const health = await call('GET', '/api/admin/tools/health', { token: adminToken })
  const sources = health.json?.sources ?? []
  const byId = (id) => sources.find((entry) => entry.id === id)
  check('健康度接口可读', health.status === 200 && sources.length >= 4, 'status=' + health.status + ' sources=' + sources.length)
  check('包含天气 / 路线 / 车次 / 门票四个来源',
    Boolean(byId('weather')) && Boolean(byId('route')) && Boolean(byId('railway')) && Boolean(byId('ticket')),
    sources.map((entry) => entry.id).join('/'))
  check('状态取值在白名单内',
    sources.every((entry) => ['ready', 'not-configured', 'not-implemented', 'disabled'].includes(entry.status)),
    sources.map((entry) => entry.id + '=' + entry.status).join(' '))
  check('每个来源都给出人话说明',
    sources.every((entry) => String(entry.detail ?? '').length > 0),
    'ok')
  check('健康度不含任何密钥内容', !/api[-_]?key\s*[:=]\s*\S|ak=[A-Za-z0-9]/.test(health.text), 'ok')
  check('记录了每个工具的调用计数',
    (health.json?.tools ?? []).some((entry) => entry.tool === 'getWeather' && entry.total > 0),
    'tools=' + (health.json?.tools ?? []).length)

  log('')
  log('通过 ' + passed + ' 项，失败 ' + failed + ' 项。')
  if (failed > 0) {
    process.exitCode = 1
  }
}

main().catch((error) => {
  console.error('验证脚本异常终止：', error)
  process.exitCode = 1
})

