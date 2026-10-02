<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { aiApi } from '../api/endpoints'
import { ApiError } from '../api/http'
import type { ProviderReport } from '../api/types'
import DataState from '../components/DataState.vue'

const report = ref<ProviderReport | null>(null)
const loading = ref(true)
const error = ref<string | null>(null)

async function load() {
  loading.value = true
  error.value = null
  try {
    report.value = await aiApi.providers()
  } catch (cause) {
    error.value = cause instanceof ApiError ? cause.message : 'AI 运行状态加载失败'
  } finally {
    loading.value = false
  }
}

onMounted(load)

function attemptOf(engine: string) {
  return report.value?.attempts.find((item) => item.engine === engine) ?? null
}

function stateTag(line: { enabled: boolean; configured: boolean }): { text: string; cls: string } {
  if (!line.enabled) return { text: '未启用', cls: 'tag-muted' }
  if (!line.configured) return { text: '已启用但缺少密钥', cls: 'tag-warn' }
  return { text: '可参与规划', cls: 'tag-ok' }
}
</script>

<template>
  <div class="stack">
    <DataState :loading="loading" :error="error">
      <template v-if="report">
        <article class="panel">
          <div class="panel-head">
            <div>
              <span class="eyebrow">Selection</span>
              <h3>当前降级顺序</h3>
            </div>
            <span class="cell-sub">
              最近一次成功的引擎：{{ report.activeEngine ?? '无（可能降级到 Mock）' }}
            </span>
          </div>
          <div class="panel-body">
            <p class="hint" style="margin-bottom:10px">
              服务端按优先级依次尝试；未启用或缺少密钥的供应商会被跳过，全部失败时由 Mock 引擎兜底，
              行程会被标记为演示数据。
            </p>
            <ol class="list">
              <li v-for="(engine, index) in report.selectionOrder" :key="engine">
                <span class="num">{{ String(index + 1).padStart(2, '0') }}</span>
                <span class="cell-strong" style="flex:1">{{ engine }}</span>
                <span class="tag tag-ok">参与尝试</span>
              </li>
              <li v-if="!report.selectionOrder.length">
                <span class="cell-sub">当前没有任何云端供应商可用，规划将直接使用 Mock 引擎。</span>
              </li>
            </ol>
          </div>
        </article>

        <div class="grid-2">
          <article v-for="line in report.providers" :key="line.id" class="panel">
            <div class="panel-head">
              <div>
                <span class="eyebrow">优先级 {{ line.priority }}</span>
                <h3>{{ line.displayName }}</h3>
              </div>
              <span class="tag" :class="stateTag(line).cls">{{ stateTag(line).text }}</span>
            </div>
            <div class="panel-body">
              <dl class="kv">
                <dt>模型</dt>
                <dd class="mono">{{ line.model || '—' }}</dd>
                <dt>Base URL</dt>
                <dd class="mono" style="word-break:break-all">{{ line.baseUrl || '—' }}</dd>
                <dt>超时</dt>
                <dd class="num">{{ line.timeoutSeconds }} 秒</dd>
                <dt>温度</dt>
                <dd class="num">{{ line.temperature }}</dd>
                <dt>成功 / 失败</dt>
                <dd class="num">
                  {{ attemptOf(line.id)?.successCount ?? 0 }} / {{ attemptOf(line.id)?.failureCount ?? 0 }}
                </dd>
                <dt>最近耗时</dt>
                <dd class="num">
                  {{ attemptOf(line.id)?.lastDurationMs ? attemptOf(line.id)?.lastDurationMs + ' ms' : '—' }}
                </dd>
              </dl>
              <p
                v-if="attemptOf(line.id)?.lastError"
                class="hint"
                style="margin-top:10px;color:var(--kiln);word-break:break-all"
              >
                最近错误：{{ attemptOf(line.id)?.lastError }}
              </p>
              <p v-else class="hint" style="margin-top:10px">
                未记录到失败。密钥只存在于服务端环境变量，本页面不展示任何密钥。
              </p>
            </div>
          </article>
        </div>

        <article class="panel">
          <div class="panel-head">
            <div>
              <span class="eyebrow">Attempts</span>
              <h3>本次运行期尝试记录</h3>
            </div>
            <button class="btn btn-sm" type="button" @click="load">刷新</button>
          </div>
          <div class="panel-body is-flush">
            <table class="table">
              <thead>
                <tr>
                  <th>引擎</th>
                  <th>成功</th>
                  <th>失败</th>
                  <th>最近状态</th>
                  <th>最近耗时</th>
                  <th>最近变化</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="attempt in report.attempts" :key="attempt.engine">
                  <td class="cell-strong">{{ attempt.engine }}</td>
                  <td class="num">{{ attempt.successCount }}</td>
                  <td class="num">{{ attempt.failureCount }}</td>
                  <td>
                    <span class="tag" :class="attempt.lastStatus === 'success' ? 'tag-ok' : 'tag-danger'">
                      {{ attempt.lastStatus === 'success' ? '成功' : attempt.lastStatus === 'failure' ? '失败' : attempt.lastStatus }}
                    </span>
                  </td>
                  <td class="num">{{ attempt.lastDurationMs }} ms</td>
                  <td class="cell-sub">{{ new Date(attempt.lastChangedAt).toLocaleString('zh-CN', { hour12: false }) }}</td>
                </tr>
                <tr v-if="!report.attempts.length">
                  <td colspan="6" class="cell-sub">本次启动后还没有调用过任何供应商。</td>
                </tr>
              </tbody>
            </table>
          </div>
        </article>
      </template>
    </DataState>
  </div>
</template>
