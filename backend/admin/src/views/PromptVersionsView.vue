<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { promptApi } from '../api/endpoints'
import { ApiError } from '../api/http'
import type { PromptVersionInput } from '../api/types'
import DataState from '../components/DataState.vue'

const versions = ref<Awaited<ReturnType<typeof promptApi.list>>>([])
const loading = ref(true)
const error = ref<string | null>(null)
const formError = ref<string | null>(null)
const success = ref<string | null>(null)
const creating = ref(false)
const activatingId = ref<string | null>(null)

const form = reactive<PromptVersionInput>({
  version: '',
  systemPrompt: '',
  note: '',
})

const current = computed(() => versions.value.find((item) => item.active) ?? null)

async function load() {
  loading.value = true
  error.value = null
  try {
    versions.value = await promptApi.list()
  } catch (cause) {
    error.value = cause instanceof ApiError ? cause.message : '提示词版本加载失败'
  } finally {
    loading.value = false
  }
}

onMounted(load)

function useCurrentAsTemplate() {
  if (!current.value) return
  form.systemPrompt = current.value.systemPrompt
  success.value = '已把当前版本填进编辑器，修改后再发布为新版本。'
}

async function createVersion() {
  formError.value = null
  success.value = null
  if (!form.version.trim()) {
    formError.value = '版本号不能为空'
    return
  }
  if (!form.systemPrompt.trim()) {
    formError.value = '系统提示词不能为空'
    return
  }
  creating.value = true
  try {
    const created = await promptApi.create({
      version: form.version.trim(),
      systemPrompt: form.systemPrompt.trim(),
      note: form.note?.trim() || null,
    })
    success.value = '已发布并启用版本 ' + created.version
    form.version = ''
    form.systemPrompt = ''
    form.note = ''
    await load()
  } catch (cause) {
    formError.value = cause instanceof ApiError ? cause.message : '发布失败，请稍后再试'
  } finally {
    creating.value = false
  }
}

async function activate(id: string | null, version: string) {
  if (!id) return
  if (!window.confirm('确定启用版本「' + version + '」？后续规划会立即使用这份系统提示词。')) return
  activatingId.value = id
  formError.value = null
  success.value = null
  try {
    await promptApi.activate(id)
    success.value = '已启用版本 ' + version
    await load()
  } catch (cause) {
    formError.value = cause instanceof ApiError ? cause.message : '启用失败，请稍后再试'
  } finally {
    activatingId.value = null
  }
}

function shortDate(value: string): string {
  if (!value || value.startsWith('1970-')) return '内置'
  return new Date(value).toLocaleString('zh-CN', { hour12: false })
}
</script>

<template>
  <div class="stack">
    <DataState :loading="loading" :error="error" :empty="!versions.length">
      <div v-if="formError" class="alert">{{ formError }}</div>
      <div v-if="success" class="notice">{{ success }}</div>

      <div class="grid-2">
        <article class="panel">
          <div class="panel-head">
            <div>
              <span class="eyebrow">Active prompt</span>
              <h3>当前启用版本</h3>
            </div>
            <span v-if="current" class="tag tag-ok">{{ current.version }}</span>
          </div>
          <div class="panel-body stack">
            <p class="hint">
              只管理系统提示词；用户请求、工具数据、JSON 输出契约与厂商无关解析仍由代码控制。
              版本切换后，新生成的行程会把版本号写入 `prompt_version`。
            </p>
            <pre v-if="current" class="prompt-block">{{ current.systemPrompt }}</pre>
            <div class="toolbar">
              <button class="btn btn-sm" type="button" @click="useCurrentAsTemplate">
                以当前版本为模板
              </button>
              <span v-if="current?.note" class="cell-sub">{{ current.note }}</span>
            </div>
          </div>
        </article>

        <article class="panel">
          <div class="panel-head">
            <div>
              <span class="eyebrow">Publish</span>
              <h3>发布新版本</h3>
            </div>
          </div>
          <div class="panel-body">
            <div class="stack">
              <div class="field">
                <label>版本号</label>
                <input v-model="form.version" class="input" placeholder="v1.3.0-rail-price-rules" />
              </div>
              <div class="field">
                <label>版本说明</label>
                <input v-model="form.note" class="input" placeholder="例如：补充铁路票价与中转约束" />
              </div>
              <div class="field">
                <label>系统提示词</label>
                <textarea
                  v-model="form.systemPrompt"
                  class="textarea prompt-editor"
                  placeholder="你是豫见智旅的河南文旅规划助手…"
                ></textarea>
              </div>
              <div class="split">
                <span class="hint">发布即启用，旧版本保留，可随时回滚。</span>
                <button class="btn btn-primary" type="button" :disabled="creating" @click="createVersion">
                  {{ creating ? '发布中…' : '发布并启用' }}
                </button>
              </div>
            </div>
          </div>
        </article>
      </div>

      <article class="panel">
        <div class="panel-head">
          <div>
            <span class="eyebrow">History</span>
            <h3>版本历史</h3>
          </div>
          <span class="cell-sub">共 {{ versions.length }} 个版本</span>
        </div>
        <div class="panel-body is-flush">
          <table class="table">
            <thead>
              <tr>
                <th>版本</th>
                <th>说明</th>
                <th>状态</th>
                <th>创建时间</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="item in versions" :key="item.id ?? item.version">
                <td class="cell-strong mono">{{ item.version }}</td>
                <td>{{ item.note || '—' }}</td>
                <td>
                  <span class="tag" :class="item.active ? 'tag-ok' : 'tag-muted'">
                    {{ item.active ? '当前启用' : '历史版本' }}
                  </span>
                </td>
                <td class="cell-sub">{{ shortDate(item.createdAt) }}</td>
                <td>
                  <div class="actions">
                    <button
                      v-if="!item.active"
                      class="btn btn-sm"
                      type="button"
                      :disabled="!item.id || activatingId === item.id"
                      @click="activate(item.id, item.version)"
                    >
                      {{ activatingId === item.id ? '启用中…' : '启用' }}
                    </button>
                    <span v-else class="cell-sub">生效中</span>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </article>
    </DataState>
  </div>
</template>
