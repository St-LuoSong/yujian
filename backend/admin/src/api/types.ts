export interface UserSummary {
  id: string
  username: string
  email: string | null
  emailVerified: boolean
  roles: string[]
}

export interface AuthResponse {
  accessToken: string
  refreshToken: string
  expiresIn: number
  user: UserSummary
}

export interface PoiView {
  id: string
  name: string
  city: string
  category: string
  imageUrl: string | null
  description: string
  ticketFrom: number
  duration: string
  suitability: string | null
  weatherTip: string | null
  dataStatus: string
  imageCredit: string | null
  sourceUrl: string | null
  /** 百度 BD09 坐标，运营台维护；为空表示这张卡片暂时不会在行程地图上打点。 */
  lng: number | null
  lat: number | null
  published: boolean
  sortOrder: number
  createdAt: string
  updatedAt: string
  /**
   * 配图合规状态，由服务端现算（不落库）：
   * MISSING 缺图 / PLACEHOLDER 占位示例图 / UNLICENSED 来源未登记 / REGISTERED 已登记。
   */
  imageStatus: string
  /** 状态的中文说法，直接显示，避免前端再维护一份映射。 */
  imageStatusLabel: string
  /** 必须补齐的项；已登记时为空数组。 */
  imageGaps: string[]
}

export interface ImageUploadResult {
  fileName: string
  url: string
  relativeUrl: string
  format: string
  sizeBytes: number
  width: number
  height: number
}

export interface PoiInput {
  name: string
  city: string
  category: string
  imageUrl: string | null
  description: string
  ticketFrom: number
  duration: string
  suitability: string | null
  weatherTip: string | null
  dataStatus: string
  imageCredit: string | null
  sourceUrl: string | null
  lng: number | null
  lat: number | null
  published: boolean
  sortOrder: number
}

/**
 * 景点坐标解析结果。
 *
 * trusted=false 时 lng/lat 一定为空 —— 后端不给出"看起来能用"的坐标，
 * 界面因此也没有机会把一个城市中心当成景点坐标存下来。
 */
export interface GeocodePreview {
  query: string
  cityHint: string | null
  lng: number | null
  lat: number | null
  level: string
  confidence: number
  trusted: boolean
  source: string
  message: string
}

export interface DailyPoint {
  date: string
  plans: number
  toolCalls: number
}

export interface ProviderLine {
  id: string
  displayName: string
  model: string
  priority: number
  enabled: boolean
  configured: boolean
  successCount: number
  failureCount: number
  lastError: string | null
  lastDurationMs: number | null
}

export interface LlmStats {
  enabled: boolean
  lastSuccessfulEngine: string | null
  selectionOrder: string[]
  providers: ProviderLine[]
}

export interface Overview {
  generatedAt: string
  users: { total: number; verified: number; newLast7Days: number }
  trips: { total: number; registered: number; anonymous: number; newLast7Days: number; avgDays: number }
  content: { publishedPois: number; totalPois: number; openFeedback: number }
  tools: {
    total: number
    succeeded: number
    failed: number
    successRate: number
    /** 标记为演示数据的调用数（含降级兜底）。 */
    mockCalls: number
    realtimeCalls: number
    cachedCalls: number
    /** 演示数据的子集：真实数据源不可用后由兜底数据顶上的调用数。 */
    degradedCalls: number
  }
  shares: { total: number; active: number; views: number }
  daily: DailyPoint[]
  llm: LlmStats
}

export interface ToolSourceLine {
  id: string
  displayName: string
  provider: string
  /**
   * ready：已配置可用；not-configured：缺少配置；
   * not-implemented：尚未接入适配器；disabled：当前是 mock 模式。
   */
  status: 'ready' | 'not-configured' | 'not-implemented' | 'disabled' | string
  detail: string
}

export interface ToolAttempt {
  tool: string
  total: number
  success: number
  failure: number
  lastStatus: string | null
  lastErrorCode: string | null
  lastDurationMs: number
  lastAt: string | null
}

/** 外部数据源健康度：回答"接上了没有"，与 Overview 的"用了多少"互补。 */
export interface ToolHealth {
  generatedAt: string
  mode: string
  sources: ToolSourceLine[]
  tools: ToolAttempt[]
}

export interface FeedbackView {
  id: string
  category: string
  content: string
  contact: string | null
  page: string | null
  status: 'OPEN' | 'HANDLED' | 'IGNORED' | string
  handlerNote: string | null
  fromRegisteredUser: boolean
  createdAt: string
  updatedAt: string
}

export interface OperationLog {
  id: string
  actorId: string | null
  actorName: string | null
  action: string
  target: string
  detail: string | null
  createdAt: string
}

export interface ProviderReport {
  llmEnabled: boolean
  activeEngine: string | null
  selectionOrder: string[]
  providers: Array<{
    id: string
    displayName: string
    model: string
    priority: number
    enabled: boolean
    configured: boolean
    baseUrl: string
    timeoutSeconds: number
    temperature: number
  }>
  attempts: Array<{
    engine: string
    successCount: number
    failureCount: number
    lastDurationMs: number
    lastStatus: string
    lastError: string | null
    lastChangedAt: string
  }>
}

export interface PromptVersion {
  id: string | null
  version: string
  systemPrompt: string
  note: string | null
  active: boolean
  createdAt: string
}

export interface PromptVersionInput {
  version: string
  systemPrompt: string
  note: string | null
}

export interface SupportedDemoScenario {
  key: string
  displayName: string
  matchHint: string
  sampleJson: string
}

export interface DemoScenario {
  id: string
  scenarioKey: string
  matchKey: string
  name: string
  payloadJson: string
  note: string | null
  enabled: boolean
  updatedAt: string
}

export interface DemoScenarioCatalog {
  supported: SupportedDemoScenario[]
  scenarios: DemoScenario[]
}

export interface DemoScenarioInput {
  name: string
  payloadJson: string
  note: string | null
  enabled: boolean
}

export interface CommunityPostView {
  id: string
  authorName: string
  authorAvatarKey: string | null
  tripPlanId: string | null
  title: string
  content: string
  city: string
  tags: string | null
  visibility: string
  status: string
  imageUrls: string[]
  likeCount: number
  viewCount: number
  likedByMe: boolean
  createdAt: string
  publishedAt: string | null
  moderationNote: string | null
}

export interface CommunityPostPage {
  items: CommunityPostView[]
  page: number
  size: number
  total: number
  hasMore: boolean
}

export interface CommunityReportView {
  id: string
  postId: string
  reporterName: string
  reason: string
  status: string
  handlerNote: string | null
  createdAt: string
  handledAt: string | null
}

export interface CommunityReportPage {
  items: CommunityReportView[]
  page: number
  size: number
  total: number
  hasMore: boolean
}
