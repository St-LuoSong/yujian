<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { communityAdminApi } from '../api/endpoints'
import { ApiError, mediaUrl } from '../api/http'
import type {
  CommunityCommentView,
  CommunityPostView,
  CommunityReportView,
} from '../api/types'
import DataState from '../components/DataState.vue'

type Tab = 'posts' | 'reports'

const activeTab = ref<Tab>('posts')
const postStatus = ref('PENDING')
const reportStatus = ref('OPEN')
const posts = ref<CommunityPostView[]>([])
const reports = ref<CommunityReportView[]>([])
const postPage = ref(1)
const reportPage = ref(1)
const postHasMore = ref(false)
const reportHasMore = ref(false)
const loading = ref(true)
const error = ref<string | null>(null)
const selected = ref<CommunityPostView | null>(null)
const moderationNote = ref('')
const acting = ref(false)
const comments = ref<CommunityCommentView[]>([])
const commentsLoading = ref(false)
const commentsError = ref<string | null>(null)

const postStatuses = [
  { key: 'PENDING', label: '待审核' },
  { key: 'APPROVED', label: '已通过' },
  { key: 'REJECTED', label: '已驳回' },
  { key: 'TAKEN_DOWN', label: '已下架' },
]

const reportStatuses = [
  { key: 'OPEN', label: '待处理' },
  { key: 'HANDLED', label: '已处理' },
  { key: 'IGNORED', label: '已忽略' },
]

async function loadPosts() {
  loading.value = true
  error.value = null
  try {
    const page = await communityAdminApi.posts(postStatus.value, postPage.value)
    posts.value = page.items
    postHasMore.value = page.hasMore
  } catch (cause) {
    error.value = cause instanceof ApiError ? cause.message : '旅记审核列表加载失败'
  } finally {
    loading.value = false
  }
}

async function loadReports() {
  loading.value = true
  error.value = null
  try {
    const page = await communityAdminApi.reports(reportStatus.value, reportPage.value)
    reports.value = page.items
    reportHasMore.value = page.hasMore
  } catch (cause) {
    error.value = cause instanceof ApiError ? cause.message : '举报列表加载失败'
  } finally {
    loading.value = false
  }
}

function selectTab(tab: Tab) {
  activeTab.value = tab
  selected.value = null
  if (tab === 'posts') {
    loadPosts()
  } else {
    loadReports()
  }
}

function selectPostStatus(status: string) {
  postStatus.value = status
  postPage.value = 1
  selected.value = null
  loadPosts()
}

function selectReportStatus(status: string) {
  reportStatus.value = status
  reportPage.value = 1
  loadReports()
}

function openPost(post: CommunityPostView) {
  selected.value = post
  moderationNote.value = post.moderationNote ?? ''
  comments.value = []
  commentsError.value = null
  loadComments(post.id)
}

/**
 * 一篇旅记下的评论，含已隐藏的。
 *
 * 隐藏不删行：管理员先看到内容再决定，比"删掉之后再想恢复"要有余地得多。
 */
async function loadComments(postId: string) {
  commentsLoading.value = true
  commentsError.value = null
  try {
    const page = await communityAdminApi.comments(postId)
    comments.value = page.items
  } catch (cause) {
    commentsError.value = cause instanceof ApiError ? cause.message : '评论加载失败'
  } finally {
    commentsLoading.value = false
  }
}

async function moderateComment(comment: CommunityCommentView, status: 'ACTIVE' | 'HIDDEN') {
  try {
    await communityAdminApi.moderateComment(comment.id, status)
    if (selected.value) await loadComments(selected.value.id)
  } catch (cause) {
    commentsError.value = cause instanceof ApiError ? cause.message : '评论处理失败'
  }
}

async function moderate(status: string) {
  if (!selected.value) return
  if (status === 'REJECTED' && !moderationNote.value.trim()) {
    error.value = '驳回必须填写说明，作者才能知道原因。'
    return
  }
  acting.value = true
  error.value = null
  try {
    await communityAdminApi.moderatePost(selected.value.id, status, moderationNote.value.trim() || null)
    selected.value = null
    await loadPosts()
  } catch (cause) {
    error.value = cause instanceof ApiError ? cause.message : '审核操作失败'
  } finally {
    acting.value = false
  }
}

async function handleReport(report: CommunityReportView, status: string) {
  const note = window.prompt(status === 'HANDLED' ? '填写处理说明（可选）' : '填写忽略原因（可选）', '') ?? ''
  try {
    await communityAdminApi.handleReport(report.id, status, note.trim() || null)
    await loadReports()
  } catch (cause) {
    error.value = cause instanceof ApiError ? cause.message : '举报处理失败'
  }
}

function statusLabel(status: string): string {
  const labels: Record<string, string> = {
    PENDING: '待审核',
    APPROVED: '已通过',
    REJECTED: '已驳回',
    TAKEN_DOWN: '已下架',
    OPEN: '待处理',
    HANDLED: '已处理',
    IGNORED: '已忽略',
  }
  return labels[status] ?? status
}

function statusClass(status: string): string {
  if (status === 'APPROVED' || status === 'HANDLED') return 'tag-ok'
  if (status === 'REJECTED' || status === 'TAKEN_DOWN') return 'tag-danger'
  if (status === 'OPEN') return 'tag-warn'
  return 'tag-muted'
}

function publicLabel(post: CommunityPostView): string {
  return post.visibility === 'PUBLIC' ? '公开' : '仅自己可见'
}

function shortDate(value: string): string {
  return new Date(value).toLocaleString('zh-CN', { hour12: false })
}

onMounted(loadPosts)
</script>

<template>
  <div class="stack">
    <div class="tabs" role="tablist" aria-label="社区审核">
      <button
        class="tab"
        :class="{ 'is-active': activeTab === 'posts' }"
        type="button"
        role="tab"
        :aria-selected="activeTab === 'posts'"
        @click="selectTab('posts')"
      >
        旅记审核
      </button>
      <button
        class="tab"
        :class="{ 'is-active': activeTab === 'reports' }"
        type="button"
        role="tab"
        :aria-selected="activeTab === 'reports'"
        @click="selectTab('reports')"
      >
        举报处理
      </button>
    </div>

    <article v-if="activeTab === 'posts'" class="panel">
      <div class="panel-head">
        <div>
          <span class="eyebrow">Community queue</span>
          <h3>旅记审核队列</h3>
        </div>
        <div class="toolbar">
          <button
            v-for="item in postStatuses"
            :key="item.key"
            class="btn btn-sm"
            :class="{ 'btn-primary': postStatus === item.key }"
            type="button"
            @click="selectPostStatus(item.key)"
          >
            {{ item.label }}
          </button>
        </div>
      </div>
      <div class="panel-body is-flush">
        <DataState
          :loading="loading"
          :error="error"
          :empty="!posts.length"
          empty-text="当前状态下没有旅记。"
        >
          <table class="table">
            <thead>
              <tr>
                <th>旅记</th>
                <th>作者</th>
                <th>城市</th>
                <th>范围</th>
                <th>状态</th>
                <th>提交时间</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="post in posts" :key="post.id" @click="openPost(post)">
                <td>
                  <div class="cell-strong">{{ post.title }}</div>
                  <div class="cell-sub">{{ post.content.slice(0, 42) }}{{ post.content.length > 42 ? '…' : '' }}</div>
                </td>
                <td>{{ post.authorName }}</td>
                <td>{{ post.city }}</td>
                <td><span class="tag tag-plain">{{ publicLabel(post) }}</span></td>
                <td><span class="tag" :class="statusClass(post.status)">{{ statusLabel(post.status) }}</span></td>
                <td class="cell-sub">{{ shortDate(post.createdAt) }}</td>
                <td><button class="btn btn-sm btn-ghost" type="button" @click.stop="openPost(post)">查看</button></td>
              </tr>
            </tbody>
          </table>
        </DataState>
      </div>
      <div class="pager">
        <span>第 {{ postPage }} 页</span>
        <div class="actions">
          <button class="btn btn-sm" type="button" :disabled="postPage <= 1" @click="postPage -= 1; loadPosts()">上一页</button>
          <button class="btn btn-sm" type="button" :disabled="!postHasMore" @click="postPage += 1; loadPosts()">下一页</button>
        </div>
      </div>
    </article>

    <article v-else class="panel">
      <div class="panel-head">
        <div>
          <span class="eyebrow">Reports</span>
          <h3>举报处理</h3>
        </div>
        <div class="toolbar">
          <button
            v-for="item in reportStatuses"
            :key="item.key"
            class="btn btn-sm"
            :class="{ 'btn-primary': reportStatus === item.key }"
            type="button"
            @click="selectReportStatus(item.key)"
          >
            {{ item.label }}
          </button>
        </div>
      </div>
      <div class="panel-body is-flush">
        <DataState
          :loading="loading"
          :error="error"
          :empty="!reports.length"
          empty-text="当前状态下没有举报。"
        >
          <table class="table">
            <thead>
              <tr>
                <th>举报编号</th>
                <th>旅记 ID</th>
                <th>举报人</th>
                <th>原因</th>
                <th>状态</th>
                <th>时间</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="report in reports" :key="report.id">
                <td class="mono">{{ report.id.slice(0, 10) }}</td>
                <td class="mono">{{ report.postId.slice(0, 10) }}</td>
                <td>{{ report.reporterName }}</td>
                <td>{{ report.reason }}</td>
                <td><span class="tag" :class="statusClass(report.status)">{{ statusLabel(report.status) }}</span></td>
                <td class="cell-sub">{{ shortDate(report.createdAt) }}</td>
                <td>
                  <div class="actions" v-if="report.status === 'OPEN'">
                    <button class="btn btn-sm" type="button" @click="handleReport(report, 'HANDLED')">已处理</button>
                    <button class="btn btn-sm btn-ghost" type="button" @click="handleReport(report, 'IGNORED')">忽略</button>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </DataState>
      </div>
      <div class="pager">
        <span>第 {{ reportPage }} 页</span>
        <div class="actions">
          <button class="btn btn-sm" type="button" :disabled="reportPage <= 1" @click="reportPage -= 1; loadReports()">上一页</button>
          <button class="btn btn-sm" type="button" :disabled="!reportHasMore" @click="reportPage += 1; loadReports()">下一页</button>
        </div>
      </div>
    </article>

    <div v-if="selected" class="drawer-mask" @click.self="selected = null">
      <aside class="drawer">
        <header class="drawer-head">
          <div>
            <span class="eyebrow">Review</span>
            <h3>{{ selected.title }}</h3>
          </div>
          <button class="btn btn-sm btn-ghost" type="button" @click="selected = null">关闭</button>
        </header>
        <div class="drawer-body stack">
          <div class="toolbar">
            <span class="tag tag-plain">{{ selected.authorName }}</span>
            <span class="tag tag-plain">{{ selected.city }}</span>
            <span class="tag" :class="statusClass(selected.status)">{{ statusLabel(selected.status) }}</span>
          </div>
          <p class="hint">{{ selected.content }}</p>
          <div v-if="selected.imageUrls.length" class="moderation-gallery">
            <img
              v-for="url in selected.imageUrls"
              :key="url"
              :src="mediaUrl(url)"
              :alt="selected.title"
            />
          </div>

          <section class="moderation-comments">
            <header class="moderation-comments-head">
              <strong>评论（{{ comments.length }}）</strong>
              <span class="cell-sub">隐藏不删除，随时可以恢复</span>
            </header>
            <p v-if="commentsLoading" class="hint">正在加载评论…</p>
            <p v-else-if="commentsError" class="alert">{{ commentsError }}</p>
            <p v-else-if="!comments.length" class="hint">这篇旅记还没有评论。</p>
            <template v-else>
              <div v-for="comment in comments" :key="comment.id" class="moderation-comment">
                <div class="moderation-comment-head">
                  <span class="cell-strong">{{ comment.authorName }}</span>
                  <span class="cell-sub">{{ shortDate(comment.createdAt) }}</span>
                  <span v-if="comment.status === 'HIDDEN'" class="tag tag-warn">已隐藏</span>
                  <span class="tag tag-plain">赞 {{ comment.likeCount }}</span>
                  <button
                    class="btn btn-sm"
                    type="button"
                    @click="moderateComment(comment, comment.status === 'HIDDEN' ? 'ACTIVE' : 'HIDDEN')"
                  >
                    {{ comment.status === 'HIDDEN' ? '恢复' : '隐藏' }}
                  </button>
                </div>
                <p class="moderation-comment-body">{{ comment.content }}</p>
                <div
                  v-for="reply in comment.replies"
                  :key="reply.id"
                  class="moderation-comment moderation-comment-reply"
                >
                  <div class="moderation-comment-head">
                    <span class="cell-strong">{{ reply.authorName }}</span>
                    <span class="cell-sub">{{ shortDate(reply.createdAt) }}</span>
                    <span v-if="reply.status === 'HIDDEN'" class="tag tag-warn">已隐藏</span>
                    <button
                      class="btn btn-sm"
                      type="button"
                      @click="moderateComment(reply, reply.status === 'HIDDEN' ? 'ACTIVE' : 'HIDDEN')"
                    >
                      {{ reply.status === 'HIDDEN' ? '恢复' : '隐藏' }}
                    </button>
                  </div>
                  <p class="moderation-comment-body">{{ reply.content }}</p>
                </div>
              </div>
            </template>
          </section>

          <div class="field">
            <label>审核说明</label>
            <textarea
              v-model="moderationNote"
              class="textarea"
              placeholder="通过可不填；驳回必须说明原因"
            ></textarea>
          </div>
        </div>
        <footer class="drawer-foot">
          <button class="btn" type="button" :disabled="acting" @click="moderate('TAKEN_DOWN')">下架</button>
          <button class="btn btn-danger" type="button" :disabled="acting" @click="moderate('REJECTED')">驳回</button>
          <button class="btn btn-primary" type="button" :disabled="acting" @click="moderate('APPROVED')">通过并公开</button>
        </footer>
      </aside>
    </div>
  </div>
</template>
