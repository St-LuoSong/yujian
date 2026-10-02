/**
 * 阶段十一验证：大模型到底有没有真的在跑（最小化调用）。
 *
 * 用法（先启动后端）：
 *   node scripts\verify-llm.mjs
 *   BASE_URL=http://localhost:8080 node scripts\verify-llm.mjs
 *
 * 这个脚本只花 **一次** 真实 LLM 调用，用来回答一个问题：
 * "这份方案是模型生成的，还是 Mock 兜底的？"
 *
 * 其余断言（供应商是否启用、配置是否就绪、密钥有没有泄漏）都不消耗 token。
 * 失败时会打印该供应商最近一次的错误原因，便于直接定位是密钥、额度还是网络。
 */
const BASE = (process.env.BASE_URL ?? 'http://localhost:8080').replace(/\/+$/, '')
const ADMIN_IDENTIFIER = process.env.ADMIN_IDENTIFIER ?? 'operator'
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD ?? 'Operator12345'

const MOCK_ENGINES = ['mock', 'mock-fallback', 'demo']

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

/** 一次真实规划 + 读取工具轨迹。整个过程只触发一次模型调用。 */
async function planOnce() {
  const session = await call('POST', '/api/anonymous/session', {
    headers: { 'X-Device-Fingerprint': 'verify-llm-' + Date.now().toString(36) },
  })
  const anonToken = session.json?.token
  const plan = await call('POST', '/api/trip-plans', {
    headers: { 'X-Anonymous-Token': anonToken },
    body: {
      prompt: '郑州出发去洛阳两天，看历史文化，节奏轻松',
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

function describeAttempts(report) {
  const attempts = report?.attempts ?? []
  if (!attempts.length) {
    return '（该供应商还没有任何调用记录）'
  }
  return attempts
    .map((entry) => entry.engine + ': ok=' + entry.successCount + ' fail=' + entry.failureCount +
      (entry.lastError ? ' lastError=' + entry.lastError : ''))
    .join(' | ')
}

log('== 1. 供应商配置（不消耗 token） ==')
const login = await call('POST', '/api/auth/login', {
  body: { identifier: ADMIN_IDENTIFIER, password: ADMIN_PASSWORD },
})
const adminToken = login.json?.accessToken
check('运营账号登录', login.status === 200 && Boolean(adminToken), 'status=' + login.status)

const report = adminToken ? await call('GET', '/api/admin/llm/providers', { token: adminToken }) : null
check('供应商状态接口可读', report?.status === 200 && Boolean(report.json), 'status=' + report?.status)

const llmEnabled = report?.json?.llmEnabled === true
check('LLM 总开关已打开', llmEnabled, 'llmEnabled=' + report?.json?.llmEnabled)

const order = report?.json?.selectionOrder ?? []
check('至少有一家可用供应商进入尝试顺序', order.length > 0, 'selectionOrder=' + JSON.stringify(order))

const first = (report?.json?.providers ?? []).find((provider) => provider.id === order[0])
check(
  '排序第一的供应商已启用且配置完整',
  Boolean(first) && first.enabled === true && first.configured === true,
  first ? first.id + ' enabled=' + first.enabled + ' configured=' + first.configured + ' model=' + first.model : 'not found',
)

check('供应商响应里不含任何密钥', !/sk-[A-Za-z0-9]|apiKey|api-key|Bearer /i.test(report?.text ?? ''), 'ok')

log('')
log('== 2. 一次真实规划（消耗一次模型调用） ==')
const { session, plan, trace } = await planOnce()
check('匿名会话创建', session.status === 201 && Boolean(session.json?.token), 'status=' + session.status)
check('生成行程', plan.status === 201 && Boolean(plan.json?.id), 'status=' + plan.status + ' dataStatus=' + plan.json?.dataStatus)

const engine = String(trace?.json?.engine ?? '')
check('读取工具轨迹', trace?.status === 200 && Boolean(trace?.json), 'status=' + trace?.status)
check(
  '规划引擎是真实模型，不是 Mock 兜底',
  engine.length > 0 && !MOCK_ENGINES.some((mock) => engine.includes(mock)),
  'engine=' + engine,
)
check('方案未被标注为 AI 降级', !String(trace?.json?.dataStatus ?? '').includes('AI 降级'), 'dataStatus=' + trace?.json?.dataStatus)

// 调用统计必须在规划**之后**再取一次：第一次取的是上一轮的状态，
// 早先的版本就是在这里读到"无记录"，把真正的失败原因藏掉了。
const after = adminToken ? await call('GET', '/api/admin/llm/providers', { token: adminToken }) : null
if (first) {
  const snapshot = (after?.json?.attempts ?? []).find((entry) => entry.engine === first.id)
  log('  --   ' + first.id + ' 调用统计  ->  ' +
    (snapshot ? 'ok=' + snapshot.successCount + ' fail=' + snapshot.failureCount +
      (snapshot.lastError ? ' lastError=' + snapshot.lastError : '') : '本轮之前无记录'))
  check('供应商健康度记录了本轮调用', Boolean(snapshot), snapshot ? 'engine=' + snapshot.engine : 'no snapshot')
}

log('')
log('通过 ' + passed + ' 项，失败 ' + failed + ' 项。')
if (failed > 0) {
  log('排查提示：供应商调用统计 -> ' + describeAttempts(after?.json))
  log('若 lastError 指向密钥或额度，请检查 scripts\\local.env 里的 LLM 配置。')
  process.exitCode = 1
}
