const TOKEN_KEY = 'yujian.admin.token'
const USER_KEY = 'yujian.admin.user'

export interface AdminUser {
  id: string
  username: string
  email: string | null
  roles: string[]
}

/**
 * 管理台会话放在 sessionStorage：关闭标签页即失效，比 localStorage 少一份长期泄露面。
 * 令牌只用于调用同源 /api，不写入 URL、不写日志、不进入图表数据。
 */
export function readToken(): string | null {
  try {
    return sessionStorage.getItem(TOKEN_KEY)
  } catch {
    return null
  }
}

export function readUser(): AdminUser | null {
  try {
    const raw = sessionStorage.getItem(USER_KEY)
    return raw ? (JSON.parse(raw) as AdminUser) : null
  } catch {
    return null
  }
}

export function saveSession(accessToken: string, user: AdminUser): void {
  try {
    sessionStorage.setItem(TOKEN_KEY, accessToken)
    sessionStorage.setItem(USER_KEY, JSON.stringify(user))
  } catch {
    /* 隐私模式下写入失败时，本次会话仍可用内存中的状态 */
  }
}

export function clearSession(): void {
  try {
    sessionStorage.removeItem(TOKEN_KEY)
    sessionStorage.removeItem(USER_KEY)
  } catch {
    /* ignore */
  }
}
