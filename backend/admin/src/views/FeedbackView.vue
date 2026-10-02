<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { feedbackApi } from '../api/endpoints'
import { ApiError } from '../api/http'
import type { FeedbackView } from '../api/types'
import DataState from '../components/DataState.vue'

const rows = ref<FeedbackView[]>([])
const loading = ref(true)
const error = ref<string | null>(null)
const status = ref('')

const active = ref<FeedbackView | null>(null)
const note = ref('')
const nextStatus = ref('HANDLED')
const saving = ref(false)
const formError = ref<string | null>(null)

const STATUS_LABELS: Record<string, string> = {
  OPEN: '待处理',
  HANDLED: '已处理',
  IGNORED: '不处理',
}

async function load() {
  loading.value = true
  error.value = null
  try {
    rows.value = await feedbackApi.list(status.value || undefined)
  } catch (cause) {
    error.value = cause instanceof ApiError ? cause.message : '反馈列表加载失败'
  } finally {
    loading.value = false
  }
}

onMounted(load)

function open(row: FeedbackView) {
  active.value = row
  note.value = row.handlerNote ?? ''
  nextStatus.value = row.status === 'OPEN' ? 'HANDLED' : row.status
  formError.value = null
}

async function submit() {
  if (!active.value) return
  saving.value = true
  formError.value = null
  try {
    await feedbackApi.update(active.value.id, { status: nextStatus.value, handlerNote: note.value })
    active.value = null
    await load()
  } catch (cause) {
    formError.value = cause instanceof ApiError ? cause.message : '更新失败'
  } finally {
    saving.value = false
  }
}

function tagClass(value: string): string {
  if (value === 'OPEN') return 'tag-warn'
  if (value === 'HANDLED') return 'tag-ok'
  return 'tag-muted'
}
</script>

<template>
  <div class="stack">
    <div class="toolbar">
      <select v-model="status" class="select" @change="load">
        <option value="">全部状态</option>
        <option value="OPEN">待处理</option>
        <option value="HANDLED">已处理</option>
        <option value="IGNORED">不处理</option>
      </select>
      <button class="btn btn-sm" type="button" @click="load">刷新</button>
      <span class="hint">反馈只保存内容与可选联系方式；不采集设备标识。</span>
    </div>

    <article class="panel">
      <div class="panel-body is-flush">
        <DataState
          :loading="loading"
          :error="error"
          :empty="!rows.length"
          empty-text="当前筛选条件下没有用户反馈。"
        >
          <table class="table">
            <thead>
              <tr>
                <th>提交时间</th>
                <th>分类</th>
                <th>内容</th>
                <th>来源</th>
                <th>状态</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="row in rows" :key="row.id">
                <td class="cell-sub">{{ new Date(row.createdAt).toLocaleString('zh-CN', { hour12: false }) }}</td>
                <td><span class="tag tag-plain">{{ row.category }}</span></td>
                <td style="max-width:420px">{{ row.content }}</td>
                <td class="cell-sub">
                  {{ row.page ?? '—' }}
                  <div>{{ row.fromRegisteredUser ? '登录用户' : '匿名会话' }}</div>
                </td>
                <td><span class="tag" :class="tagClass(row.status)">{{ STATUS_LABELS[row.status] ?? row.status }}</span></td>
                <td>
                  <div class="actions">
                    <button class="btn btn-sm btn-ghost" type="button" @click="open(row)">处理</button>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </DataState>
      </div>
    </article>

    <div v-if="active" class="drawer-mask" @click.self="active = null">
      <aside class="drawer" style="width:min(520px,100%)">
        <header class="drawer-head">
          <div>
            <span class="eyebrow">Feedback</span>
            <h3>处理反馈</h3>
          </div>
          <button class="btn btn-sm btn-ghost" type="button" @click="active = null">关闭</button>
        </header>
        <div class="drawer-body stack">
          <div v-if="formError" class="alert">{{ formError }}</div>
          <div class="panel">
            <div class="panel-body">
              <p>{{ active.content }}</p>
              <dl class="kv" style="margin-top:12px">
                <dt>分类</dt>
                <dd>{{ active.category }}</dd>
                <dt>联系方式</dt>
                <dd>{{ active.contact ?? '未提供' }}</dd>
                <dt>来源页面</dt>
                <dd>{{ active.page ?? '—' }}</dd>
              </dl>
            </div>
          </div>
          <div class="field">
            <label>处理结果</label>
            <select v-model="nextStatus" class="select">
              <option value="OPEN">待处理</option>
              <option value="HANDLED">已处理</option>
              <option value="IGNORED">不处理</option>
            </select>
          </div>
          <div class="field">
            <label>处理说明（仅运营可见）</label>
            <textarea v-model="note" class="textarea" placeholder="已核对景区开放时间并更新内容库"></textarea>
          </div>
        </div>
        <footer class="drawer-foot">
          <button class="btn" type="button" @click="active = null">取消</button>
          <button class="btn btn-primary" type="button" :disabled="saving" @click="submit">
            {{ saving ? '保存中…' : '保存处理结果' }}
          </button>
        </footer>
      </aside>
    </div>
  </div>
</template>
