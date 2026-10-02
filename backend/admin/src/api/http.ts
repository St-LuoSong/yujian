import { clearSession, readToken } from './token'

const BASE = ((import.meta.env.VITE_API_BASE as string | undefined) ?? '/api').replace(/\/+$/, '')

export class ApiError extends Error {
  readonly status: number
  readonly code: string

  constructor(status: number, code: string, message: string) {
    super(message)
    this.status = status
    this.code = code
  }
}

export type QueryValue = string | number | boolean | undefined | null

export function buildUrl(path: string, query?: Record<string, QueryValue>): string {
  const url = BASE + (path.startsWith('/') ? path : '/' + path)
  if (!query) return url
  const params = new URLSearchParams()
  for (const [key, value] of Object.entries(query)) {
    if (value === undefined || value === null || value === '') continue
    params.set(key, String(value))
  }
  const qs = params.toString()
  return qs ? url + '?' + qs : url
}

function authHeaders(): Record<string, string> {
  const token = readToken()
  return token ? { Authorization: 'Bearer ' + token } : {}
}

/** 统一处理 401、错误载荷与空响应，普通请求和上传共用同一套语义。 */
async function readResponse<T>(response: Response, silentAuth: boolean): Promise<T> {
  if (response.status === 401 && !silentAuth) {
    clearSession()
    if (!location.hash.startsWith('#/login')) location.hash = '#/login'
    throw new ApiError(401, 'AUTH_REQUIRED', '登录状态已失效，请重新登录')
  }

  if (response.status === 204) return undefined as T

  const text = await response.text()
  let payload: unknown = null
  if (text) {
    try {
      payload = JSON.parse(text)
    } catch {
      payload = null
    }
  }
  const body = payload as { code?: string; message?: string; detail?: string } | null

  if (!response.ok) {
    throw new ApiError(
      response.status,
      body?.code ?? 'HTTP_' + response.status,
      body?.message ?? body?.detail ?? '请求失败（' + response.status + '）',
    )
  }
  return payload as T
}

interface RequestOptions {
  query?: Record<string, QueryValue>
  body?: unknown
  /** 401 时是否强制退出登录。登录接口自己处理失败，不应该被踢。 */
  silentAuth?: boolean
}

async function request<T>(method: string, path: string, options: RequestOptions = {}): Promise<T> {
  const headers: Record<string, string> = { Accept: 'application/json', ...authHeaders() }
  if (options.body !== undefined) headers['Content-Type'] = 'application/json'

  let response: Response
  try {
    response = await fetch(buildUrl(path, options.query), {
      method,
      headers,
      body: options.body === undefined ? undefined : JSON.stringify(options.body),
    })
  } catch {
    throw new ApiError(0, 'NETWORK_UNREACHABLE', '无法连接服务端，请确认后端已启动')
  }
  return readResponse<T>(response, Boolean(options.silentAuth))
}

/**
 * multipart 上传。
 *
 * 刻意不设置 Content-Type：浏览器需要自己补 boundary，手写会破坏请求。
 */
async function upload<T>(path: string, file: File, fieldName = 'file'): Promise<T> {
  const form = new FormData()
  form.append(fieldName, file)

  let response: Response
  try {
    response = await fetch(buildUrl(path), {
      method: 'POST',
      headers: { Accept: 'application/json', ...authHeaders() },
      body: form,
    })
  } catch {
    throw new ApiError(0, 'NETWORK_UNREACHABLE', '无法连接服务端，请确认后端已启动')
  }
  return readResponse<T>(response, false)
}

export const api = {
  get: <T>(path: string, options?: RequestOptions) => request<T>('GET', path, options),
  post: <T>(path: string, body?: unknown, options?: RequestOptions) =>
    request<T>('POST', path, { ...options, body }),
  put: <T>(path: string, body?: unknown, options?: RequestOptions) =>
    request<T>('PUT', path, { ...options, body }),
  patch: <T>(path: string, body?: unknown, options?: RequestOptions) =>
    request<T>('PATCH', path, { ...options, body }),
  del: <T>(path: string, options?: RequestOptions) => request<T>('DELETE', path, options),
  upload,
}
