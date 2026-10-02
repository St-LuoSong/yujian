<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { statsApi } from '../api/endpoints'
import { useSessionStore } from '../stores/session'

const route = useRoute()
const router = useRouter()
const session = useSessionStore()
const health = ref<'unknown' | 'ok' | 'down'>('unknown')

const navItems = [
  { key: 'overview', index: '01', label: '运营总览', to: '/' },
  { key: 'pois', index: '02', label: '景点内容', to: '/pois' },
  { key: 'content', index: '03', label: '内容运营', to: '/content' },
  { key: 'ai', index: '04', label: 'AI 运行', to: '/ai' },
  { key: 'prompts', index: '05', label: '提示词版本', to: '/prompts' },
  { key: 'mock', index: '06', label: 'Mock 数据', to: '/mock' },
  { key: 'community', index: '07', label: '社区审核', to: '/community' },
  { key: 'feedback', index: '08', label: '用户反馈', to: '/feedback' },
  { key: 'logs', index: '09', label: '操作日志', to: '/logs' },
]

const activeNav = computed(() => (route.meta.nav as string) ?? 'overview')
const pageTitle = computed(() => (route.meta.title as string) ?? '运营台')
const pageCrumb = computed(() => (route.meta.crumb as string) ?? '')

onMounted(async () => {
  try {
    await statsApi.overview()
    health.value = 'ok'
  } catch {
    health.value = 'down'
  }
})

function logout() {
  session.logout()
  router.push({ name: 'login' })
}
</script>

<template>
  <div class="admin">
    <aside class="side">
      <div class="side-brand">
        <strong>豫见智旅</strong>
        <small>OPERATIONS</small>
      </div>
      <nav class="side-nav">
        <button
          v-for="item in navItems"
          :key="item.key"
          class="nav-item"
          :class="{ 'is-active': activeNav === item.key }"
          type="button"
          @click="router.push(item.to)"
        >
          <span class="idx">{{ item.index }}</span>
          <span>{{ item.label }}</span>
        </button>
      </nav>
      <div class="side-foot">
        <span class="dot" :class="{ 'is-bad': health === 'down' }"></span>
        {{ health === 'ok' ? '服务正常' : health === 'down' ? '服务不可用' : '检测中' }}
        <div>v0.2 · 管理台</div>
      </div>
    </aside>

    <div class="main">
      <header class="topbar">
        <div>
          <p class="crumb">{{ pageCrumb }}</p>
          <h1>{{ pageTitle }}</h1>
        </div>
        <div class="top-actions">
          <span class="tag tag-muted tag-plain">
            {{ session.user?.roles?.includes('ADMIN') ? 'ADMIN' : '无管理权限' }}
          </span>
          <span class="cell-sub">{{ session.displayName }}</span>
          <button class="btn btn-sm" type="button" @click="logout">退出</button>
        </div>
      </header>
      <main class="content">
        <router-view />
      </main>
    </div>
  </div>
</template>
