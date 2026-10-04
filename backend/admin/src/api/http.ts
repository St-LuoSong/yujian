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

/**
 * 把服务端返回的 `/media/...` 相对地址补成浏览器能直接取的地址。
 *
 * 上传接口按"谁上传就归谁"的规则推导地址，旅记配图入库时存的是相对路径。
 * 运营台如果把它原样塞进 `<img src>`，浏览器会去请求运营台自己的域名 ——
 * 那边只有 SPA 的 index.html（`try_files` 兜底），于是显示成一张碎图。
 *
 * 走 API 的绝对地址时（VITE_API_BASE 配了完整域名），这里会拼成对应的
 * 媒体域名；走相对地址时保持相对，由运营台的 nginx 把 `/media/` 反代到后端。
 */
export function mediaUrl(raw: string | null | undefined): string {
  const value = (raw ?? '').trim()
  if (!value) return ''
  if (/^(https?:)?\/\//i.test(value)) return value
  // BASE 形如 `/api` 或 `https://api.example.com/api`；图片挂在它的兄弟路径下。
  const origin = BASE.replace(/\/api$/, '')
  return origin + (value.startsWith('/') ? value : '/' + value)
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
async function upload<T>(
  path: string,
  file: File,
  fieldName = 'file',
  onProgress?: (percent: number) => void,
): Promise<T> {
  const form = new FormData()
  form.append(fieldName, file)

  if (onProgress) {
    return new Promise<T>((resolve, reject) => {
      const request = new XMLHttpRequest()
      request.open('POST', buildUrl(path))
      request.setRequestHeader('Accept', 'application/json')
      const token = readToken()
      if (token) request.setRequestHeader('Authorization', 'Bearer ' + token)
      request.upload.onprogress = (event) => {
        if (event.lengthComputable) onProgress(Math.round((event.loaded / event.total) * 100))
      }
      request.onerror = () => reject(new ApiError(0, 'NETWORK_UNREACHABLE', '无法连接服务端，请确认后端已启动'))
      request.onload = async () => {
        try {
          const response = new Response(request.responseText, {
            status: request.status,
            headers: { 'Content-Type': request.getResponseHeader('Content-Type') ?? 'application/json' },
          })
          resolve(await readResponse<T>(response, false))
        } catch (cause) {
          reject(cause)
        }
      }
      request.send(form)
    })
  }

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
