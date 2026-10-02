/**
 * 阶段七端到端验证：内容库、管理 API、反馈、操作日志、公开分享页。
 *
 * 用法：
 *   node scripts/verify-phase7.mjs
 *   BASE_URL=http://localhost:8080 ADMIN_IDENTIFIER=operator ADMIN_PASSWORD=... node scripts/verify-phase7.mjs
 *
 * 脚本会真实写入数据并在结束时清理自己创建的景点；注册的验证账号保留在数据库中，
 * 用户名带时间戳，便于在管理台复盘。
 */
const BASE = (process.env.BASE_URL ?? 'http://localhost:8080').replace(/\/+$/, '');
const ADMIN_IDENTIFIER = process.env.ADMIN_IDENTIFIER ?? 'operator';
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD ?? 'Operator12345';

let passed = 0;
let failed = 0;
const log = (message) => console.log(message);

function check(name, condition, detail = '') {
  if (condition) {
    passed += 1;
    log('  OK   ' + name + (detail ? '  ->  ' + detail : ''));
  } else {
    failed += 1;
    log('  FAIL ' + name + (detail ? '  ->  ' + detail : ''));
  }
}

async function call(method, urlPath, options = {}) {
  const headers = { Accept: 'application/json', ...(options.headers ?? {}) };
  if (options.body !== undefined) headers['Content-Type'] = 'application/json';
  if (options.token) headers.Authorization = 'Bearer ' + options.token;
  const response = await fetch(BASE + urlPath, {
    method,
    headers,
    body: options.body === undefined ? undefined : JSON.stringify(options.body),
  });
  const text = await response.text();
  let json = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    json = null;
  }
  return { status: response.status, headers: response.headers, text, json };
}

async function main() {
  log('== 1. 未登录可访问的内容与健康检查 ==');
  const health = await call('GET', '/actuator/health');
  check('健康检查', health.status === 200 && health.json?.status === 'UP', 'status=' + health.status);

  const pois = await call('GET', '/api/pois');
  check('GET /api/pois 来自内容库', pois.status === 200 && Array.isArray(pois.json) && pois.json.length >= 4,
    'count=' + (pois.json?.length ?? 0));
  check('景点响应仍保持 APK 契约',
    Boolean(pois.json?.[0]?.id && pois.json?.[0]?.name && 'ticketFrom' in pois.json[0] && 'dataStatus' in pois.json[0]),
    'keys=' + Object.keys(pois.json?.[0] ?? {}).join(','));

  const home = await call('GET', '/api/home');
  check('GET /api/home 读到同一批景点',
    home.status === 200 && home.json?.featuredPois?.length === pois.json?.length,
    'featured=' + (home.json?.featuredPois?.length ?? 0));

  log('== 2. 匿名反馈 ==');
  const feedback = await call('POST', '/api/feedback', {
    body: { content: '阶段七验证反馈：龙门石窟的开放时间建议再核对一次。', category: '内容纠错', page: 'poi-detail' },
  });
  check('匿名提交反馈', feedback.status === 201 && feedback.json?.status === 'OPEN', 'id=' + feedback.json?.id);

  const feedbackTooLong = await call('POST', '/api/feedback', { body: { content: 'x'.repeat(1001) } });
  check('超长反馈被拒绝', feedbackTooLong.status === 400, 'status=' + feedbackTooLong.status);

  log('== 3. 管理台鉴权 ==');
  const anonymousAdmin = await call('GET', '/api/admin/stats/overview');
  check('未登录访问管理接口返回 401', anonymousAdmin.status === 401, 'status=' + anonymousAdmin.status);

  const login = await call('POST', '/api/auth/login', {
    body: { identifier: ADMIN_IDENTIFIER, password: ADMIN_PASSWORD },
  });
  check('运营账号登录', login.status === 200 && Boolean(login.json?.accessToken), 'status=' + login.status);
  const adminToken = login.json?.accessToken;
  if (!adminToken) {
    log('无法取得管理令牌，跳过后续管理用例。');
    return;
  }

  const me = await call('GET', '/api/auth/me', { token: adminToken });
  check('运营账号具备 ADMIN 角色', (me.json?.roles ?? []).includes('ADMIN'), 'roles=' + (me.json?.roles ?? []).join('/'));

  log('== 4. 景点内容管理 ==');
  const adminPois = await call('GET', '/api/admin/pois', { token: adminToken });
  check('管理端可列出全部景点', adminPois.status === 200 && adminPois.json.length >= 4,
    'count=' + (adminPois.json?.length ?? 0));
  check('管理端返回版权与来源字段',
    'imageCredit' in (adminPois.json?.[0] ?? {}) && 'sourceUrl' in (adminPois.json?.[0] ?? {}));

  const created = await call('POST', '/api/admin/pois', {
    token: adminToken,
    body: {
      name: '阶段七验证景点',
      city: '郑州',
      category: '城市漫游',
      imageUrl: 'https://example.com/verify.jpg',
      description: '仅用于自动化验证，脚本结束时会删除。',
      ticketFrom: 0,
      duration: '1小时',
      suitability: '验证用例',
      weatherTip: '不适用',
      dataStatus: '演示数据',
      imageCredit: '自动化脚本生成，无版权素材',
      sourceUrl: 'https://example.com/verify',
      published: true,
      sortOrder: 999,
    },
  });
  check('新增景点返回 201', created.status === 201 && Boolean(created.json?.id), 'id=' + created.json?.id);
  const createdId = created.json?.id;

  const poisAfterCreate = await call('GET', '/api/pois');
  check('上架后游客端立即可见', poisAfterCreate.json?.some((item) => item.id === createdId),
    'count=' + (poisAfterCreate.json?.length ?? 0));

  const unpublished = await call('PATCH', '/api/admin/pois/' + encodeURIComponent(createdId) + '/publish', {
    token: adminToken,
    body: { published: false },
  });
  check('下架操作生效', unpublished.status === 200 && unpublished.json?.published === false,
    'published=' + unpublished.json?.published);

  const poisAfterUnpublish = await call('GET', '/api/pois');
  check('下架后游客端不可见', !poisAfterUnpublish.json?.some((item) => item.id === createdId));

  log('== 5. 运营统计、AI 供应商与操作日志 ==');
  const overview = await call('GET', '/api/admin/stats/overview', { token: adminToken });
  const stats = overview.json;
  check('统计接口可用', overview.status === 200 && Boolean(stats?.users && stats?.trips && stats?.tools),
    'status=' + overview.status);
  check('统计包含近 7 天趋势点', Array.isArray(stats?.daily) && stats.daily.length === 7,
    'points=' + (stats?.daily?.length ?? 0));
  check('统计含 AI 供应商四家',
    ['openai', 'deepseek', 'kimi', 'qwen'].every((id) => stats?.llm?.providers?.some((p) => p.id === id)),
    'providers=' + (stats?.llm?.providers ?? []).map((p) => p.id).join('/'));
  check('统计不含任何密钥字段', !/apiKey|api-key|secret/i.test(JSON.stringify(stats ?? {})));

  const providers = await call('GET', '/api/admin/llm/providers', { token: adminToken });
  check('供应商报告可用', providers.status === 200 && providers.json?.providers?.length === 4,
    'status=' + providers.status);
  check('供应商报告不泄露密钥', !/apiKey|sk-|secret/i.test(providers.text));

  const logs = await call('GET', '/api/admin/logs', { token: adminToken });
  check('操作日志记录了景点新增与下架',
    logs.status === 200
      && logs.json.some((row) => row.action === 'POI_CREATE' && row.target === 'poi:' + createdId)
      && logs.json.some((row) => row.action === 'POI_UNPUBLISH' && row.target === 'poi:' + createdId),
    'rows=' + (logs.json?.length ?? 0));

  const feedbackList = await call('GET', '/api/admin/feedback', { token: adminToken });
  check('反馈进入管理列表', feedbackList.status === 200 && feedbackList.json.some((row) => row.id === feedback.json.id),
    'count=' + (feedbackList.json?.length ?? 0));

  const handled = await call('PATCH', '/api/admin/feedback/' + feedback.json.id, {
    token: adminToken,
    body: { status: 'HANDLED', handlerNote: '已核对景区官网开放时间' },
  });
  check('反馈可被处理', handled.status === 200 && handled.json?.status === 'HANDLED');

  log('== 6. 只读分享页（比赛演示第 17 步） ==');
  const anonToken0 = await call('POST', '/api/anonymous/session', { headers: { 'X-Device-Fingerprint': 'phase7-verify' } });
  check('创建匿名体验会话', anonToken0.status === 201 && Boolean(anonToken0.json?.token), 'status=' + anonToken0.status);
  // 匿名令牌只在响应体中返回（不像 trip-plans 会同时写响应头）。
  const anonToken = anonToken0.json?.token;

  const trip = await call('POST', '/api/trip-plans', {
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
  });
  check('匿名生成行程', trip.status === 201 && Boolean(trip.json?.id), 'id=' + trip.json?.id);
  const tripId = trip.json?.id;
  // 带已有匿名会话创建行程时，服务端不会再下发新令牌，沿用原会话即可。
  const newAnonToken = trip.headers.get('x-anonymous-token') ?? anonToken;

  const suffix = Date.now().toString().slice(-8);
  const register = await call('POST', '/api/auth/register', {
    body: { username: 'verify' + suffix, email: 'verify' + suffix + '@yujian.local', password: 'Verify12345' },
  });
  check('注册验证账号', register.status === 201 && Boolean(register.json?.accessToken), 'status=' + register.status);
  const userToken = register.json?.accessToken;

  const merge = await call('POST', '/api/auth/merge-anonymous', {
    token: userToken,
    headers: { 'X-Anonymous-Token': newAnonToken },
  });
  check('匿名行程合并到账号', merge.status === 200 && merge.json?.merged === true, JSON.stringify(merge.json));

  const accountTrips = await call('GET', '/api/trip-plans', { token: userToken });
  check('合并后行程归属账号', accountTrips.status === 200 && accountTrips.json.some((row) => row.id === tripId),
    'count=' + (accountTrips.json?.length ?? 0));

  const share = await call('POST', '/api/trip-plans/' + tripId + '/share', {
    token: userToken,
    body: { hideBudget: false, expireDays: 7 },
  });
  check('创建只读分享', share.status === 200 && Boolean(share.json?.token), 'url=' + share.json?.url);
  const shareToken = share.json?.token;

  const shareApi = await call('GET', '/api/trip-shares/' + shareToken);
  check('分享 JSON 接口免登录可读', shareApi.status === 200 && shareApi.json?.plan?.id === tripId,
    'status=' + shareApi.status);

  const sharePage = await call('GET', '/share/' + shareToken);
  const contentType = sharePage.headers.get('content-type') ?? '';
  check('分享页面免登录返回 HTML', sharePage.status === 200 && contentType.includes('text/html'),
    'status=' + sharePage.status + ' type=' + contentType);
  check('分享页面含行程标题', sharePage.text.includes(trip.json.title), 'title=' + trip.json.title);
  check('分享页面不含令牌与脚本注入', !sharePage.text.includes(shareToken) && !/<script/i.test(sharePage.text));
  check('分享页面声明只读与数据状态',
    sharePage.text.includes('只读分享') && sharePage.text.includes(trip.json.dataStatus),
    'status=' + trip.json.dataStatus);

  const missingShare = await call('GET', '/share/definitely-not-a-token');
  check('失效分享返回友好页面', missingShare.status === 404 && missingShare.text.includes('分享暂时打不开'),
    'status=' + missingShare.status);

  log('== 7. 清理验证数据 ==');
  const removed = await call('DELETE', '/api/admin/pois/' + encodeURIComponent(createdId), { token: adminToken });
  check('删除验证景点', removed.status === 204, 'status=' + removed.status);
  const finalPois = await call('GET', '/api/pois');
  check('游客端景点数量回到初始值', finalPois.json?.length === pois.json?.length,
    'before=' + pois.json?.length + ' after=' + finalPois.json?.length);

  log('== 8. 权限边界 ==');
  const userOnAdmin = await call('GET', '/api/admin/pois', { token: userToken });
  check('普通用户访问管理接口返回 403', userOnAdmin.status === 403, 'status=' + userOnAdmin.status);
}

main()
  .catch((error) => {
    failed += 1;
    console.error('验证脚本异常：', error);
  })
  .finally(() => {
    log('');
    log('结果：通过 ' + passed + ' 项，失败 ' + failed + ' 项');
    if (failed > 0) process.exitCode = 1;
  });
