<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import {
  appResourceApi,
  cultureArticleApi,
  mediaApi,
  poiApi,
  themeRouteApi,
} from '../api/endpoints'
import { ApiError, mediaUrl } from '../api/http'
import type {
  CultureArticleInput,
  CultureArticleView,
  PoiMediaView,
  PoiView,
  ThemeRouteInput,
  ThemeRouteView,
  VisualResourceView,
} from '../api/types'
import DataState from '../components/DataState.vue'

type TabKey = 'visual' | 'routes' | 'gallery' | 'culture'

/**
 * 资源槽的中文名与建议尺寸。
 *
 * 尺寸提示写在这里而不是让运营去猜：首页横幅和个人页背景的裁切比例不一样，
 * 配错比例的图在客户端会被裁掉主体。
 */
const SLOT_LABELS: Record<string, string> = {
  HOME_HERO: '首页横幅',
  PROFILE_HEADER: '个人页背景',
  TRIP_DEFAULT_COVER: '行程默认封面',
  ATTRACTION_PLACEHOLDER: '景区占位图',
  COMMUNITY_PLACEHOLDER: '旅记占位图',
  CULTURE_HEADER: '文化锦囊头图',
}

const SLOT_HINTS: Record<string, string> = {
  HOME_HERO: '建议 16:9、≥1600×900；主体偏下，上半部留出标题空间',
  PROFILE_HEADER: '建议 3:2、≥1200×800；与首页横幅同色系',
  TRIP_DEFAULT_COVER: '建议 16:9、≥1600×900；行程里没有景点图时使用',
  ATTRACTION_PLACEHOLDER: '建议 4:3、≥800×600；景区无图时的兜底',
  COMMUNITY_PLACEHOLDER: '建议 4:3、≥800×600；旅记无封面时使用',
  CULTURE_HEADER: '建议 16:9、≥1600×900；文化锦囊列表头图',
}

const CULTURE_CATEGORIES = ['中原历史', '非遗文化', '河南美食', '旅行常识', '行前准备']

const activeTab = ref<TabKey>('visual')
const loading = ref(true)
const error = ref<string | null>(null)
const notice = ref<string | null>(null)

function failure(cause: unknown, fallback: string): string {
  return cause instanceof ApiError ? cause.message : fallback
}

// ---------- 通用图片选择器 ----------
// 一个隐藏 input 服务所有上传入口：点按钮时先把"选完之后怎么用"存进闭包，
// 避免给每个槽、每条路线各挂一个 ref。
const pickerInput = ref<HTMLInputElement | null>(null)
let pendingPick: ((url: string) => void) | null = null

function pickImage(apply: (url: string) => void) {
  pendingPick = apply
  pickerInput.value?.click()
}

async function onPicked(event: Event) {
  const input = event.target as HTMLInputElement
  const file = input.files?.[0]
  input.value = ''
  if (!file || !pendingPick) return
  const apply = pendingPick
  pendingPick = null
  try {
    const result = await mediaApi.uploadImage(file)
    apply(result.url)
  } catch (cause) {
    error.value = failure(cause, '图片上传失败，请稍后再试')
  }
}

// ---------- 全局视觉资源 ----------

interface VisualForm {
  imageUrl: string
  imageCredit: string
  sourceUrl: string
  enabled: boolean
}

const visuals = ref<VisualResourceView[]>([])
const visualForms = reactive<Record<string, VisualForm>>({})
const savingSlot = ref<string | null>(null)

function fillVisualForms(rows: VisualResourceView[]) {
  for (const row of rows) {
    visualForms[row.slot] = {
      imageUrl: row.imageUrl ?? '',
      imageCredit: row.imageCredit ?? '',
      sourceUrl: row.sourceUrl ?? '',
      enabled: row.enabled,
    }
  }
}

async function saveVisual(slot: string) {
  const form = visualForms[slot]
  if (!form) return
  savingSlot.value = slot
  notice.value = null
  try {
    await appResourceApi.save(slot, {
      imageUrl: form.imageUrl || null,
      imageCredit: form.imageCredit || null,
      sourceUrl: form.sourceUrl || null,
      enabled: form.enabled,
    })
    notice.value = (SLOT_LABELS[slot] ?? slot) + ' 已保存，客户端下次刷新即可看到'
  } catch (cause) {
    error.value = failure(cause, '保存失败')
  } finally {
    savingSlot.value = null
  }
}

// ---------- 主题路线 ----------

interface RouteForm {
  title: string
  subtitle: string
  cities: string
  duration: string
  budget: string
  coverUrl: string
  highlights: string
  planningPrompt: string
  imageCredit: string
  sourceUrl: string
  published: boolean
  sortOrder: number
}

const routes = ref<ThemeRouteView[]>([])
const routeDrawerOpen = ref(false)
const editingRouteId = ref<string | null>(null)
const savingRoute = ref(false)
const routeError = ref<string | null>(null)
const routeForm = reactive<RouteForm>(emptyRouteForm())

function emptyRouteForm(): RouteForm {
  return {
    title: '',
    subtitle: '',
    cities: '',
    duration: '',
    budget: '',
    coverUrl: '',
    highlights: '',
    planningPrompt: '',
    imageCredit: '',
    sourceUrl: '',
    published: true,
    sortOrder: 100,
  }
}

function openRouteCreate() {
  editingRouteId.value = null
  routeError.value = null
  Object.assign(routeForm, emptyRouteForm())
  routeDrawerOpen.value = true
}

function openRouteEdit(row: ThemeRouteView) {
  editingRouteId.value = row.id
  routeError.value = null
  Object.assign(routeForm, {
    title: row.title,
    subtitle: row.subtitle,
    cities: row.cities ?? '',
    duration: row.duration ?? '',
    budget: row.budget ?? '',
    coverUrl: row.coverUrl ?? '',
    highlights: row.highlights.join('，'),
    planningPrompt: row.planningPrompt ?? '',
    imageCredit: row.imageCredit ?? '',
    sourceUrl: row.sourceUrl ?? '',
    published: row.published,
    sortOrder: row.sortOrder,
  })
  routeDrawerOpen.value = true
}

function splitTags(text: string): string[] {
  return text
    .split(/[，,、]/)
    .map((item) => item.trim())
    .filter((item) => item.length > 0)
}

async function submitRoute() {
  routeError.value = null
  if (!routeForm.title.trim() || !routeForm.subtitle.trim()) {
    routeError.value = '标题与副标题是必填项'
    return
  }
  const payload: ThemeRouteInput = {
    title: routeForm.title.trim(),
    subtitle: routeForm.subtitle.trim(),
    cities: routeForm.cities.trim() || null,
    duration: routeForm.duration.trim() || null,
    budget: routeForm.budget.trim() || null,
    coverUrl: routeForm.coverUrl.trim() || null,
    highlights: splitTags(routeForm.highlights),
    planningPrompt: routeForm.planningPrompt.trim() || null,
    imageCredit: routeForm.imageCredit.trim() || null,
    sourceUrl: routeForm.sourceUrl.trim() || null,
    published: routeForm.published,
    sortOrder: routeForm.sortOrder,
  }
  savingRoute.value = true
  try {
    if (editingRouteId.value) {
      await themeRouteApi.update(editingRouteId.value, payload)
    } else {
      await themeRouteApi.create(payload)
    }
    routeDrawerOpen.value = false
    await loadRoutes()
  } catch (cause) {
    routeError.value = failure(cause, '保存失败')
  } finally {
    savingRoute.value = false
  }
}

async function removeRoute(row: ThemeRouteView) {
  if (!window.confirm('确定删除主题路线「' + row.title + '」？首页将不再展示这条路线。')) return
  try {
    await themeRouteApi.remove(row.id)
    await loadRoutes()
  } catch (cause) {
    error.value = failure(cause, '删除失败')
  }
}

// ---------- 首页推荐位 ----------

const pois = ref<PoiView[]>([])
const publishedPois = computed(() => pois.value.filter((row) => row.published))

async function toggleFeatured(row: PoiView) {
  try {
    await poiApi.setFeatured(row.id, !row.homeFeatured, row.featuredSortOrder)
    await loadPois()
  } catch (cause) {
    error.value = failure(cause, '推荐位更新失败')
  }
}

async function changeFeaturedOrder(row: PoiView, value: number) {
  try {
    await poiApi.setFeatured(row.id, row.homeFeatured, value)
    await loadPois()
  } catch (cause) {
    error.value = failure(cause, '推荐位排序更新失败')
  }
}

// ---------- 景区图集 ----------

const galleryPoiId = ref('')
const galleryMedia = ref<PoiMediaView[]>([])
const galleryLoading = ref(false)
const galleryPoi = computed(() => pois.value.find((row) => row.id === galleryPoiId.value) ?? null)

async function loadGallery(poiId: string) {
  galleryPoiId.value = poiId
  galleryMedia.value = []
  if (!poiId) return
  galleryLoading.value = true
  try {
    galleryMedia.value = await poiApi.media(poiId)
  } catch (cause) {
    error.value = failure(cause, '图集加载失败')
  } finally {
    galleryLoading.value = false
  }
}

function addGalleryImage() {
  pickImage(async (url) => {
    if (!galleryPoiId.value) return
    try {
      const created = await poiApi.addMedia(galleryPoiId.value, {
        imageUrl: url,
        caption: null,
        imageCredit: null,
        sourceUrl: null,
      })
      galleryMedia.value = [...galleryMedia.value, created]
    } catch (cause) {
      error.value = failure(cause, '图片加入图集失败')
    }
  })
}

async function saveGalleryItem(item: PoiMediaView) {
  try {
    const updated = await poiApi.updateMedia(item.poiId, item.id, {
      imageUrl: item.imageUrl,
      caption: item.caption,
      imageCredit: item.imageCredit,
      sourceUrl: item.sourceUrl,
      sortOrder: item.sortOrder,
      published: item.published,
    })
    galleryMedia.value = galleryMedia.value.map((row) => (row.id === updated.id ? updated : row))
    notice.value = '图集已保存'
  } catch (cause) {
    error.value = failure(cause, '图集保存失败')
  }
}

async function removeGalleryItem(item: PoiMediaView) {
  if (!window.confirm('确定从图集中移除这张图？')) return
  try {
    await poiApi.removeMedia(item.poiId, item.id)
    galleryMedia.value = galleryMedia.value.filter((row) => row.id !== item.id)
  } catch (cause) {
    error.value = failure(cause, '移除失败')
  }
}

// ---------- 文化锦囊 ----------

interface ArticleForm {
  title: string
  summary: string
  content: string
  category: string
  coverUrl: string
  imageCredit: string
  sourceUrl: string
  published: boolean
  sortOrder: number
  author: string
  likeCount: number
}

const culture = ref<CultureArticleView[]>([])
const articleDrawerOpen = ref(false)
const editingArticleId = ref<string | null>(null)
const savingArticle = ref(false)
const articleError = ref<string | null>(null)
const articleForm = reactive<ArticleForm>(emptyArticleForm())

function emptyArticleForm(): ArticleForm {
  return {
    title: '',
    summary: '',
    content: '',
    category: '行前准备',
    coverUrl: '',
    imageCredit: '',
    sourceUrl: '',
    published: true,
    sortOrder: 100,
    author: '',
    likeCount: 0,
  }
}

function openArticleCreate() {
  editingArticleId.value = null
  articleError.value = null
  Object.assign(articleForm, emptyArticleForm())
  articleDrawerOpen.value = true
}

function openArticleEdit(row: CultureArticleView) {
  editingArticleId.value = row.id
  articleError.value = null
  Object.assign(articleForm, {
    title: row.title,
    summary: row.summary ?? '',
    content: row.content,
    category: row.category,
    coverUrl: row.coverUrl ?? '',
    imageCredit: row.imageCredit ?? '',
    sourceUrl: row.sourceUrl ?? '',
    published: row.published,
    sortOrder: row.sortOrder,
    author: row.author ?? '',
    likeCount: row.likeCount ?? 0,
  })
  articleDrawerOpen.value = true
}

async function submitArticle() {
  articleError.value = null
  if (!articleForm.title.trim() || !articleForm.content.trim()) {
    articleError.value = '标题与正文是必填项'
    return
  }
  const payload: CultureArticleInput = {
    title: articleForm.title.trim(),
    summary: articleForm.summary.trim() || null,
    content: articleForm.content.trim(),
    category: articleForm.category,
    coverUrl: articleForm.coverUrl.trim() || null,
    imageCredit: articleForm.imageCredit.trim() || null,
    sourceUrl: articleForm.sourceUrl.trim() || null,
    published: articleForm.published,
    sortOrder: articleForm.sortOrder,
    author: articleForm.author.trim() || null,
    likeCount: articleForm.likeCount,
  }
  savingArticle.value = true
  try {
    if (editingArticleId.value) {
      await cultureArticleApi.update(editingArticleId.value, payload)
    } else {
      await cultureArticleApi.create(payload)
    }
    articleDrawerOpen.value = false
    await loadCulture()
  } catch (cause) {
    articleError.value = failure(cause, '保存失败')
  } finally {
    savingArticle.value = false
  }
}

async function removeArticle(row: CultureArticleView) {
  if (!window.confirm('确定删除文章「' + row.title + '」？')) return
  try {
    await cultureArticleApi.remove(row.id)
    await loadCulture()
  } catch (cause) {
    error.value = failure(cause, '删除失败')
  }
}

// ---------- 加载 ----------

async function loadVisuals() {
  visuals.value = await appResourceApi.list()
  fillVisualForms(visuals.value)
}

async function loadRoutes() {
  routes.value = await themeRouteApi.list()
}

async function loadPois() {
  pois.value = await poiApi.list()
}

async function loadCulture() {
  culture.value = await cultureArticleApi.list()
}

async function load() {
  loading.value = true
  error.value = null
  try {
    await Promise.all([loadVisuals(), loadRoutes(), loadPois(), loadCulture()])
  } catch (cause) {
    error.value = failure(cause, '应用资源加载失败')
  } finally {
    loading.value = false
  }
}

onMounted(load)
</script>

<template>
  <div class="stack">
    <div class="tabs" role="tablist" aria-label="应用资源">
      <button
        class="tab"
        :class="{ 'is-active': activeTab === 'visual' }"
        type="button"
        role="tab"
        :aria-selected="activeTab === 'visual'"
        @click="activeTab = 'visual'"
      >
        全局视觉资源
      </button>
      <button
        class="tab"
        :class="{ 'is-active': activeTab === 'routes' }"
        type="button"
        role="tab"
        :aria-selected="activeTab === 'routes'"
        @click="activeTab = 'routes'"
      >
        首页推荐与主题路线
      </button>
      <button
        class="tab"
        :class="{ 'is-active': activeTab === 'gallery' }"
        type="button"
        role="tab"
        :aria-selected="activeTab === 'gallery'"
        @click="activeTab = 'gallery'"
      >
        景区图集
      </button>
      <button
        class="tab"
        :class="{ 'is-active': activeTab === 'culture' }"
        type="button"
        role="tab"
        :aria-selected="activeTab === 'culture'"
        @click="activeTab = 'culture'"
      >
        文化锦囊
      </button>
    </div>

    <div v-if="notice" class="notice">{{ notice }}</div>

    <DataState :loading="loading" :error="error" :empty="false">
      <div v-if="activeTab === 'visual'" class="stack">
        <p class="hint">
          这里配置的是<strong>平台控制的图片</strong>；用户头像与旅记配图由用户上传、管理员审核，不在此处替换。
          启动图 loading.png 随 APK 打包，也不在这里。
        </p>
        <article v-for="row in visuals" :key="row.slot" class="panel">
          <div class="panel-head">
            <div>
              <span class="eyebrow">{{ row.slot }}</span>
              <h3>{{ SLOT_LABELS[row.slot] ?? row.slot }}</h3>
            </div>
            <span v-if="row.updatedAt" class="cell-sub">
              更新于 {{ new Date(row.updatedAt).toLocaleString('zh-CN', { hour12: false }) }}
            </span>
          </div>
          <div class="panel-body">
            <div class="media-row">
              <div class="media-preview">
                <img
                  v-if="visualForms[row.slot]?.imageUrl"
                  :src="mediaUrl(visualForms[row.slot].imageUrl)"
                  :alt="(SLOT_LABELS[row.slot] ?? row.slot) + '预览'"
                />
                <span v-else>未配置</span>
              </div>
              <div class="media-side">
                <p class="hint">{{ SLOT_HINTS[row.slot] ?? '' }}</p>
                <input
                  v-model="visualForms[row.slot].imageUrl"
                  class="input"
                  placeholder="/media/xxx.jpg 或 https://…"
                />
                <div class="toolbar">
                  <button
                    class="btn btn-sm"
                    type="button"
                    @click="pickImage((url) => (visualForms[row.slot].imageUrl = url))"
                  >
                    上传图片
                  </button>
                  <button
                    v-if="visualForms[row.slot]?.imageUrl"
                    class="btn btn-sm btn-ghost"
                    type="button"
                    @click="visualForms[row.slot].imageUrl = ''"
                  >
                    清除
                  </button>
                  <label class="hint" style="display:flex;align-items:center;gap:6px">
                    <input v-model="visualForms[row.slot].enabled" type="checkbox" />
                    启用
                  </label>
                </div>
                <input v-model="visualForms[row.slot].imageCredit" class="input" placeholder="图片版权 / 授权说明" />
                <input v-model="visualForms[row.slot].sourceUrl" class="input" placeholder="来源链接（可空）" />
                <div class="toolbar">
                  <button
                    class="btn btn-primary btn-sm"
                    type="button"
                    :disabled="savingSlot === row.slot"
                    @click="saveVisual(row.slot)"
                  >
                    {{ savingSlot === row.slot ? '保存中…' : '保存' }}
                  </button>
                </div>
              </div>
            </div>
          </div>
        </article>
      </div>

      <div v-else-if="activeTab === 'routes'" class="stack">
        <div class="toolbar">
          <button class="btn btn-primary btn-sm" type="button" @click="openRouteCreate">新增主题路线</button>
          <span class="hint">首页"精选路线"直接读这张表；未配置时客户端退回内置的三条示范走廊。</span>
        </div>

        <article v-if="routes.length" class="panel">
          <div class="panel-body is-flush">
            <table class="table">
              <thead>
                <tr>
                  <th>路线</th>
                  <th>时长 / 预算</th>
                  <th>标签</th>
                  <th>状态</th>
                  <th>排序</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="row in routes" :key="row.id">
                  <td>
                    <div class="cell-strong">{{ row.title }}</div>
                    <div class="cell-sub">{{ row.subtitle }}</div>
                  </td>
                  <td class="cell-sub">{{ row.duration || '—' }} / {{ row.budget || '—' }}</td>
                  <td class="cell-sub">{{ row.highlights.join('、') || '—' }}</td>
                  <td>
                    <span class="tag" :class="row.published ? 'tag-ok' : 'tag-muted'">
                      {{ row.published ? '已发布' : '未发布' }}
                    </span>
                  </td>
                  <td class="num">{{ row.sortOrder }}</td>
                  <td>
                    <div class="actions">
                      <button class="btn btn-sm" type="button" @click="openRouteEdit(row)">编辑</button>
                      <button class="btn btn-sm btn-danger" type="button" @click="removeRoute(row)">删除</button>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </article>
        <DataState v-else :loading="false" :error="null" :empty="true" empty-text="还没有主题路线，先新增一条。" />

        <article class="panel">
          <div class="panel-head">
            <div>
              <span class="eyebrow">Home featured</span>
              <h3>首页热门推荐</h3>
            </div>
            <span class="cell-sub">勾选后会出现在首页"热门推荐"，最多展示 12 条</span>
          </div>
          <div class="panel-body is-flush">
            <table class="table">
              <thead>
                <tr>
                  <th>景点</th>
                  <th>城市</th>
                  <th>上首页</th>
                  <th>推荐排序</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="row in publishedPois" :key="row.id">
                  <td class="cell-strong">{{ row.name }}</td>
                  <td class="cell-sub">{{ row.city }}</td>
                  <td>
                    <input type="checkbox" :checked="row.homeFeatured" @change="toggleFeatured(row)" />
                  </td>
                  <td>
                    <input
                      class="input"
                      style="width:90px"
                      type="number"
                      :value="row.featuredSortOrder"
                      @change="changeFeaturedOrder(row, Number(($event.target as HTMLInputElement).value))"
                    />
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </article>
      </div>

      <div v-else-if="activeTab === 'gallery'" class="stack">
        <div class="toolbar">
          <select
            class="select"
            :value="galleryPoiId"
            @change="loadGallery(($event.target as HTMLSelectElement).value)"
          >
            <option value="">选择景点</option>
            <option v-for="row in pois" :key="row.id" :value="row.id">{{ row.name }} · {{ row.city }}</option>
          </select>
          <button v-if="galleryPoiId" class="btn btn-primary btn-sm" type="button" @click="addGalleryImage">
            上传并加入图集
          </button>
          <span class="hint">封面仍由"景点内容"里的主图决定；这里补充的是详情页图集。</span>
        </div>

        <DataState
          :loading="galleryLoading"
          :error="null"
          :empty="!galleryPoiId"
          empty-text="先选择一个景点，再维护它的图集。"
        >
          <p v-if="galleryPoi" class="hint">当前景点：{{ galleryPoi.name }}</p>
          <div v-if="galleryMedia.length" class="grid-2">
            <article v-for="item in galleryMedia" :key="item.id" class="panel">
              <div class="panel-body stack">
                <div class="media-preview" style="width:100%;height:160px">
                  <img :src="mediaUrl(item.imageUrl)" alt="图集图片" />
                </div>
                <input v-model="item.caption" class="input" placeholder="图注（可空）" />
                <input v-model="item.imageCredit" class="input" placeholder="图片版权 / 授权说明" />
                <input v-model="item.sourceUrl" class="input" placeholder="来源链接（可空）" />
                <div class="toolbar">
                  <input v-model.number="item.sortOrder" class="input" style="width:100px" type="number" />
                  <label class="hint" style="display:flex;align-items:center;gap:6px">
                    <input v-model="item.published" type="checkbox" />
                    展示
                  </label>
                  <button class="btn btn-sm btn-primary" type="button" @click="saveGalleryItem(item)">保存</button>
                  <button class="btn btn-sm btn-danger" type="button" @click="removeGalleryItem(item)">移除</button>
                </div>
              </div>
            </article>
          </div>
          <DataState
            v-else
            :loading="false"
            :error="null"
            :empty="true"
            empty-text="这个景点还没有图集，点上面的按钮上传第一张。"
          />
        </DataState>
      </div>

      <div v-else class="stack">
        <div class="toolbar">
          <button class="btn btn-primary btn-sm" type="button" @click="openArticleCreate">新增文章</button>
          <span class="hint">首版只允许管理员发布；文章列表为空时，首页的"文化锦囊"会显示空状态。</span>
        </div>

        <article v-if="culture.length" class="panel">
          <div class="panel-body is-flush">
            <table class="table">
              <thead>
                <tr>
                  <th>标题</th>
                  <th>分类</th>
                  <th>状态</th>
                  <th>排序</th>
                  <th>更新</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="row in culture" :key="row.id">
                  <td>
                    <div class="cell-strong">{{ row.title }}</div>
                    <div class="cell-sub">{{ row.summary || '（无摘要）' }}</div>
                  </td>
                  <td class="cell-sub">{{ row.category }}</td>
                  <td>
                    <span class="tag" :class="row.published ? 'tag-ok' : 'tag-muted'">
                      {{ row.published ? '已发布' : '草稿' }}
                    </span>
                  </td>
                  <td class="num">{{ row.sortOrder }}</td>
                  <td class="cell-sub">
                    {{ row.updatedAt ? new Date(row.updatedAt).toLocaleString('zh-CN', { hour12: false }) : '—' }}
                  </td>
                  <td>
                    <div class="actions">
                      <button class="btn btn-sm" type="button" @click="openArticleEdit(row)">编辑</button>
                      <button class="btn btn-sm btn-danger" type="button" @click="removeArticle(row)">删除</button>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </article>
        <DataState v-else :loading="false" :error="null" :empty="true" empty-text="还没有文章，先新增一篇。" />
      </div>
    </DataState>

    <!-- 统一的隐藏文件选择器 -->
    <input
      ref="pickerInput"
      type="file"
      accept="image/jpeg,image/png,image/gif"
      style="display:none"
      @change="onPicked"
    />

    <div v-if="routeDrawerOpen" class="drawer-mask" @click.self="routeDrawerOpen = false">
      <aside class="drawer">
        <header class="drawer-head">
          <div>
            <span class="eyebrow">Theme route</span>
            <h3>{{ editingRouteId ? '编辑主题路线' : '新增主题路线' }}</h3>
          </div>
          <button class="btn btn-sm btn-ghost" type="button" @click="routeDrawerOpen = false">关闭</button>
        </header>
        <div class="drawer-body stack">
          <div v-if="routeError" class="alert">{{ routeError }}</div>
          <div class="form-grid">
            <div class="field">
              <label>标题</label>
              <input v-model="routeForm.title" class="input" placeholder="郑州—洛阳" />
            </div>
            <div class="field">
              <label>副标题</label>
              <input v-model="routeForm.subtitle" class="input" placeholder="沿着伊河读懂千年中原" />
            </div>
            <div class="field">
              <label>城市</label>
              <input v-model="routeForm.cities" class="input" placeholder="郑州 · 洛阳" />
            </div>
            <div class="field">
              <label>建议时长</label>
              <input v-model="routeForm.duration" class="input" placeholder="2—3天" />
            </div>
            <div class="field">
              <label>参考预算</label>
              <input v-model="routeForm.budget" class="input" placeholder="¥680起" />
            </div>
            <div class="field">
              <label>排序（越小越靠前）</label>
              <input v-model.number="routeForm.sortOrder" class="input" type="number" />
            </div>
            <div class="field span-2">
              <label>标签（用逗号分隔）</label>
              <input v-model="routeForm.highlights" class="input" placeholder="龙门石窟，博物馆，古都深度游" />
            </div>
            <div class="field span-2">
              <label>规划提示词（点这条路线时带去规划页）</label>
              <textarea v-model="routeForm.planningPrompt" class="textarea"></textarea>
            </div>
            <div class="field span-2">
              <label>封面图</label>
              <div class="media-row">
                <div class="media-preview">
                  <img v-if="routeForm.coverUrl" :src="mediaUrl(routeForm.coverUrl)" alt="封面预览" />
                  <span v-else>暂无图片</span>
                </div>
                <div class="media-side">
                  <input v-model="routeForm.coverUrl" class="input" placeholder="/media/xxx.jpg 或 https://…" />
                  <div class="toolbar">
                    <button class="btn btn-sm" type="button" @click="pickImage((url) => (routeForm.coverUrl = url))">
                      上传图片
                    </button>
                    <button
                      v-if="routeForm.coverUrl"
                      class="btn btn-sm btn-ghost"
                      type="button"
                      @click="routeForm.coverUrl = ''"
                    >
                      清除
                    </button>
                  </div>
                </div>
              </div>
            </div>
            <div class="field span-2">
              <label>图片版权 / 授权说明</label>
              <input v-model="routeForm.imageCredit" class="input" />
            </div>
            <div class="field span-2">
              <label>来源链接</label>
              <input v-model="routeForm.sourceUrl" class="input" />
            </div>
            <div class="field span-2">
              <label style="display:flex;align-items:center;gap:8px">
                <input v-model="routeForm.published" type="checkbox" />
                在首页展示
              </label>
            </div>
          </div>
        </div>
        <footer class="drawer-foot">
          <button class="btn" type="button" @click="routeDrawerOpen = false">取消</button>
          <button class="btn btn-primary" type="button" :disabled="savingRoute" @click="submitRoute">
            {{ savingRoute ? '保存中…' : '保存' }}
          </button>
        </footer>
      </aside>
    </div>

    <div v-if="articleDrawerOpen" class="drawer-mask" @click.self="articleDrawerOpen = false">
      <aside class="drawer">
        <header class="drawer-head">
          <div>
            <span class="eyebrow">Culture</span>
            <h3>{{ editingArticleId ? '编辑文章' : '新增文章' }}</h3>
          </div>
          <button class="btn btn-sm btn-ghost" type="button" @click="articleDrawerOpen = false">关闭</button>
        </header>
        <div class="drawer-body stack">
          <div v-if="articleError" class="alert">{{ articleError }}</div>
          <div class="form-grid">
            <div class="field">
              <label>标题</label>
              <input v-model="articleForm.title" class="input" placeholder="第一次去洛阳，先看懂这三处" />
            </div>
            <div class="field">
              <label>分类</label>
              <select v-model="articleForm.category" class="select">
                <option v-for="item in CULTURE_CATEGORIES" :key="item" :value="item">{{ item }}</option>
              </select>
            </div>
            <div class="field">
              <label>作者 / 署名</label>
              <input v-model="articleForm.author" class="input" placeholder="留空则客户端不显示作者" />
            </div>
            <div class="field">
              <label>点赞数（内容自带，非站内真实点赞）</label>
              <input v-model.number="articleForm.likeCount" class="input" type="number" min="0" />
            </div>
            <div class="field span-2">
              <label>摘要（列表页显示）</label>
              <input v-model="articleForm.summary" class="input" />
            </div>
            <div class="field span-2">
              <label>正文</label>
              <textarea v-model="articleForm.content" class="textarea prompt-editor"></textarea>
            </div>
            <div class="field span-2">
              <label>封面图</label>
              <div class="media-row">
                <div class="media-preview">
                  <img v-if="articleForm.coverUrl" :src="mediaUrl(articleForm.coverUrl)" alt="封面预览" />
                  <span v-else>暂无图片</span>
                </div>
                <div class="media-side">
                  <input v-model="articleForm.coverUrl" class="input" placeholder="/media/xxx.jpg 或 https://…" />
                  <div class="toolbar">
                    <button class="btn btn-sm" type="button" @click="pickImage((url) => (articleForm.coverUrl = url))">
                      上传图片
                    </button>
                    <button
                      v-if="articleForm.coverUrl"
                      class="btn btn-sm btn-ghost"
                      type="button"
                      @click="articleForm.coverUrl = ''"
                    >
                      清除
                    </button>
                  </div>
                </div>
              </div>
            </div>
            <div class="field">
              <label>图片版权 / 授权说明</label>
              <input v-model="articleForm.imageCredit" class="input" />
            </div>
            <div class="field">
              <label>来源链接</label>
              <input v-model="articleForm.sourceUrl" class="input" />
            </div>
            <div class="field">
              <label>排序（越小越靠前）</label>
              <input v-model.number="articleForm.sortOrder" class="input" type="number" />
            </div>
            <div class="field">
              <label style="display:flex;align-items:center;gap:8px">
                <input v-model="articleForm.published" type="checkbox" />
                发布
              </label>
            </div>
          </div>
        </div>
        <footer class="drawer-foot">
          <button class="btn" type="button" @click="articleDrawerOpen = false">取消</button>
          <button class="btn btn-primary" type="button" :disabled="savingArticle" @click="submitArticle">
            {{ savingArticle ? '保存中…' : '保存' }}
          </button>
        </footer>
      </aside>
    </div>
  </div>
</template>
