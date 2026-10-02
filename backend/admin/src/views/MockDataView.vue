<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { mockApi } from '../api/endpoints'
import { ApiError } from '../api/http'
import type { DemoScenarioCatalog, DemoScenarioInput, SupportedDemoScenario } from '../api/types'
import DataState from '../components/DataState.vue'

const catalog = ref<DemoScenarioCatalog>({ supported: [], scenarios: [] })
const loading = ref(true)
const error = ref<string | null>(null)
const drawerOpen = ref(false)
const editingId = ref<string | null>(null)
const saving = ref(false)
const formError = ref<string | null>(null)

const form = reactive({
  scenarioKey: 'weather',
  matchKey: '',
  name: '',
  payloadJson: '',
  note: '',
  enabled: true,
})

const supported = computed(() => catalog.value.supported)
const currentScheme = computed(
  () => supported.value.find((item) => item.key === form.scenarioKey) ?? null,
)

async function load() {
  loading.value = true
  error.value = null
  try {
    catalog.value = await mockApi.catalog()
  } catch (cause) {
    error.value = cause instanceof ApiError ? cause.message : 'Mock 数据加载失败'
  } finally {
    loading.value = false
  }
}

onMounted(load)

function labelOf(key: string): string {
  return supported.value.find((item) => item.key === key)?.displayName ?? key
}

function resetForm() {
  form.scenarioKey = supported.value[0]?.key ?? 'weather'
  form.matchKey = ''
  form.name = ''
  form.payloadJson = ''
  form.note = ''
  form.enabled = true
  formError.value = null
}

function openCreate() {
  editingId.value = null
  resetForm()
  drawerOpen.value = true
}

function openEdit(item: {
  id: string
  scenarioKey: string
  matchKey: string
  name: string
  payloadJson: string
  note: string | null
  enabled: boolean
}) {
  editingId.value = item.id
  form.scenarioKey = item.scenarioKey
  form.matchKey = item.matchKey
  form.name = item.name
  form.payloadJson = item.payloadJson
  form.note = item.note ?? ''
  form.enabled = item.enabled
  formError.value = null
  drawerOpen.value = true
}

function useSample() {
  const scheme = currentScheme.value as SupportedDemoScenario | null
  if (!scheme) return
  form.payloadJson = scheme.sampleJson
  if (!form.matchKey.trim()) form.matchKey = 'default'
  if (!form.name.trim()) form.name = scheme.displayName + ' 演示覆盖'
}

function validateJson(text: string): string | null {
  try {
    JSON.parse(text)
    return null
  } catch (cause) {
    return cause instanceof Error ? cause.message : 'JSON 格式不正确'
  }
}

async function submit() {
  formError.value = null
  if (!form.scenarioKey.trim() || !form.matchKey.trim() || !form.name.trim()) {
    formError.value = '数据类型、匹配键和名称都是必填项'
    return
  }
  const jsonError = validateJson(form.payloadJson)
  if (jsonError) {
    formError.value = 'JSON 格式不正确：' + jsonError
    return
  }

  saving.value = true
  try {
    const payload: DemoScenarioInput = {
      name: form.name.trim(),
      payloadJson: form.payloadJson.trim(),
      note: form.note.trim() || null,
      enabled: form.enabled,
    }
    await mockApi.upsert(form.scenarioKey, form.matchKey.trim(), payload)
    drawerOpen.value = false
    await load()
  } catch (cause) {
    formError.value = cause instanceof ApiError ? cause.message : '保存失败，请检查 JSON 结构'
  } finally {
    saving.value = false
  }
}

async function remove(item: { id: string; name: string }) {
  if (!window.confirm('确定删除「' + item.name + '」？删除后会回退到内置演示样例。')) return
  try {
    await mockApi.remove(item.id)
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
    <DataState
      :loading="loading"
      :error="error"
      :empty="!supported.length"
      empty-text="Mock 数据目录为空。"
    >
      <article class="panel">
        <div class="panel-head">
          <div>
            <span class="eyebrow">Demo overrides</span>
            <h3>Mock 数据覆盖</h3>
          </div>
          <button class="btn btn-primary btn-sm" type="button" @click="openCreate">
            新增覆盖
          </button>
        </div>
        <div class="panel-body">
          <p class="hint">
            只影响 `APP_TOOLS_MODE=mock` 或真实数据降级后的演示结果。精确匹配优先，
            找不到时使用 `default`；都没有配置时回退代码内置样例，不伪造实时数据。
          </p>
          <div class="grid-3" style="margin-top:14px">
            <div v-for="scheme in supported" :key="scheme.key" class="scenario-scheme">
              <strong>{{ scheme.displayName }}</strong>
              <code>{{ scheme.key }}</code>
              <span>{{ scheme.matchHint }}</span>
            </div>
          </div>
        </div>
      </article>

      <article class="panel">
        <div class="panel-body is-flush">
          <table class="table">
            <thead>
              <tr>
                <th>类型</th>
                <th>匹配键</th>
                <th>名称</th>
                <th>状态</th>
                <th>更新时间</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="item in catalog.scenarios" :key="item.id">
                <td>
                  <span class="tag tag-plain">{{ labelOf(item.scenarioKey) }}</span>
                  <div class="cell-sub mono">{{ item.scenarioKey }}</div>
                </td>
                <td class="mono">{{ item.matchKey }}</td>
                <td>
                  <div class="cell-strong">{{ item.name }}</div>
                  <div v-if="item.note" class="cell-sub">{{ item.note }}</div>
                </td>
                <td>
                  <span class="tag" :class="item.enabled ? 'tag-ok' : 'tag-muted'">
                    {{ item.enabled ? '已启用' : '已停用' }}
                  </span>
                </td>
                <td class="cell-sub">{{ shortDate(item.updatedAt) }}</td>
                <td>
                  <div class="actions">
                    <button class="btn btn-sm btn-ghost" type="button" @click="openEdit(item)">
                      编辑
                    </button>
                    <button class="btn btn-sm btn-danger" type="button" @click="remove(item)">
                      删除
                    </button>
                  </div>
                </td>
              </tr>
              <tr v-if="!catalog.scenarios.length">
                <td colspan="6" class="cell-sub">
                  还没有覆盖项，当前全部使用代码内置演示样例。
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </article>
    </DataState>

    <div v-if="drawerOpen" class="drawer-mask" @click.self="drawerOpen = false">
      <aside class="drawer">
        <header class="drawer-head">
          <div>
            <span class="eyebrow">Demo data</span>
            <h3>{{ editingId ? '编辑覆盖' : '新增覆盖' }}</h3>
          </div>
          <button class="btn btn-sm btn-ghost" type="button" @click="drawerOpen = false">
            关闭
          </button>
        </header>

        <div class="drawer-body stack">
          <div v-if="formError" class="alert">{{ formError }}</div>
          <div class="form-grid">
            <div class="field">
              <label>数据类型</label>
              <select v-model="form.scenarioKey" class="select" :disabled="Boolean(editingId)">
                <option v-for="scheme in supported" :key="scheme.key" :value="scheme.key">
                  {{ scheme.displayName }}（{{ scheme.key }}）
                </option>
              </select>
            </div>
            <div class="field">
              <label>匹配键</label>
              <input
                v-model="form.matchKey"
                class="input"
                :disabled="Boolean(editingId)"
                placeholder="例如 洛阳 或 郑州>洛阳；兜底填 default"
              />
            </div>
            <div class="field span-2">
              <label>名称</label>
              <input v-model="form.name" class="input" placeholder="洛阳晴天演示数据" />
            </div>
            <div class="field span-2">
              <label>说明</label>
              <input v-model="form.note" class="input" placeholder="给运营同事看的说明，不进入接口响应" />
            </div>
            <div class="field span-2">
              <div class="split">
                <label>JSON 内容</label>
                <button class="btn btn-sm" type="button" @click="useSample">填入示例</button>
              </div>
              <textarea
                v-model="form.payloadJson"
                class="textarea prompt-editor"
                placeholder="粘贴结构化 JSON；保存前服务端会按工具返回类型做严格校验"
              ></textarea>
              <p v-if="currentScheme" class="hint">{{ currentScheme.matchHint }}</p>
            </div>
            <div class="field span-2">
              <label style="display:flex;align-items:center;gap:8px">
                <input v-model="form.enabled" type="checkbox" />
                启用这条覆盖；停用后回退到内置样例
              </label>
            </div>
          </div>
        </div>

        <footer class="drawer-foot">
          <button class="btn" type="button" @click="drawerOpen = false">取消</button>
          <button class="btn btn-primary" type="button" :disabled="saving" @click="submit">
            {{ saving ? '保存中…' : '保存覆盖' }}
          </button>
        </footer>
      </aside>
    </div>
  </div>
</template>
