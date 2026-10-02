<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { statsApi, toolApi } from '../api/endpoints'
import { ApiError } from '../api/http'
import type { Overview, ToolHealth } from '../api/types'
import DataState from '../components/DataState.vue'
import MetricCard from '../components/MetricCard.vue'
import TrendChart from '../components/TrendChart.vue'

const data = ref<Overview | null>(null)
const health = ref<ToolHealth | null>(null)
const loading = ref(true)
const error = ref<string | null>(null)
const healthError = ref<string | null>(null)

async function load() {
  loading.value = true
  error.value = null
  healthError.value = null
  // 健康度是"补充说明"，单独失败不该把整页统计拖成错误页。
  const [overview, toolHealth] = await Promise.allSettled([statsApi.overview(), toolApi.health()])
  if (overview.status === 'fulfilled') {
    data.value = overview.value
  } else {
    error.value = overview.reason instanceof ApiError ? overview.reason.message : '统计数据加载失败'
  }
  if (toolHealth.status === 'fulfilled') {
    health.value = toolHealth.value
  } else {
    healthError.value =
      toolHealth.reason instanceof ApiError ? toolHealth.reason.message : '数据源健康度加载失败'
  }
  loading.value = false
}

onMounted(load)

const updatedAt = computed(() =>
  data.value ? new Date(data.value.generatedAt).toLocaleString('zh-CN', { hour12: false }) : '',
)

function providerTag(line: { enabled: boolean; configured: boolean }): { text: string; cls: string } {
  if (!line.enabled) return { text: '未启用', cls: 'tag-muted' }
  if (!line.configured) return { text: '缺少密钥', cls: 'tag-warn' }
  return { text: '已启用', cls: 'tag-ok' }
}

/** 数据源状态：只有 ready 是绿的，缺配置/未接入都要能被一眼看见。 */
function sourceTag(status: string): { text: string; cls: string } {
  if (status === 'ready') return { text: '已就绪', cls: 'tag-ok' }
  if (status === 'not-configured') return { text: '缺少配置', cls: 'tag-warn' }
  if (status === 'not-implemented') return { text: '未接入', cls: 'tag-muted' }
  return { text: '演示模式', cls: 'tag-muted' }
}

function attemptTag(entry: { failure: number; lastStatus: string | null }): { text: string; cls: string } {
  if (entry.failure === 0) return { text: entry.lastStatus ?? '尚未调用', cls: 'tag-ok' }
  return { text: entry.lastStatus ?? '有降级', cls: 'tag-warn' }
}
</script>

<template>
  <div class="stack">
    <DataState :loading="loading" :error="error">
      <template v-if="data">
        <section class="metrics">
          <MetricCard
            label="注册用户"
            :value="data.users.total"
            :sub="'近 7 天新增 ' + data.users.newLast7Days + ' · 已验证 ' + data.users.verified"
          />
          <MetricCard
            label="行程方案"
            :value="data.trips.total"
            :sub="'登录 ' + data.trips.registered + ' · 匿名 ' + data.trips.anonymous"
          />
          <MetricCard
            label="景点内容"
            :value="data.content.publishedPois"
            :sub="'内容库共 ' + data.content.totalPois + ' 条 · 待处理反馈 ' + data.content.openFeedback"
          />
          <MetricCard
            label="工具调用成功率"
            :value="data.tools.successRate"
            unit="%"
            :sub="'共 ' + data.tools.total + ' 次 · 失败 ' + data.tools.failed"
          />
        </section>

        <div class="grid-2">
          <article class="panel">
            <div class="panel-head">
              <div>
                <span class="eyebrow">近 7 天</span>
                <h3>规划方案与工具调用</h3>
              </div>
              <span class="cell-sub">{{ updatedAt }}</span>
            </div>
            <div class="panel-body">
              <TrendChart v-if="data.daily.length" :points="data.daily" />
              <div v-else class="state">暂无趋势数据</div>
            </div>
          </article>

          <article class="panel">
            <div class="panel-head">
              <div>
                <span class="eyebrow">AI 供应商</span>
                <h3>降级顺序</h3>
              </div>
              <router-link class="btn btn-sm" to="/ai">运行详情</router-link>
            </div>
            <div class="panel-body is-flush">
              <table class="table">
                <thead>
                  <tr>
                    <th>顺序</th>
                    <th>供应商</th>
                    <th>模型</th>
                    <th>状态</th>
                  </tr>
                </thead>
                <tbody>
                  <tr v-for="line in data.llm.providers" :key="line.id">
                    <td class="num">{{ line.priority }}</td>
                    <td class="cell-strong">{{ line.displayName }}</td>
                    <td class="cell-sub mono">{{ line.model || '—' }}</td>
                    <td>
                      <span class="tag" :class="providerTag(line).cls">{{ providerTag(line).text }}</span>
                    </td>
                  </tr>
                </tbody>
              </table>
              <div class="pager">
                <span>当前生效：{{ data.llm.lastSuccessfulEngine ?? '尚无成功记录' }}</span>
                <span>Mock 兜底始终最后</span>
              </div>
            </div>
          </article>
        </div>

        <div class="grid-3">
          <article class="panel">
            <div class="panel-head"><h3>只读分享</h3></div>
            <div class="panel-body">
              <dl class="kv">
                <dt>累计生成</dt>
                <dd class="num">{{ data.shares.total }}</dd>
                <dt>仍有效</dt>
                <dd class="num">{{ data.shares.active }}</dd>
                <dt>被查看</dt>
                <dd class="num">{{ data.shares.views }}</dd>
              </dl>
            </div>
          </article>

          <article class="panel">
            <div class="panel-head"><h3>工具调用构成</h3></div>
            <div class="panel-body">
              <dl class="kv">
                <dt>总调用</dt>
                <dd class="num">{{ data.tools.total }}</dd>
                <dt>标记为演示</dt>
                <dd class="num">{{ data.tools.mockCalls }}</dd>
                <dt>标记为实时</dt>
                <dd class="num">{{ data.tools.realtimeCalls }}</dd>
                <dt>标记为缓存</dt>
                <dd class="num">{{ data.tools.cachedCalls }}</dd>
                <dt>其中降级兜底</dt>
                <dd class="num">{{ data.tools.degradedCalls }}</dd>
              </dl>
              <p class="hint" style="margin-top:10px">
                演示与实时分开统计，避免把 Mock 数据说成真实调用。降级兜底是演示数据的子集，
                它单独计数才能说明真实数据源这一次到底有没有接上。
              </p>
            </div>
          </article>

          <article class="panel">
            <div class="panel-head">
              <div>
                <span class="eyebrow">外部数据源</span>
                <h3>接上了没有</h3>
              </div>
              <span class="cell-sub">{{ health ? health.mode + ' 模式' : '—' }}</span>
            </div>
            <div class="panel-body is-flush">
              <div v-if="healthError" class="state">{{ healthError }}</div>
              <table v-else class="table">
                <thead>
                  <tr>
                    <th>数据</th>
                    <th>实现</th>
                    <th>状态</th>
                  </tr>
                </thead>
                <tbody>
                  <tr v-for="line in health?.sources ?? []" :key="line.id">
                    <td>{{ line.displayName }}</td>
                    <td class="cell-sub">{{ line.provider }}</td>
                    <td>
                      <span class="tag" :class="sourceTag(line.status).cls">
                        {{ sourceTag(line.status).text }}
                      </span>
                    </td>
                  </tr>
                  <tr v-if="!(health?.sources ?? []).length">
                    <td colspan="3" class="cell-sub">暂无数据源信息</td>
                  </tr>
                </tbody>
              </table>
              <ul class="source-notes">
                <li v-for="line in health?.sources ?? []" :key="'note-' + line.id">
                  <strong>{{ line.displayName }}</strong>{{ line.detail }}
                </li>
              </ul>
            </div>
          </article>

          <article class="panel">
            <div class="panel-head">
              <div>
                <span class="eyebrow">最近一次调用</span>
                <h3>工具健康度</h3>
              </div>
            </div>
            <div class="panel-body is-flush">
              <table class="table">
                <thead>
                  <tr>
                    <th>工具</th>
                    <th>成功</th>
                    <th>降级/失败</th>
                    <th>最近状态</th>
                    <th>耗时</th>
                  </tr>
                </thead>
                <tbody>
                  <tr v-for="entry in health?.tools ?? []" :key="entry.tool">
                    <td>{{ entry.tool }}</td>
                    <td class="num">{{ entry.success }}</td>
                    <td class="num">{{ entry.failure }}</td>
                    <td>
                      <span class="tag" :class="attemptTag(entry).cls">{{ attemptTag(entry).text }}</span>
                    </td>
                    <td class="num">{{ entry.lastDurationMs }} ms</td>
                  </tr>
                  <tr v-if="!(health?.tools ?? []).length">
                    <td colspan="5" class="cell-sub">还没有调用记录，先跑一次规划。</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </article>

          <article class="panel">
            <div class="panel-head"><h3>行程规模</h3></div>
            <div class="panel-body">
              <dl class="kv">
                <dt>平均天数</dt>
                <dd class="num">{{ data.trips.avgDays }} 天</dd>
                <dt>近 7 天新增</dt>
                <dd class="num">{{ data.trips.newLast7Days }}</dd>
                <dt>用户新增</dt>
                <dd class="num">{{ data.users.newLast7Days }}</dd>
              </dl>
            </div>
          </article>
        </div>

        <p class="hint">
          统计口径：全部为服务端聚合值，不包含个人明细。数据生成时间 {{ updatedAt }}（Asia/Shanghai）。
        </p>
      </template>
    </DataState>
  </div>
</template>
