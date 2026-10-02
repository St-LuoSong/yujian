import { api } from './http'
import type {
  AuthResponse,
  CommunityPostPage,
  CommunityPostView,
  CommunityReportPage,
  CommunityReportView,
  DemoScenario,
  DemoScenarioCatalog,
  DemoScenarioInput,
  FeedbackView,
  GeocodePreview,
  ImageUploadResult,
  OperationLog,
  Overview,
  PoiInput,
  PoiView,
  PromptVersion,
  PromptVersionInput,
  ProviderReport,
  ToolHealth,
} from './types'

export const authApi = {
  login: (identifier: string, password: string) =>
    api.post<AuthResponse>('/auth/login', { identifier, password }, { silentAuth: true }),
}

export const poiApi = {
  list: (keyword?: string) => api.get<PoiView[]>('/admin/pois', { query: { keyword } }),
  get: (id: string) => api.get<PoiView>('/admin/pois/' + encodeURIComponent(id)),
  create: (input: PoiInput) => api.post<PoiView>('/admin/pois', input),
  update: (id: string, input: PoiInput) => api.put<PoiView>('/admin/pois/' + encodeURIComponent(id), input),
  setPublished: (id: string, published: boolean) =>
    api.patch<PoiView>('/admin/pois/' + encodeURIComponent(id) + '/publish', { published }),
  remove: (id: string) => api.del<void>('/admin/pois/' + encodeURIComponent(id)),
  /**
   * 用景点名反查一个可信坐标。只解析、不落库：结果回填到表单，
   * 点“保存”之前不会写进内容库，因此可以放心地多试几次。
   */
  geocode: (name: string, city?: string) =>
    api.post<GeocodePreview>('/admin/pois/geocode', { name, city: city ?? null }),
}

export const mediaApi = {
  /**
   * 上传景点配图。服务端会做魔数校验、尺寸校验与重命名，
   * 返回的 url 可以直接写入景点内容。
   */
  uploadImage: (file: File) => api.upload<ImageUploadResult>('/admin/media/images', file),
}

export const statsApi = {
  overview: () => api.get<Overview>('/admin/stats/overview'),
}

export const toolApi = {
  /** 外部数据源健康度：每个源是 ready / 缺少配置 / 未接入 / mock 模式，一目了然。 */
  health: () => api.get<ToolHealth>('/admin/tools/health'),
}

export const aiApi = {
  providers: () => api.get<ProviderReport>('/admin/llm/providers'),
}

export const promptApi = {
  list: () => api.get<PromptVersion[]>('/admin/llm/prompts'),
  current: () => api.get<PromptVersion>('/admin/llm/prompts/current'),
  create: (input: PromptVersionInput) => api.post<PromptVersion>('/admin/llm/prompts', input),
  activate: (id: string) =>
    api.patch<PromptVersion>('/admin/llm/prompts/' + encodeURIComponent(id) + '/activate'),
}

export const mockApi = {
  catalog: () => api.get<DemoScenarioCatalog>('/admin/mock/scenarios'),
  upsert: (scenarioKey: string, matchKey: string, input: DemoScenarioInput) =>
    api.put<DemoScenario>(
      '/admin/mock/scenarios/'
        + encodeURIComponent(scenarioKey)
        + '/'
        + encodeURIComponent(matchKey),
      input,
    ),
  remove: (id: string) =>
    api.del<void>('/admin/mock/scenarios/' + encodeURIComponent(id)),
}

export const communityAdminApi = {
  posts: (status: string, page = 1, size = 12) =>
    api.get<CommunityPostPage>('/admin/community/posts', {
      query: { status, page, size },
    }),
  moderatePost: (id: string, status: string, note: string | null) =>
    api.patch<CommunityPostView>(
      '/admin/community/posts/' + encodeURIComponent(id) + '/status',
      { status, note },
    ),
  reports: (status: string, page = 1, size = 12) =>
    api.get<CommunityReportPage>('/admin/community/reports', {
      query: { status, page, size },
    }),
  handleReport: (id: string, status: string, note: string | null) =>
    api.patch<CommunityReportView>(
      '/admin/community/reports/' + encodeURIComponent(id),
      { status, note },
    ),
}

export const feedbackApi = {
  list: (status?: string) => api.get<FeedbackView[]>('/admin/feedback', { query: { status } }),
  update: (id: string, payload: { status?: string; handlerNote?: string }) =>
    api.patch<FeedbackView>('/admin/feedback/' + encodeURIComponent(id), payload),
}

export const logApi = {
  list: (limit = 50) => api.get<OperationLog[]>('/admin/logs', { query: { limit } }),
}

export const catalogApi = {
  home: () => api.get<{ corridors: unknown[]; featuredPois: unknown[]; headline: string; subline: string }>(
    '/home',
    { silentAuth: true },
  ),
}
