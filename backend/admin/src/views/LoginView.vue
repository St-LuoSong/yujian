<script setup lang="ts">
import { ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ApiError } from '../api/http'
import { useSessionStore } from '../stores/session'

const route = useRoute()
const router = useRouter()
const session = useSessionStore()

const identifier = ref('')
const password = ref('')
const error = ref<string | null>(null)
const pending = ref(false)

async function submit() {
  error.value = null
  if (!identifier.value.trim() || !password.value) {
    error.value = '请填写账号与密码'
    return
  }
  pending.value = true
  try {
    await session.login(identifier.value.trim(), password.value)
    if (!session.isAdmin) {
      error.value = '该账号没有 ADMIN 角色，无法进入运营台。请在服务端设置 ADMIN_USERNAME / ADMIN_PASSWORD。'
      session.logout()
      return
    }
    const redirect = (route.query.redirect as string | undefined) ?? '/'
    router.replace(redirect)
  } catch (cause) {
    error.value = cause instanceof ApiError ? cause.message : '登录失败，请稍后再试'
  } finally {
    pending.value = false
  }
}
</script>

<template>
  <div class="login">
    <section class="login-visual">
      <div class="mark">豫见智旅</div>
      <div>
        <h2>让每一次出发<br /><em>都更有依据。</em></h2>
        <p style="margin-top:14px;color:#9FB0AB;font-size:13px;max-width:32em">
          运营台负责内容质量、AI 供应商健康度与用户反馈；游客端只看到经过校验的结果。
        </p>
      </div>
      <div class="foot">河南文旅智能服务 · 运营控制台</div>
    </section>

    <section class="login-form">
      <h1>运营登录</h1>
      <p class="sub">使用具备 ADMIN 角色的账号登录。管理员账号由服务端环境变量配置，不写入仓库。</p>
      <div v-if="error" class="alert">{{ error }}</div>
      <div class="field">
        <label for="identifier">账号或邮箱</label>
        <input
          id="identifier"
          v-model="identifier"
          class="input"
          autocomplete="username"
          placeholder="operator"
          @keyup.enter="submit"
        />
      </div>
      <div class="field">
        <label for="password">密码</label>
        <input
          id="password"
          v-model="password"
          class="input"
          type="password"
          autocomplete="current-password"
          placeholder="至少 8 位"
          @keyup.enter="submit"
        />
      </div>
      <button class="btn btn-primary" type="button" :disabled="pending" @click="submit">
        {{ pending ? '正在登录…' : '进入运营台' }}
      </button>
      <p class="hint">连续失败不会被记录密码；服务端只返回统一错误信息，避免暴露账号是否存在。</p>
    </section>
  </div>
</template>
