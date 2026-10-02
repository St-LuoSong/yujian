<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { logApi } from '../api/endpoints'
import { ApiError } from '../api/http'
import type { OperationLog } from '../api/types'
import DataState from '../components/DataState.vue'

const rows = ref<OperationLog[]>([])
const loading = ref(true)
const error = ref<string | null>(null)
const limit = ref(50)

const ACTION_LABELS: Record<string, string> = {
  POI_CREATE: '新增景点',
  POI_UPDATE: '修改景点',
  POI_PUBLISH: '上架景点',
  POI_UNPUBLISH: '下架景点',
  POI_DELETE: '删除景点',
  FEEDBACK_UPDATE: '处理反馈',
}

async function load() {
  loading.value = true
  error.value = null
  try {
    rows.value = await logApi.list(limit.value)
  } catch (cause) {
    error.value = cause instanceof ApiError ? cause.message : '日志加载失败'
  } finally {
    loading.value = false
  }
}

onMounted(load)
</script>

<template>
  <div class="stack">
    <div class="toolbar">
      <select v-model.number="limit" class="select" @change="load">
        <option :value="50">最近 50 条</option>
        <option :value="100">最近 100 条</option>
        <option :value="200">最近 200 条</option>
      </select>
      <button class="btn btn-sm" type="button" @click="load">刷新</button>
      <span class="hint">只记录动作、目标与摘要，不记录令牌、密码或完整请求体。</span>
    </div>

    <article class="panel">
      <div class="panel-body is-flush">
        <DataState :loading="loading" :error="error" :empty="!rows.length" empty-text="还没有管理员操作记录。">
          <table class="table">
            <thead>
              <tr>
                <th>时间</th>
                <th>操作者</th>
                <th>动作</th>
                <th>目标</th>
                <th>摘要</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="row in rows" :key="row.id">
                <td class="cell-sub">{{ new Date(row.createdAt).toLocaleString('zh-CN', { hour12: false }) }}</td>
                <td>{{ row.actorName ?? '—' }}</td>
                <td><span class="tag tag-plain">{{ ACTION_LABELS[row.action] ?? row.action }}</span></td>
                <td class="mono">{{ row.target }}</td>
                <td>{{ row.detail ?? '—' }}</td>
              </tr>
            </tbody>
          </table>
        </DataState>
      </div>
    </article>
  </div>
</template>
