/**
 * mcp-server-12306 的协议替身（本地验证用）。
 *
 * 为什么需要它：真机/真网络环境里我们用官方镜像
 *   docker run -d -p 8000:8000 drfccv/mcp-server-12306:latest
 * 但 CI 或离线环境不一定能拉镜像。这个替身只做一件事：**按同样的 MCP 协议说话**，
 * 因此可以验证后端 MCP 客户端（握手 → 会话头 → tools/call → SSE/JSON 解析 → 降级）
 * 是否正确，而不需要真的连上 12306。
 *
 * 用法：node scripts/mock-12306-mcp.mjs       （默认 8000 端口）
 *
 * 它故意做两件"刁难客户端"的事：
 *   1. tools/call 用 text/event-stream 返回，验证客户端的 SSE 分支；
 *   2. 缺少 Mcp-Session-Id 时返回 404，验证客户端会重新握手并重试一次。
 * 它返回的车次是固定样例数据，绝不能被当成真实余票。
 */
import { createServer } from 'node:http'

const PORT = Number(process.env.MCP_PORT ?? 8000)
const SESSION = 'mock-session-' + Math.random().toString(36).slice(2, 10)

const SAMPLES = {
  '郑州|洛阳': [
    ['G1903', '郑州东', '洛阳龙门', '08:20', '08:56', '00:36', { business: '有', first_class: '12', second_class: '有' }],
    ['G2205', '郑州东', '洛阳龙门', '09:35', '10:12', '00:37', { business: '3', first_class: '有', second_class: '有' }],
    ['K177', '郑州', '洛阳', '10:04', '11:56', '01:52', { hard_sleeper: '有', hard_seat: '有' }],
  ],
  '郑州|开封': [
    ['G1560', '郑州东', '开封北', '07:40', '08:02', '00:22', { first_class: '有', second_class: '有' }],
    ['C2901', '郑州东', '开封北', '08:15', '08:41', '00:26', { second_class: '有' }],
  ],
  '郑州|焦作': [
    ['C2905', '郑州东', '焦作', '07:52', '08:37', '00:45', { second_class: '有' }],
  ],
}

/** 只做"城市名匹配"，够模拟器与单元验证用；真实解析由官方 MCP 服务负责。 */
function pickTrains(from, to) {
  const key = Object.keys(SAMPLES).find(
    (candidate) => from.includes(candidate.split('|')[0]) && to.includes(candidate.split('|')[1]),
  )
  return key ? SAMPLES[key] : []
}

function payloadFor(args) {
  const from = String(args.from_station ?? '')
  const to = String(args.to_station ?? '')
  const trainDate = String(args.train_date ?? '')
  const rows = pickTrains(from, to)
  return {
    success: true,
    from_station: from,
    to_station: to,
    train_date: trainDate,
    count: rows.length,
    trains: rows.map(([trainNo, fromStation, toStation, start, arrive, duration, seats]) => ({
      train_no: trainNo,
      from_station: fromStation,
      from_station_code: 'MOCK',
      to_station: toStation,
      to_station_code: 'MOCK',
      start_time: start,
      arrive_time: arrive,
      duration,
      seats,
    })),
    notice: '协议替身返回的样例数据，不是真实余票',
  }
}

function callResult(id, args) {
  return {
    jsonrpc: '2.0',
    id,
    result: {
      content: [{ type: 'text', text: JSON.stringify(payloadFor(args)) }],
      isError: false,
    },
  }
}

function sse(body) {
  return 'event: message\ndata: ' + JSON.stringify(body) + '\n\n'
}

const server = createServer((req, res) => {
  if (req.method === 'GET' && req.url.startsWith('/health')) {
    res.writeHead(200, { 'Content-Type': 'application/json' })
    res.end(JSON.stringify({ status: 'ok', transport: 'streamable-http', stations: 3382, sessions: 1 }))
    return
  }
  if (req.method === 'GET' && req.url.startsWith('/schema/tools')) {
    res.writeHead(200, { 'Content-Type': 'application/json' })
    res.end(JSON.stringify({ tools: [{ name: 'query-tickets' }, { name: 'query-ticket-price' }] }))
    return
  }
  if (req.method !== 'POST' || !req.url.startsWith('/mcp')) {
    res.writeHead(404, { 'Content-Type': 'application/json' })
    res.end(JSON.stringify({ error: 'not found' }))
    return
  }

  let raw = ''
  req.on('data', (chunk) => {
    raw += chunk
  })
  req.on('end', () => {
    let message = null
    try {
      message = raw ? JSON.parse(raw) : null
    } catch {
      res.writeHead(400, { 'Content-Type': 'application/json' })
      res.end(JSON.stringify({ jsonrpc: '2.0', error: { code: -32700, message: 'parse error' } }))
      return
    }
    const method = message?.method ?? ''
    const id = message?.id ?? null

    if (method === 'initialize') {
      res.writeHead(200, { 'Content-Type': 'application/json', 'Mcp-Session-Id': SESSION })
      res.end(JSON.stringify({
        jsonrpc: '2.0',
        id,
        result: {
          protocolVersion: '2025-06-18',
          capabilities: { tools: { listChanged: false } },
          serverInfo: { name: 'mock-12306', version: '0.0.1' },
        },
      }))
      return
    }

    if (method.startsWith('notifications/')) {
      res.writeHead(202)
      res.end()
      return
    }

    if (req.headers['mcp-session-id'] !== SESSION) {
      // 会话缺失/过期：真实实现也会这样返回，用来逼客户端重新握手并重试一次。
      res.writeHead(404, { 'Content-Type': 'application/json' })
      res.end(JSON.stringify({ jsonrpc: '2.0', id, error: { code: -32001, message: 'session not found' } }))
      return
    }

    if (method === 'tools/call') {
      const name = message?.params?.name
      if (name !== 'query-tickets' && name !== 'query-ticket-price') {
        res.writeHead(200, { 'Content-Type': 'application/json' })
        res.end(JSON.stringify({ jsonrpc: '2.0', id, error: { code: -32602, message: 'unknown tool ' + name } }))
        return
      }
      res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-store' })
      res.end(sse(callResult(id, message?.params?.arguments ?? {})))
      return
    }

    res.writeHead(200, { 'Content-Type': 'application/json' })
    res.end(JSON.stringify({ jsonrpc: '2.0', id, error: { code: -32601, message: 'method not found: ' + method } }))
  })
})

server.listen(PORT, () => {
  console.log('[mock-12306] MCP ready at http://localhost:' + PORT + '/mcp  (session=' + SESSION + ')')
  console.log('[mock-12306] 样例数据仅用于协议验证，不是真实余票。')
})

