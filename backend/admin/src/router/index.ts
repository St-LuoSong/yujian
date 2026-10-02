import { createRouter, createWebHashHistory } from 'vue-router'
import { useSessionStore } from '../stores/session'

const router = createRouter({
  history: createWebHashHistory(),
  routes: [
    {
      path: '/login',
      name: 'login',
      component: () => import('../views/LoginView.vue'),
      meta: { public: true, title: '运营登录' },
    },
    {
      path: '/',
      component: () => import('../layouts/AdminLayout.vue'),
      children: [
        {
          path: '',
          name: 'overview',
          component: () => import('../views/OverviewView.vue'),
          meta: { title: '运营总览', crumb: 'Overview', nav: 'overview' },
        },
        {
          path: 'pois',
          name: 'pois',
          component: () => import('../views/PoisView.vue'),
          meta: { title: '景点内容', crumb: 'Content', nav: 'pois' },
        },
        {
          path: 'content',
          name: 'content',
          component: () => import('../views/ContentOpsView.vue'),
          meta: { title: '内容运营', crumb: 'Content Ops', nav: 'content' },
        },
        {
          path: 'ai',
          name: 'ai',
          component: () => import('../views/AiRunsView.vue'),
          meta: { title: 'AI 运行', crumb: 'Vendors', nav: 'ai' },
        },
        {
          path: 'prompts',
          name: 'prompts',
          component: () => import('../views/PromptVersionsView.vue'),
          meta: { title: '提示词版本', crumb: 'Prompts', nav: 'prompts' },
        },
        {
          path: 'mock',
          name: 'mock',
          component: () => import('../views/MockDataView.vue'),
          meta: { title: 'Mock 数据', crumb: 'Demo Data', nav: 'mock' },
        },
        {
          path: 'community',
          name: 'community',
          component: () => import('../views/CommunityModerationView.vue'),
          meta: { title: '社区审核', crumb: 'Community', nav: 'community' },
        },
        {
          path: 'feedback',
          name: 'feedback',
          component: () => import('../views/FeedbackView.vue'),
          meta: { title: '用户反馈', crumb: 'Feedback', nav: 'feedback' },
        },
        {
          path: 'logs',
          name: 'logs',
          component: () => import('../views/LogsView.vue'),
          meta: { title: '操作日志', crumb: 'Audit', nav: 'logs' },
        },
      ],
    },
    { path: '/:pathMatch(.*)*', redirect: '/' },
  ],
})

router.beforeEach((to) => {
  const session = useSessionStore()
  if (!to.meta.public && !session.isAuthenticated) {
    return { name: 'login', query: to.fullPath === '/' ? undefined : { redirect: to.fullPath } }
  }
  if (to.name === 'login' && session.isAuthenticated) {
    return { name: 'overview' }
  }
  return true
})

router.afterEach((to) => {
  const title = (to.meta.title as string | undefined) ?? '运营台'
  document.title = title + ' · 豫见智旅'
})

export default router
