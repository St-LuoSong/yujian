/**
 * 阶段十验证：12306 MCP 分层接入（协议 + 端到端 + 不泄露）。
 *
 * 前置：
 *   1. 启动 MCP 服务（二选一）：
 *        node scripts/mock-12306-mcp.mjs                       ← 协议替身
 *        docker run -d -p 8000:8000 drfccv/mcp-server-12306:latest   ← 官方镜像
 *   2. 让后端指向它并启用 12306：
 *        set RAILWAY_PROVIDER=12306-mcp
 *        set RAILWAY_MCP_URL=http://localhost:8000/mcp
 *        scripts\run-server-dev.cmd
 *   3. node scripts/verify-railway-mcp.mjs
 *
 * 验证的是"职责分层有没有真的做到"：
 * 车次只在 MCP 服务里查，Spring Boot 只是调用方，APK 既拿不到 MCP 地址也拿不到任何凭证；
 * 取不到时必须带 errorCode 降级，而不是把参考时刻表说成实时车次。
 */
const BASE = (process.env.BASE_URL ?? 'http://localhost:8080').replace(/\/+$/, '')
const MCP = process.env.RAILWAY_MCP_URL ?? 'http://localhost:8000/mcp'
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

async function mcp(message, session) {
  const headers = {
    'Content-Type': 'application/json',
    Accept: 'application/json, text/event-stream',
  }
  if (session) headers['Mcp-Session-Id'] = session
  const response = await fetch(MCP, { method: 'POST', headers, body: JSON.stringify(message) })
  const text = await response.text()
  return { status: response.status, session: response.headers.get('mcp-session-id'), text }
}

async function main() {
  log('== 1. MCP 服务可达性 ==')
  let health = null
  try {
    const response = await fetch(MCP.replace(/\/mcp$/, '/health'), { signal: AbortSignal.timeout(8000) })
    health = { status: response.status, json: await response.json() }
  } catch (error) {
    health = { status: 0, error: String(error) }
  }
  check('MCP 服务 /health 可读', health.status === 200 && Boolean(health.json?.status), 'status=' + health.status)
  if (health.status !== 200) {
    log('')
    log('请先启动 MCP 服务：node scripts/mock-12306-mcp.mjs 或 docker run -d -p 8000:8000 drfccv/mcp-server-12306:latest')
    process.exitCode = 1
    return
  }

  log('== 2. MCP 协议握手与会话 ==')
  // 查询日期必须落在 12306 的预售窗口内，否则官方接口会直接拒绝。
  const probeDate = new Date(Date.now() + 2 * 86400000)
    .toLocaleDateString('sv-SE', { timeZone: 'Asia/Shanghai' })
  const init = await mcp({
    jsonrpc: '2.0',
    id: 1,
    method: 'initialize',
    params: {
      protocolVersion: '2025-06-18',
      capabilities: {},
      clientInfo: { name: 'verify-railway-mcp', version: '0.0.1' },
    },
  })
  check('initialize 成功', init.status === 200 && init.text.includes('serverInfo'), 'status=' + init.status)
  const session = init.session
  check('服务端下发会话头', Boolean(session), 'session=' + (session ? 'yes' : 'no'))

  // 官方镜像用 400 拒绝没有会话头的调用，协议替身用 404。后端对这两种状态都会重新握手并重试一次，
  // 所以这里只断言"被拒绝"，不把具体状态码写死。
  const noSession = await mcp({
    jsonrpc: '2.0',
    id: 2,
    method: 'tools/call',
    params: { name: 'query-tickets', arguments: { from_station: '郑州', to_station: '洛阳', train_date: probeDate } },
  })
  check('缺少会话头会被拒绝（后端据此重新握手）', noSession.status >= 400 && noSession.status < 500, 'status=' + noSession.status)

  const ticketCall = await mcp(
    {
      jsonrpc: '2.0',
      id: 3,
      method: 'tools/call',
      params: { name: 'query-tickets', arguments: { from_station: '郑州', to_station: '洛阳', train_date: probeDate } },
    },
    session,
  )
  const sseData = ticketCall.text
    .split(/\r?\n/)
    .filter((line) => line.startsWith('data:'))
    .map((line) => line.slice(5).trim())
    .filter(Boolean)
  check(
    'tools/call 以 SSE 返回且能解析',
    ticketCall.status === 200 && sseData.length > 0,
    'events=' + sseData.length,
  )
  let payload = null
  let payloadError = ''
  try {
    const envelope = JSON.parse(sseData[0])
    payload = JSON.parse(envelope.result.content[0].text)
  } catch (error) {
    payloadError = String(error)
  }
  check(
    '车次内容可解析',
    payload?.success === true && Array.isArray(payload.trains),
    payload ? 'trains=' + payload.trains.length + ' count=' + payload.count : 'parse failed: ' + payloadError,
  )

  log('== 3. 后端到 MCP 的端到端链路 ==')
  const fingerprint = 'verify-railway-' + Date.now().toString(36)
  const session0 = await call('POST', '/api/anonymous/session', {
    headers: { 'X-Device-Fingerprint': fingerprint },
  })
  const anonToken = session0.json?.token
  check('创建匿名会话', session0.status === 201 && Boolean(anonToken), 'status=' + session0.status)

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
  check('生成行程', plan.status === 201 && Boolean(plan.json?.id), 'status=' + plan.status)

  const trace = await call('GET', '/api/trip-plans/' + plan.json?.id + '/trace', {
    headers: { 'X-Anonymous-Token': anonToken },
  })
  check('读取工具轨迹', trace.status === 200, 'status=' + trace.status)

  const train = (trace.json?.toolInvocations ?? []).find((entry) => entry.toolName === 'searchTrain')
  check('存在车次调用记录', Boolean(train))
  const status = String(train?.dataStatus ?? '')
  const configured = Boolean(train) && !['RAILWAY_MCP_NOT_CONFIGURED', 'RAILWAY_BACKOFF'].includes(train?.errorCode)
  if (configured) {
    // 余票变化快，实时车次走 30 分钟短缓存；命中缓存说明刚才那次真实调用仍在
    // 有效期内，而不是降级。只认“实时”会让这个脚本在第二次运行时假失败。
    check(
      '车次是 12306 官方实时数据或它的短缓存',
      status.includes('实时') || status.includes('缓存'),
      'status=' + status
    )
    check('车次来源指向 12306 MCP', String(train?.source ?? '').includes('12306 MCP'), 'source=' + train?.source)
    check('车次摘要包含真实车次号', /[GDCKTZ]?\d{1,4}/.test(String(train?.outputSummary ?? '')), 'summary=' + String(train?.outputSummary ?? '').slice(0, 60))
    check('余票信息不承诺代购', !String(train?.outputSummary ?? '').includes('已购票'), 'ok')
  } else {
    check('未启用 12306 MCP 时给出明确降级原因', Boolean(train?.errorCode), 'error=' + train?.errorCode)
    log('  提示：后端当前未启用 12306 MCP（RAILWAY_PROVIDER/RAILWAY_MCP_URL 未生效），本轮只验证了降级口径。')
  }

  log('== 4. 分层边界：客户端与响应都不该看到 MCP ==')
  check('轨迹响应不含 MCP 地址', !trace.text.includes('localhost:8000') && !trace.text.includes(MCP), 'ok')
  check('轨迹响应不含 12306 会话头', !trace.text.toLowerCase().includes('mcp-session-id'), 'ok')
  check('行程响应不含 MCP 地址', !String(plan.text).includes('localhost:8000'), 'ok')

  log('== 5. 数据源健康度面板 ==')
  const login = await call('POST', '/api/auth/login', {
    body: { identifier: ADMIN_IDENTIFIER, password: ADMIN_PASSWORD },
  })
  const adminToken = login.json?.accessToken
  const tools = await call('GET', '/api/admin/tools/health', { token: adminToken })
  const railwayLine = (tools.json?.sources ?? []).find((entry) => entry.id === 'railway')
  check('健康度接口可读', tools.status === 200 && Array.isArray(tools.json?.sources), 'status=' + tools.status)
  check('健康度包含跨城车次来源', Boolean(railwayLine), 'provider=' + railwayLine?.provider)
  check('健康度不含任何密钥内容', !/api[-_]?key|ak=|token/i.test(tools.text), 'ok')
  const attempts = (tools.json?.tools ?? []).map((entry) => entry.tool)
  check('健康度记录了每个工具的最近状态', attempts.includes('searchTrain'), 'tools=' + attempts.join(','))

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

