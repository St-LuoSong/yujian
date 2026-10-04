<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { securityApi } from '../api/endpoints'
import { ApiError } from '../api/http'
import type { SecurityLimitsView, SecurityQuotaUsage, SecuritySettingItem } from '../api/types'
import DataState from '../components/DataState.vue'

/**
 * 安全与限流。
 *
 * 两件事放在一页，是因为它们的调法一样：看着用量、改数字、立刻生效。
 * 限流保护的是我们自己的服务，配额保护的是外部接口的额度，对运营来说是一回事。
 */
const items = ref<SecuritySettingItem[]>([])
const quotas = ref<SecurityQuotaUsage[]>([])
const activeWindows = ref(0)
const draft = ref<Record<string, number>>({})
const loading = ref(true)
const saving = ref(false)
const error = ref<string | null>(null)
const notice = ref<string | null>(null)

/** 桶名到「额度 + 窗口」的配对，让一行里就能把一对数字改完。 */
interface RateRow {
  name: string
  label: string
  limit?: SecuritySettingItem
  window?: SecuritySettingItem
}

const rateEnabled = computed(() => items.value.find((item) => item.key === 'rate.enabled'))
const quotaEnabled = computed(() => items.value.find((item) => item.key === 'quota.enabled'))

const rateRows = computed<RateRow[]>(() => {
  const rows = new Map<string, RateRow>()
  for (const item of items.value) {
    if (item.group !== 'rate' || item.key === 'rate.enabled') continue
    const name = item.key.split('.')[1]
    const row = rows.get(name) ?? { name, label: stripSuffix(item.label) }
    if (item.key.endsWith('.limit')) row.limit = item
    if (item.key.endsWith('.window')) row.window = item
    rows.set(name, row)
  }
  return [...rows.values()]
})

const quotaRows = computed(() => items.value.filter(
  (item) => item.group === 'quota' && item.key !== 'quota.enabled',
))

const dirty = computed(() => items.value.some((item) => draft.value[item.key] !== item.value))

function stripSuffix(label: string): string {
  return label.replace(/\s*·\s*(次数|窗口)$/, '')
}

function usageFor(item: SecuritySettingItem): SecurityQuotaUsage | undefined {
  const name = item.key.split('.')[1]
  return quotas.value.find((quota) => quota.group === name)
}

function usedPercent(item: SecuritySettingItem): number {
  const usage = usageFor(item)
  if (!usage || usage.limit <= 0) return 0
  return Math.min(100, Math.round((usage.used / usage.limit) * 100))
}

function windowLabel(item?: SecuritySettingItem): string {
  if (!item) return ''
  const seconds = draft.value[item.key] ?? item.value
  if (seconds % 86400 === 0) return `${seconds / 86400} 天`
  if (seconds % 3600 === 0) return `${seconds / 3600} 小时`
  if (seconds % 60 === 0) return `${seconds / 60} 分钟`
  return `${seconds} 秒`
}

function sync(view: SecurityLimitsView) {
  items.value = view.items
  quotas.value = view.quotas
  activeWindows.value = view.activeWindows
  draft.value = Object.fromEntries(view.items.map((item) => [item.key, item.value]))
}

async function load() {
  loading.value = true
  error.value = null
  try {
    sync(await securityApi.limits())
  } catch (cause) {
    error.value = cause instanceof ApiError ? cause.message : '限流配置加载失败'
  } finally {
    loading.value = false
  }
}

async function save() {
  saving.value = true
  error.value = null
  notice.value = null
  try {
    sync(await securityApi.update(draft.value))
    notice.value = '已生效。限流计数按新额度继续，不会重置已经用掉的次数。'
  } catch (cause) {
    error.value = cause instanceof ApiError ? cause.message : '保存失败'
  } finally {
    saving.value = false
  }
}

async function reset() {
  if (!window.confirm('把所有限流与配额恢复成默认值？')) return
  saving.value = true
  error.value = null
  notice.value = null
  try {
    sync(await securityApi.reset())
    notice.value = '已恢复默认值。'
  } catch (cause) {
    error.value = cause instanceof ApiError ? cause.message : '恢复默认失败'
  } finally {
    saving.value = false
  }
}

onMounted(load)
</script>

<template>
  <div class="stack">
    <article class="panel">
      <div class="panel-head">
        <div>
          <span class="eyebrow">External tool quota</span>
          <h3>外部工具今日额度</h3>
        </div>
        <div class="toolbar">
          <span class="tag tag-plain">活跃限流窗口 {{ activeWindows }}</span>
          <button class="btn btn-sm" type="button" :disabled="saving || !dirty" @click="load">放弃修改</button>
          <button class="btn btn-sm" type="button" :disabled="saving" @click="reset">恢复默认</button>
          <button class="btn btn-sm btn-primary" type="button" :disabled="saving || !dirty" @click="save">
            {{ saving ? '保存中…' : '保存并生效' }}
          </button>
        </div>
      </div>
      <div class="panel-body">
        <p class="hint">
          额度按自然日（Asia/Shanghai）统计，用的是既有的工具调用日志，<strong>重启服务不会清零</strong>。
          用满之后当次调用直接熔断并如实标注"未取到实时数据"，不会继续消耗外部接口额度。
        </p>
        <div v-if="notice" class="alert alert-ok" style="margin-bottom:12px">{{ notice }}</div>
        <DataState :loading="loading" :error="error" :empty="!quotaRows.length" empty-text="暂无可配置的工具额度。">
          <div class="quota-list">
            <div v-for="item in quotaRows" :key="item.key" class="quota-row">
              <div class="quota-head">
                <div>
                  <div class="cell-strong">{{ item.label.replace(' · 每日上限', '') }}</div>
                  <div class="cell-sub">{{ item.description }}</div>
                </div>
                <div class="quota-numbers">
                  <span>今日已用 {{ usageFor(item)?.used ?? 0 }} / {{ draft[item.key] ?? item.value }}</span>
                </div>
              </div>
              <div class="quota-track">
                <i :style="{ width: usedPercent(item) + '%' }" :class="{ 'is-hot': usedPercent(item) >= 80 }"></i>
              </div>
              <label class="field quota-input">
                <span>每日上限（{{ item.unit }}）</span>
                <input
                  v-model.number="draft[item.key]"
                  class="input"
                  type="number"
                  :min="item.min"
                  :max="item.max"
                />
              </label>
            </div>
          </div>
        </DataState>
      </div>
    </article>

    <article class="panel">
      <div class="panel-head">
        <div>
          <span class="eyebrow">Rate limit</span>
          <h3>接口限流</h3>
        </div>
        <label v-if="rateEnabled" class="switch-row">
          <input v-model.number="draft['rate.enabled']" type="checkbox" :true-value="1" :false-value="0" />
          <span>启用限流</span>
        </label>
      </div>
      <div class="panel-body">
        <p class="hint">
          按主体分桶：登录用户按账号计，其余按客户端 IP。超过额度返回 429 并带上
          <code>Retry-After</code>，客户端据此决定什么时候重试。
          「每人每日规划次数」是对大模型开销的硬上限，窗口设成 86400 秒即是按自然日。
        </p>
        <table class="table">
          <thead>
            <tr>
              <th>场景</th>
              <th>说明</th>
              <th>窗口内次数</th>
              <th>窗口长度</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="row in rateRows" :key="row.name">
              <td class="cell-strong">{{ row.label }}</td>
              <td class="cell-sub">{{ row.limit?.description }}</td>
              <td>
                <input
                  v-if="row.limit"
                  v-model.number="draft[row.limit.key]"
                  class="input input-compact"
                  type="number"
                  :min="row.limit.min"
                  :max="row.limit.max"
                />
              </td>
              <td>
                <div v-if="row.window" class="window-cell">
                  <input
                    v-model.number="draft[row.window.key]"
                    class="input input-compact"
                    type="number"
                    :min="row.window.min"
                    :max="row.window.max"
                  />
                  <span class="cell-sub">{{ windowLabel(row.window) }}</span>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
        <p v-if="quotaEnabled" class="hint" style="margin-top:12px">
          外部工具配额总开关当前为
          <strong>{{ draft['quota.enabled'] ? '开启' : '关闭' }}</strong>；
          {{ quotaEnabled.description }}
        </p>
      </div>
    </article>
  </div>
</template>

<style scoped>
.quota-list{display:flex;flex-direction:column;gap:18px}
.quota-row{display:flex;flex-direction:column;gap:8px}
.quota-head{display:flex;align-items:flex-end;justify-content:space-between;gap:16px}
.quota-numbers{font-size:13px;color:var(--ink-soft);font-variant-numeric:tabular-nums}
.quota-track{height:6px;background:var(--glaze-sunken);overflow:hidden;border-radius:99px}
.quota-track i{display:block;height:100%;background:var(--celadon);transition:width .2s ease}
.quota-track i.is-hot{background:#b23a22}
.quota-input{max-width:220px}
.input-compact{width:96px;padding:6px 8px}
.window-cell{display:flex;align-items:center;gap:8px}
.switch-row{display:inline-flex;align-items:center;gap:8px;font-size:13px;color:var(--ink-soft)}
.alert-ok{background:#e4f0e8;color:#2f6f57;border-left:3px solid #3f7a57;padding:10px 12px;font-size:13px}
</style>
