<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { useRoute } from 'vue-router'
import { mediaApi, poiApi } from '../api/endpoints'
import { ApiError, mediaUrl } from '../api/http'
import type { PoiInput, PoiView } from '../api/types'
import DataState from '../components/DataState.vue'

const route = useRoute()
const rows = ref<PoiView[]>([])
const loading = ref(true)
const error = ref<string | null>(null)
const keyword = ref('')

const drawerOpen = ref(false)
const editingId = ref<string | null>(null)
const saving = ref(false)
const formError = ref<string | null>(null)

/**
 * 配图筛选。
 *
 * 判定规则不在前端 —— 每个景点带着服务端算好的 imageStatus 过来，管理台只负责
 * 统计与筛选。规则放在一处，就不会出现"后台说已登记、接口说占位图"这种两套口径。
 */
type ImageFilter = 'all' | 'todo' | 'done'
const imageFilter = ref<ImageFilter>('all')

const imageTodoCount = computed(
  () => rows.value.filter((row) => row.imageStatus !== 'REGISTERED').length,
)

const visibleRows = computed(() => {
  if (imageFilter.value === 'all') return rows.value
  const wantTodo = imageFilter.value === 'todo'
  return rows.value.filter((row) => (row.imageStatus !== 'REGISTERED') === wantTodo)
})

/** 编辑中的那一条，用来在抽屉里显示"这份配图现在差什么"。 */
const editingAudit = computed(
  () => rows.value.find((row) => row.id === editingId.value) ?? null,
)

function imageTagClass(status: string): string {
  if (status === 'REGISTERED') return 'tag-ok'
  if (status === 'UNLICENSED') return 'tag-warn'
  return 'tag-danger'
}

const DATA_STATUSES = ['系统资料', '演示数据', '缓存数据', '实时数据']
const CATEGORIES = ['人文古迹', '山水秘境', '宋韵生活', '博物馆', '美食街区', '城市漫游']

/**
 * 表单里的经纬度按字符串编辑。
 *
 * 两个坑：number 输入框清空后是空字符串，直接提交会被后端当成非法数字；
 * 而"没填坐标"和"坐标恰好是 0"也必须能区分。统一用字符串表示，
 * 转换规则只写在 toCoordinate() 一处，避免每个出口各判一次。
 */
interface PoiFormState {
  name: string
  city: string
  category: string
  imageUrl: string | null
  description: string
  ticketFrom: number
  duration: string
  suitability: string | null
  weatherTip: string | null
  dataStatus: string
  imageCredit: string | null
  sourceUrl: string | null
  lng: string
  lat: string
  published: boolean
  sortOrder: number
}

/** 中国大陆的经纬度范围，用来挡住明显填反或手滑的数字。 */
const LNG_RANGE: [number, number] = [73, 136]
const LAT_RANGE: [number, number] = [3, 54]

function emptyForm(): PoiFormState {
  return {
    name: '',
    city: '',
    category: '人文古迹',
    imageUrl: '',
    description: '',
    ticketFrom: 0,
    duration: '',
    suitability: '',
    weatherTip: '',
    dataStatus: '系统资料',
    imageCredit: '',
    sourceUrl: '',
    lng: '',
    lat: '',
    published: true,
    sortOrder: 100,
  }
}

const form = reactive<PoiFormState>(emptyForm())

const fileInput = ref<HTMLInputElement | null>(null)
const uploading = ref(false)
const uploadError = ref<string | null>(null)

function resetForm() {
  Object.assign(form, emptyForm())
  uploadError.value = null
  geoHint.value = null
  geoTrusted.value = null
}

function pickImage() {
  uploadError.value = null
  fileInput.value?.click()
}

async function onFilePicked(event: Event) {
  const input = event.target as HTMLInputElement
  const file = input.files?.[0]
  // 立刻清空，保证连续选择同一个文件也会触发 change。
  input.value = ''
  if (!file) return

  uploading.value = true
  uploadError.value = null
  try {
    const result = await mediaApi.uploadImage(file)
    form.imageUrl = result.url
  } catch (cause) {
    uploadError.value = cause instanceof ApiError ? cause.message : '图片上传失败，请稍后再试'
  } finally {
    uploading.value = false
  }
}

const geoLoading = ref(false)
const geoHint = ref<string | null>(null)
const geoTrusted = ref<boolean | null>(null)

function toCoordinate(text: string): number | null {
  const trimmed = text.trim()
  if (!trimmed) return null
  const value = Number(trimmed)
  return Number.isFinite(value) ? value : null
}

function coordinateText(value: number | null | undefined): string {
  return value === null || value === undefined ? '' : String(value)
}

function hasCoordinate(row: PoiView): boolean {
  return row.lng !== null && row.lng !== undefined && row.lat !== null && row.lat !== undefined
}

function coordinateLabel(row: PoiView): string {
  if (!hasCoordinate(row)) return '未配置'
  return Number(row.lng).toFixed(4) + ', ' + Number(row.lat).toFixed(4)
}

/**
 * 按名称解析坐标。
 *
 * 只回填表单、不落库，所以可以放心地反复试；后端不采信时不会给出坐标，
 * 这里也就不会把一个"城市中心"顺手存进内容库。
 */
async function resolveCoordinate() {
  geoHint.value = null
  geoTrusted.value = null
  if (!form.name.trim()) {
    geoHint.value = '请先填写景点名称，再解析坐标。'
    return
  }
  geoLoading.value = true
  try {
    const result = await poiApi.geocode(form.name.trim(), form.city.trim() || undefined)
    geoTrusted.value = result.trusted
    geoHint.value = result.message
    if (result.trusted && result.lng !== null && result.lat !== null) {
      form.lng = coordinateText(result.lng)
      form.lat = coordinateText(result.lat)
    }
  } catch (cause) {
    geoTrusted.value = false
    geoHint.value = cause instanceof ApiError ? cause.message : '坐标解析失败，请手工填写经纬度'
  } finally {
    geoLoading.value = false
  }
}

function clearCoordinate() {
  form.lng = ''
  form.lat = ''
  geoHint.value = null
  geoTrusted.value = null
}

/**
 * 兜住"后端还没重启"的情况。
 *
 * 配图审计字段是服务端新增的；如果运营台连的是旧进程，这些字段会整个缺失。
 * 与其让表格在 `.length` 上直接抛错，不如退化成一个明确的"未判定"，
 * 并且按待处理计 —— 拿不准的时候，宁可多提醒一次。
 */
function normalizeAudit(row: PoiView): PoiView {
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
    const listed = await poiApi.list(keyword.value.trim() || undefined)
    rows.value = listed.map(normalizeAudit)
  } catch (cause) {
    error.value = cause instanceof ApiError ? cause.message : '景点列表加载失败'
  } finally {
    loading.value = false
  }
}

onMounted(async () => {
  await load()
  openFocusedRow()
})

/** 内容运营页会带 ?focus=<id> 跳进来，直接把对应景点抽屉打开。 */
function openFocusedRow() {
  const raw = route.query.focus
  const id = Array.isArray(raw) ? raw[0] : raw
  if (!id) return
  const row = rows.value.find((item) => item.id === id)
  if (row) openEdit(row)
}

function openCreate() {
  editingId.value = null
  formError.value = null
  resetForm()
  drawerOpen.value = true
}

function openEdit(row: PoiView) {
  editingId.value = row.id
  formError.value = null
  Object.assign(form, {
    name: row.name,
    city: row.city,
    category: row.category,
    imageUrl: row.imageUrl ?? '',
    description: row.description,
    ticketFrom: row.ticketFrom,
    duration: row.duration,
    suitability: row.suitability ?? '',
    weatherTip: row.weatherTip ?? '',
    dataStatus: row.dataStatus,
    imageCredit: row.imageCredit ?? '',
    sourceUrl: row.sourceUrl ?? '',
    lng: coordinateText(row.lng),
    lat: coordinateText(row.lat),
    published: row.published,
    sortOrder: row.sortOrder,
  })
  drawerOpen.value = true
}

async function submit() {
  formError.value = null
  if (!form.name.trim() || !form.city.trim() || !form.description.trim() || !form.duration.trim()) {
    formError.value = '名称、城市、一句话介绍和建议游玩时长是必填项'
    return
  }
  const lng = toCoordinate(form.lng)
  const lat = toCoordinate(form.lat)
  const hasLng = form.lng.trim().length > 0
  const hasLat = form.lat.trim().length > 0
  if (hasLng !== hasLat) {
    formError.value = '经度和纬度要么都填，要么都留空'
    return
  }
  if (hasLng && (lng === null || lat === null)) {
    formError.value = '经纬度必须是数字，请检查是否填了多余字符'
    return
  }
  if (lng !== null && lat !== null
    && (lng < LNG_RANGE[0] || lng > LNG_RANGE[1] || lat < LAT_RANGE[0] || lat > LAT_RANGE[1])) {
    formError.value = '经纬度超出中国大陆范围（经度 73—136，纬度 3—54），请检查是否填反了'
    return
  }

  saving.value = true
  try {
    const payload: PoiInput = { ...form, lng, lat }
    if (editingId.value) {
      await poiApi.update(editingId.value, payload)
    } else {
      await poiApi.create(payload)
    }
    drawerOpen.value = false
    await load()
  } catch (cause) {
    formError.value = cause instanceof ApiError ? cause.message : '保存失败，请稍后再试'
  } finally {
    saving.value = false
  }
}

async function togglePublish(row: PoiView) {
  try {
    await poiApi.setPublished(row.id, !row.published)
    await load()
  } catch (cause) {
    error.value = cause instanceof ApiError ? cause.message : '状态更新失败'
  }
}

async function remove(row: PoiView) {
  if (!window.confirm('确定删除「' + row.name + '」？该操作会立即从游客端下架。')) return
  try {
    await poiApi.remove(row.id)
    await load()
  } catch (cause) {
    error.value = cause instanceof ApiError ? cause.message : '删除失败'
  }
}

function shortDate(value: string): string {
  return new Date(value).toLocaleString('zh-CN', { hour12: false })
}
</script>

<template>
  <div class="stack">
    <div class="toolbar">
      <input
        v-model="keyword"
        class="input"
        placeholder="搜索名称、城市或分类"
        @keyup.enter="load"
      />
      <button class="btn btn-sm" type="button" @click="load">搜索</button>
      <button class="btn btn-primary btn-sm" type="button" @click="openCreate">新增景点</button>
      <span class="hint">游客端 /api/pois 直接读这张表，保存后立即生效。</span>
    </div>

    <article v-if="rows.length" class="panel">
      <div class="panel-head">
        <div>
          <span class="eyebrow">Image audit</span>
          <h3>配图与版权</h3>
        </div>
        <div class="toolbar">
          <button
            class="btn btn-sm"
            :class="{ 'btn-primary': imageFilter === 'all' }"
            type="button"
            @click="imageFilter = 'all'"
          >
            全部 {{ rows.length }}
          </button>
          <button
            class="btn btn-sm"
            :class="{ 'btn-primary': imageFilter === 'todo' }"
            type="button"
            @click="imageFilter = 'todo'"
          >
            待处理 {{ imageTodoCount }}
          </button>
          <button
            class="btn btn-sm"
            :class="{ 'btn-primary': imageFilter === 'done' }"
            type="button"
            @click="imageFilter = 'done'"
          >
            已登记 {{ rows.length - imageTodoCount }}
          </button>
        </div>
      </div>
      <div class="panel-body">
        <p v-if="imageTodoCount" class="hint">
          还有 {{ imageTodoCount }} 个景点的配图没闭环：占位示例图要换成有授权的河南实景图，
          换完在表单里登记「图片版权 / 授权说明」。状态由服务端现算，保存后自动刷新，
          不需要额外点一次重新审计。
        </p>
        <p v-else class="hint">所有景点的配图与版权信息都已登记。</p>
      </div>
    </article>

    <article class="panel">
      <div class="panel-body is-flush">
        <DataState
          :loading="loading"
          :error="error"
          :empty="!visibleRows.length"
          empty-text="当前筛选下没有景点，换个条件看看。"
        >
          <table class="table">
            <thead>
              <tr>
                <th>景点</th>
                <th>城市</th>
                <th>分类</th>
                <th>坐标</th>
                <th>配图</th>
                <th>门票</th>
                <th>数据状态</th>
                <th>上架</th>
                <th>更新时间</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="row in visibleRows" :key="row.id">
                <td>
                  <div class="cell-strong">{{ row.name }}</div>
                  <div class="cell-sub mono">{{ row.id }}</div>
                </td>
                <td>{{ row.city }}</td>
                <td><span class="tag tag-plain">{{ row.category }}</span></td>
                <td>
                  <span v-if="hasCoordinate(row)" class="cell-sub mono">{{ coordinateLabel(row) }}</span>
                  <span v-else class="hint">未配置</span>
                </td>
                <td>
                  <span class="tag" :class="imageTagClass(row.imageStatus)">
                    {{ row.imageStatusLabel }}
                  </span>
                  <div v-if="row.imageGaps.length" class="cell-sub">
                    {{ row.imageGaps.join('、') }}
                  </div>
                </td>
                <td class="num">¥{{ row.ticketFrom }} 起</td>
                <td>
                  <span class="tag" :class="row.dataStatus === '实时数据' ? 'tag-ok' : 'tag-muted'">
                    {{ row.dataStatus }}
                  </span>
                </td>
                <td>
                  <span class="tag" :class="row.published ? 'tag-ok' : 'tag-warn'">
                    {{ row.published ? '已上架' : '已下架' }}
                  </span>
                </td>
                <td class="cell-sub">{{ shortDate(row.updatedAt) }}</td>
                <td>
                  <div class="actions">
                    <button class="btn btn-sm btn-ghost" type="button" @click="openEdit(row)">编辑</button>
                    <button class="btn btn-sm btn-ghost" type="button" @click="togglePublish(row)">
                      {{ row.published ? '下架' : '上架' }}
                    </button>
                    <button class="btn btn-sm btn-danger" type="button" @click="remove(row)">删除</button>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </DataState>
      </div>
    </article>

    <div v-if="drawerOpen" class="drawer-mask" @click.self="drawerOpen = false">
      <aside class="drawer">
        <header class="drawer-head">
          <div>
            <span class="eyebrow">Content</span>
            <h3>{{ editingId ? '编辑景点' : '新增景点' }}</h3>
          </div>
          <button class="btn btn-sm btn-ghost" type="button" @click="drawerOpen = false">关闭</button>
        </header>

        <div class="drawer-body stack">
          <div v-if="formError" class="alert">{{ formError }}</div>
          <div class="form-grid">
            <div class="field">
              <label>景点名称</label>
              <input v-model="form.name" class="input" placeholder="龙门石窟" />
            </div>
            <div class="field">
              <label>所属城市</label>
              <input v-model="form.city" class="input" placeholder="洛阳" />
            </div>
            <div class="field">
              <label>主题分类</label>
              <select v-model="form.category" class="select">
                <option v-for="item in CATEGORIES" :key="item" :value="item">{{ item }}</option>
              </select>
            </div>
            <div class="field">
              <label>门票参考（元）</label>
              <input v-model.number="form.ticketFrom" class="input" type="number" min="0" />
            </div>
            <div class="field">
              <label>建议游玩时长</label>
              <input v-model="form.duration" class="input" placeholder="3—4小时" />
            </div>
            <div class="field">
              <label>适合人群</label>
              <input v-model="form.suitability" class="input" placeholder="历史文化爱好者" />
            </div>
            <div class="field span-2">
              <label>一句话介绍</label>
              <textarea v-model="form.description" class="textarea" placeholder="一壁看尽千年风物…"></textarea>
            </div>
            <div class="field span-2">
              <label>天气提示</label>
              <input v-model="form.weatherTip" class="input" placeholder="雨天仍可游览，建议穿防滑鞋" />
            </div>
            <div class="field span-2">
              <label>经纬度坐标（百度 BD09）</label>
              <div class="coord-row">
                <input v-model="form.lng" class="input" inputmode="decimal" placeholder="经度，例如 112.469100" />
                <input v-model="form.lat" class="input" inputmode="decimal" placeholder="纬度，例如 34.555400" />
                <button class="btn btn-sm" type="button" :disabled="geoLoading" @click="resolveCoordinate">
                  {{ geoLoading ? '解析中…' : '按名称解析' }}
                </button>
                <button
                  v-if="form.lng || form.lat"
                  class="btn btn-sm btn-ghost"
                  type="button"
                  @click="clearCoordinate"
                >
                  清除
                </button>
              </div>
              <p class="hint">
                留空也能上架，只是这个景点不会出现在行程地图上；填了就会优先使用这里的坐标。
              </p>
              <p
                v-if="geoHint"
                class="hint"
                :style="{ color: geoTrusted ? 'var(--celadon-deep)' : 'var(--kiln)' }"
              >
                {{ geoHint }}
              </p>
            </div>
            <div class="field span-2">
              <label>景点主图</label>
              <div class="media-row">
                <div class="media-preview">
                  <img
                    v-if="form.imageUrl"
                    :src="mediaUrl(form.imageUrl)"
                    alt="景点主图预览"
                  />
                  <span v-else>暂无图片</span>
                </div>
                <div class="media-side">
                  <input v-model="form.imageUrl" class="input" placeholder="/media/xxx.jpg 或 https://…" />
                  <div class="toolbar">
                    <button class="btn btn-sm" type="button" :disabled="uploading" @click="pickImage">
                      {{ uploading ? '上传中…' : '上传本地图片' }}
                    </button>
                    <button
                      v-if="form.imageUrl"
                      class="btn btn-sm btn-ghost"
                      type="button"
                      @click="form.imageUrl = ''"
                    >
                      清除
                    </button>
                    <span class="hint">JPEG / PNG / GIF，单张不超过 8MB</span>
                  </div>
                  <p v-if="uploadError" class="hint" style="color:var(--kiln)">{{ uploadError }}</p>
                </div>
              </div>
              <input
                ref="fileInput"
                type="file"
                accept="image/jpeg,image/png,image/gif"
                style="display:none"
                @change="onFilePicked"
              />
            </div>
            <div v-if="editingAudit" class="field span-2">
              <div v-if="editingAudit.imageStatus !== 'REGISTERED'" class="alert">
                当前配图状态：{{ editingAudit.imageStatusLabel }} —— 待补：{{
                  editingAudit.imageGaps.join('、')
                }}
              </div>
              <p v-else class="hint">当前配图状态：{{ editingAudit.imageStatusLabel }}，可以交付。</p>
              <p class="hint">
                状态按当前图片与版权信息现算：图片换成本地上传、并填好版权说明之后，这一条就会转成"已登记"。
              </p>
            </div>
            <div class="field span-2">
              <label>图片版权 / 授权说明</label>
              <input v-model="form.imageCredit" class="input" placeholder="摄影师 / 来源 / 授权方式" />
            </div>
            <div class="field span-2">
              <label>数据来源链接</label>
              <input v-model="form.sourceUrl" class="input" placeholder="景区官网、文旅厅公示页等" />
            </div>
            <div class="field">
              <label>数据状态</label>
              <select v-model="form.dataStatus" class="select">
                <option v-for="item in DATA_STATUSES" :key="item" :value="item">{{ item }}</option>
              </select>
            </div>
            <div class="field">
              <label>排序权重（越小越靠前）</label>
              <input v-model.number="form.sortOrder" class="input" type="number" />
            </div>
            <div class="field span-2">
              <label style="display:flex;align-items:center;gap:8px">
                <input v-model="form.published" type="checkbox" />
                立即在游客端上架
              </label>
            </div>
          </div>
        </div>

        <footer class="drawer-foot">
          <button class="btn" type="button" @click="drawerOpen = false">取消</button>
          <button class="btn btn-primary" type="button" :disabled="saving" @click="submit">
            {{ saving ? '保存中…' : '保存' }}
          </button>
        </footer>
      </aside>
    </div>
  </div>
</template>
