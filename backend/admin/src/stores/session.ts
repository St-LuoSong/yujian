import { computed, ref } from 'vue'
import { defineStore } from 'pinia'
import { authApi } from '../api/endpoints'
import { clearSession, readToken, readUser, saveSession, type AdminUser } from '../api/token'

export const useSessionStore = defineStore('session', () => {
  const token = ref<string | null>(readToken())
  const user = ref<AdminUser | null>(readUser())

  const isAuthenticated = computed(() => Boolean(token.value))
  const isAdmin = computed(() => user.value?.roles?.includes('ADMIN') ?? false)
  const displayName = computed(() => user.value?.username ?? '未登录')

  async function login(identifier: string, password: string): Promise<void> {
    const result = await authApi.login(identifier, password)
    const nextUser: AdminUser = {
      id: result.user.id,
      username: result.user.username,
      email: result.user.email,
      roles: result.user.roles ?? [],
    }
    token.value = result.accessToken
    user.value = nextUser
    saveSession(result.accessToken, nextUser)
  }

  function logout(): void {
    token.value = null
    user.value = null
    clearSession()
  }

  return { token, user, isAuthenticated, isAdmin, displayName, login, logout }
})
