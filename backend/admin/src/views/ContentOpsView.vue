<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import { poiApi } from '../api/endpoints'
import { ApiError } from '../api/http'
import type { PoiView } from '../api/types'
import DataState from '../components/DataState.vue'

type TabKey = 'cities' | 'images'

const router = useRouter()
const activeTab = ref<TabKey>('cities')
const rows = ref<PoiView[]>([])
const loading = ref(true)
const error = ref<string | null>(null)

interface CityStat {
  city: string
  total: number
  published: number
  coordinate: number
  imageRegistered: number
}

interface CategoryStat {
  category: string
  total: number
  published: number
  cityCount: number
}

function normalize(row: PoiView): PoiView {
  return {
    ...row,
    imageStatus: row.imageStatus || 'UNKNOWN',
    imageStatusLabel: row.imageStatusLabel || '未判定',
    imageGaps: row.imageGaps ?? [],
  }
}

async function load() {
  loading.value = true
  error.value = null
  try {
    rows.value = (await poiApi.list()).map(normalize)
  } catch (cause) {
    error.value = cause instanceof ApiError ? cause.message : '内容数据加载失败'
  } finally {
    loading.value = false
  }
}

onMounted(load)

const publishedCount = computed(() => rows.value.filter((row) => row.published).length)
const coordinateCount = computed(() => rows.value.filter(hasCoordinate).length)
const imageRegisteredCount = computed(
  () => rows.value.filter((row) => row.imageStatus === 'REGISTERED').length,
)
const imageTodoCount = computed(() => rows.value.length - imageRegisteredCount.value)
const missingImageCount = computed(
  () => rows.value.filter((row) => row.imageStatus === 'MISSING').length,
)
const unlicensedImageCount = computed(
  () => rows.value.filter((row) => row.imageStatus === 'UNLICENSED').length,
)

const cityStats = computed<CityStat[]>(() => {
  const map = new Map<string, CityStat>()
  for (const row of rows.value) {
    const city = row.city || '未填写'
    const current = map.get(city) ?? {
      city,
      total: 0,
      published: 0,
      coordinate: 0,
      imageRegistered: 0,
    }
    current.total += 1
    if (row.published) current.published += 1
    if (hasCoordinate(row)) current.coordinate += 1
    if (row.imageStatus === 'REGISTERED') current.imageRegistered += 1
    map.set(city, current)
  }
  return [...map.values()].sort((a, b) => b.total - a.total || a.city.localeCompare(b.city, 'zh-CN'))
})

const categoryStats = computed<CategoryStat[]>(() => {
  const map = new Map<string, { total: number; published: number; cities: Set<string> }>()
  for (const row of rows.value) {
    const category = row.category || '未分类'
    const current = map.get(category) ?? { total: 0, published: 0, cities: new Set<string>() }
    current.total += 1
    if (row.published) current.published += 1
    current.cities.add(row.city || '未填写')
    map.set(category, current)
  }
  return [...map.entries()]
    .map(([category, value]) => ({
      category,
      total: value.total,
      published: value.published,
      cityCount: value.cities.size,
    }))
    .sort((a, b) => b.total - a.total || a.category.localeCompare(b.category, 'zh-CN'))
})

const maxCategoryTotal = computed(
  () => categoryStats.value.reduce((max, item) => Math.max(max, item.total), 0) || 1,
)

const imageTodoRows = computed(() =>
  rows.value
    .filter((row) => row.imageStatus !== 'REGISTERED')
    .sort((a, b) => imageRank(a.imageStatus) - imageRank(b.imageStatus)
      || a.city.localeCompare(b.city, 'zh-CN')
      || a.name.localeCompare(b.name, 'zh-CN')),
)

function hasCoordinate(row: PoiView): boolean {
  return row.lng !== null && row.lng !== undefined && row.lat !== null && row.lat !== undefined
}

function percent(part: number, total: number): number {
  if (total <= 0) return 0
  return Math.round((part / total) * 100)
}

function imageRank(status: string): number {
  if (status === 'MISSING') return 0
  if (status === 'PLACEHOLDER') return 1
  if (status === 'UNLICENSED') return 2
  return 3
}

function imageTagClass(status: string): string {
  if (status === 'REGISTERED') return 'tag-ok'
  if (status === 'UNLICENSED') return 'tag-warn'
  return 'tag-danger'
}

function openPoi(id: string) {
  router.push({ name: 'pois', query: { focus: id } })
}

function shortDate(value: string): string {
  return new Date(value).toLocaleString('zh-CN', { hour12: false })
}
</script>

<template>
  <div class="stack">
    <div class="tabs" role="tablist" aria-label="内容运营视图">
      <button
        class="tab"
        :class="{ 'is-active': activeTab === 'cities' }"
        type="button"
        role="tab"
        :aria-selected="activeTab === 'cities'"
        @click="activeTab = 'cities'"
      >
        城市与主题
      </button>
      <button
        class="tab"
        :class="{ 'is-active': activeTab === 'images' }"
        type="button"
        role="tab"
        :aria-selected="activeTab === 'images'"
        @click="activeTab = 'images'"
      >
        图片与版权
      </button>
    </div>

    <DataState
      :loading="loading"
      :error="error"
      :empty="!rows.length"
      empty-text="内容库里还没有景点，先到景点管理里新增一条。"
    >
      <template v-if="activeTab === 'cities'">
        <section class="metrics">
          <dl class="metric">
            <dt>覆盖城市</dt>
            <dd>{{ cityStats.length }}<span class="unit">个</span></dd>
            <div class="sub">按景点内容聚合，不依赖外部地理编码</div>
          </dl>
          <dl class="metric">
            <dt>内容总量</dt>
            <dd>{{ rows.length }}<span class="unit">条</span></dd>
            <div class="sub">已上架 {{ publishedCount }} 条</div>
          </dl>
          <dl class="metric">
            <dt>坐标覆盖</dt>
            <dd>{{ percent(coordinateCount, rows.length) }}<span class="unit">%</span></dd>
            <div class="sub">{{ coordinateCount }} / {{ rows.length }} 可参与地图打点</div>
          </dl>
          <dl class="metric">
            <dt>主题标签</dt>
            <dd>{{ categoryStats.length }}<span class="unit">类</span></dd>
            <div class="sub">用于游客端筛选与内容推荐</div>
          </dl>
        </section>

        <div class="grid-2">
          <article class="panel">
            <div class="panel-head">
              <div>
                <span class="eyebrow">City coverage</span>
                <h3>城市内容覆盖</h3>
              </div>
              <button class="btn btn-sm" type="button" @click="router.push('/pois')">
                管理景点
              </button>
            </div>
            <div class="panel-body is-flush">
              <table class="table">
                <thead>
                  <tr>
                    <th>城市</th>
                    <th>景点</th>
                    <th>上架</th>
                    <th>坐标</th>
                    <th>配图</th>
                  </tr>
                </thead>
                <tbody>
                  <tr v-for="item in cityStats" :key="item.city">
                    <td class="cell-strong">{{ item.city }}</td>
                    <td class="num">{{ item.total }}</td>
                    <td class="num">{{ item.published }} / {{ item.total }}</td>
                    <td class="num">{{ percent(item.coordinate, item.total) }}%</td>
                    <td class="num">{{ percent(item.imageRegistered, item.total) }}%</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </article>

          <article class="panel">
            <div class="panel-head">
              <div>
                <span class="eyebrow">Theme mix</span>
                <h3>主题标签分布</h3>
              </div>
            </div>
            <div class="panel-body">
              <ul class="bar-list">
                <li v-for="item in categoryStats" :key="item.category">
                  <div class="split">
                    <strong>{{ item.category }}</strong>
                    <span class="cell-sub num">{{ item.total }} 条 · {{ item.cityCount }} 城</span>
                  </div>
                  <div class="bar-track">
                    <div
                      class="bar-fill"
                      :style="{ width: percent(item.total, maxCategoryTotal) + '%' }"
                    ></div>
                  </div>
                </li>
              </ul>
            </div>
          </article>
        </div>

        <article class="panel">
          <div class="panel-head">
            <div>
              <span class="eyebrow">Content health</span>
              <h3>内容健康度</h3>
            </div>
          </div>
          <div class="panel-body">
            <div class="health-grid">
              <div>
                <span class="cell-sub">已上架比例</span>
                <strong class="num">{{ percent(publishedCount, rows.length) }}%</strong>
              </div>
              <div>
                <span class="cell-sub">坐标覆盖</span>
                <strong class="num">{{ percent(coordinateCount, rows.length) }}%</strong>
              </div>
              <div>
                <span class="cell-sub">配图登记</span>
                <strong class="num">{{ percent(imageRegisteredCount, rows.length) }}%</strong>
              </div>
              <div>
                <span class="cell-sub">待处理配图</span>
                <strong class="num" :class="{ 'is-warn': imageTodoCount > 0 }">{{ imageTodoCount }}</strong>
              </div>
            </div>
          </div>
        </article>
      </template>

      <template v-else>
        <section class="metrics">
          <dl class="metric">
            <dt>已登记</dt>
            <dd>{{ imageRegisteredCount }}<span class="unit">条</span></dd>
            <div class="sub">图片与版权说明都齐全</div>
          </dl>
          <dl class="metric">
            <dt>待处理</dt>
            <dd>{{ imageTodoCount }}<span class="unit">条</span></dd>
            <div class="sub">按缺图、占位图、未登记排序</div>
          </dl>
          <dl class="metric">
            <dt>缺图</dt>
            <dd>{{ missingImageCount }}<span class="unit">条</span></dd>
            <div class="sub">游客端只能看到主题占位</div>
          </dl>
          <dl class="metric">
            <dt>版权未登记</dt>
            <dd>{{ unlicensedImageCount }}<span class="unit">条</span></dd>
            <div class="sub">有图但没有可追溯授权说明</div>
          </dl>
        </section>

        <article class="panel">
          <div class="panel-head">
            <div>
              <span class="eyebrow">Image audit</span>
              <h3>配图待办</h3>
            </div>
            <span class="cell-sub">状态由服务端现算，保存后自动刷新</span>
          </div>
          <div class="panel-body is-flush">
            <table class="table">
              <thead>
                <tr>
                  <th>景点</th>
                  <th>城市</th>
                  <th>状态</th>
                  <th>待补项</th>
                  <th>更新时间</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="row in imageTodoRows" :key="row.id">
                  <td>
                    <div class="cell-strong">{{ row.name }}</div>
                    <div class="cell-sub mono">{{ row.id }}</div>
                  </td>
                  <td>{{ row.city }}</td>
                  <td>
                    <span class="tag" :class="imageTagClass(row.imageStatus)">
                      {{ row.imageStatusLabel }}
                    </span>
                  </td>
                  <td class="cell-sub">{{ row.imageGaps.join('、') || '未提供待补说明' }}</td>
                  <td class="cell-sub">{{ shortDate(row.updatedAt) }}</td>
                  <td>
                    <div class="actions">
                      <button class="btn btn-sm" type="button" @click="openPoi(row.id)">
                        去处理
                      </button>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </article>
      </template>
    </DataState>
  </div>
</template>
