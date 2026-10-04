<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { appReleaseApi } from '../api/endpoints'
import { ApiError } from '../api/http'
import type { AppReleaseView, PublishAppReleaseInput } from '../api/types'
import DataState from '../components/DataState.vue'

const releases = ref<AppReleaseView[]>([])
const loading = ref(true)
const error = ref<string | null>(null)
const uploadError = ref<string | null>(null)
const uploading = ref(false)
const progress = ref(0)
/** 上传到哪条通道。缺省正式通道，调试包必须显式选。 */
const channel = ref<'RELEASE' | 'DEBUG'>('RELEASE')
const selected = ref<AppReleaseView | null>(null)
const publishing = ref(false)
const publishError = ref<string | null>(null)

const form = reactive<PublishAppReleaseInput>({
  releaseTitle: '',
  releaseNotes: '',
  minimumSupportedVersionCode: 1,
  updateMode: 'OPTIONAL',
})

const staged = computed(() => releases.value.filter((item) => item.status === 'UPLOADED').length)

async function load() {
  loading.value = true
  error.value = null
  try {
    releases.value = await appReleaseApi.list()
  } catch (cause) {
    error.value = cause instanceof ApiError ? cause.message : '应用版本加载失败'
  } finally {
    loading.value = false
  }
}

onMounted(load)

async function chooseFile(event: Event) {
  const input = event.target as HTMLInputElement
  const file = input.files?.[0]
  input.value = ''
  if (!file || uploading.value) return
  if (!file.name.toLowerCase().endsWith('.apk')) {
    uploadError.value = '请选择 .apk 安装包'
    return
  }
  uploadError.value = null
  uploading.value = true
  progress.value = 0
  try {
    const release = await appReleaseApi.upload(
      file,
      channel.value,
      (value) => (progress.value = value),
    )
    await load()
    openPublish(release)
  } catch (cause) {
    uploadError.value = cause instanceof ApiError ? cause.message : 'APK 上传或校验失败'
  } finally {
    uploading.value = false
  }
}

function openPublish(release: AppReleaseView) {
  selected.value = release
  form.releaseTitle = release.releaseTitle
  form.releaseNotes = release.releaseNotes === '待填写更新说明' ? '' : release.releaseNotes
  form.minimumSupportedVersionCode = Math.min(
    Math.max(1, release.minimumSupportedVersionCode),
    release.versionCode,
  )
  form.updateMode = release.updateMode === 'REQUIRED' || release.updateMode === 'RECOMMENDED'
    ? release.updateMode
    : 'OPTIONAL'
  publishError.value = null
}

async function publish() {
  const release = selected.value
  if (!release) return
  if (!form.releaseTitle.trim() || !form.releaseNotes.trim()) {
    publishError.value = '更新标题和更新说明不能为空'
    return
  }
  if (form.minimumSupportedVersionCode < 1
      || form.minimumSupportedVersionCode > release.versionCode) {
    publishError.value = '最低支持版本必须在 1 到当前 versionCode 之间'
    return
  }
  publishing.value = true
  publishError.value = null
  try {
    await appReleaseApi.publish(release.id, {
      releaseTitle: form.releaseTitle.trim(),
      releaseNotes: form.releaseNotes.trim(),
      minimumSupportedVersionCode: form.minimumSupportedVersionCode,
      updateMode: form.updateMode,
    })
    selected.value = null
    await load()
  } catch (cause) {
    publishError.value = cause instanceof ApiError ? cause.message : '版本发布失败'
  } finally {
    publishing.value = false
  }
}

async function disable(release: AppReleaseView) {
  if (!window.confirm('停止发布「' + release.versionName + '」？客户端将不再获得该版本。')) return
  try {
    await appReleaseApi.disable(release.id)
    await load()
  } catch (cause) {
    error.value = cause instanceof ApiError ? cause.message : '停止发布失败'
  }
}

async function restore(release: AppReleaseView) {
  if (!window.confirm('把「' + release.versionName + '」重新放回公开通道？')) return
  try {
    await appReleaseApi.restore(release.id)
    await load()
  } catch (cause) {
    error.value = cause instanceof ApiError ? cause.message : '重新发布失败'
  }
}

function statusText(status: string) {
  return ({ UPLOADED: '待发布', PUBLISHED: '发布中', SUPERSEDED: '已替代', DISABLED: '已停用' } as Record<string, string>)[status] ?? status
}

function statusClass(status: string) {
  return status === 'PUBLISHED' ? 'tag-ok' : status === 'UPLOADED' ? 'tag-warn' : 'tag-muted'
}

function humanSize(bytes: number) {
  return bytes >= 1024 * 1024 ? (bytes / 1024 / 1024).toFixed(1) + ' MB' : Math.ceil(bytes / 1024) + ' KB'
}

function shortHash(value: string) {
  return value.length > 20 ? value.slice(0, 10) + '…' + value.slice(-10) : value
}
</script>

<template>
  <div class="stack">
    <article class="panel release-upload-panel">
      <div class="panel-head">
        <div>
          <span class="eyebrow">Trusted Android channel</span>
          <h3>上传 APK</h3>
        </div>
        <div class="release-channel">
          <button
            type="button"
            class="btn btn-sm"
            :class="channel === 'RELEASE' ? 'btn-primary' : 'btn-ghost'"
            :disabled="uploading"
            @click="channel = 'RELEASE'"
          >正式包</button>
          <button
            type="button"
            class="btn btn-sm"
            :class="channel === 'DEBUG' ? 'btn-primary' : 'btn-ghost'"
            :disabled="uploading"
            @click="channel = 'DEBUG'"
          >调试包</button>
        </div>
        <label class="btn btn-primary btn-sm" :class="{ 'is-disabled': uploading }">
          {{ uploading ? '校验中…' : (channel === 'DEBUG' ? '选择 Debug APK' : '选择 Release APK') }}
          <input type="file" accept=".apk,application/vnd.android.package-archive" hidden :disabled="uploading" @change="chooseFile" />
        </label>
      </div>
      <div class="panel-body">
        <p class="hint">
          <template v-if="channel === 'RELEASE'">
            <strong>正式包</strong>：服务端会验证 APK 签名完整性、正式证书 SHA-256、包名、
            versionCode 与文件哈希。调试包会被拒绝。
          </template>
          <template v-else>
            <strong>调试包</strong>：debug keystore 每台机器都不一样，所以这一条通道只校验
            "文件是一份有效签名 + 包名与 versionCode 合法"，不比对证书白名单。
            它只会在同样开了 debuggable 的安装包上生效。
          </template>
          校验通过只进入待发布区，不会立即推送给用户。
        </p>
        <div v-if="uploading" class="release-progress">
          <div class="release-progress-track"><i :style="{ width: progress + '%' }"></i></div>
          <span>{{ progress < 100 ? '正在上传 ' + progress + '%' : '上传完成，正在校验签名与清单…' }}</span>
        </div>
        <div v-if="uploadError" class="alert" style="margin-top:12px">{{ uploadError }}</div>
      </div>
    </article>

    <DataState :loading="loading" :error="error" :empty="!releases.length" empty-text="还没有上传过正式安装包。">
      <article class="panel">
        <div class="panel-head">
          <div>
            <span class="eyebrow">Release ledger</span>
            <h3>版本记录</h3>
          </div>
          <span class="tag tag-plain">待发布 {{ staged }}</span>
        </div>
        <div class="table-wrap">
          <table>
            <thead><tr><th>版本</th><th>通道</th><th>策略</th><th>文件</th><th>可信校验</th><th>状态</th><th></th></tr></thead>
            <tbody>
              <tr v-for="release in releases" :key="release.id">
                <td>
                  <div class="cell-strong">v{{ release.versionName }}</div>
                  <div class="cell-sub mono">versionCode {{ release.versionCode }} · API {{ release.minimumSdk ?? '—' }}+</div>
                </td>
                <td>
                  <span class="tag" :class="release.channel === 'DEBUG' ? 'tag-warn' : 'tag-plain'">
                    {{ release.channel === 'DEBUG' ? '调试' : '正式' }}
                  </span>
                </td>
                <td>
                  <div>{{ release.updateMode }}</div>
                  <div class="cell-sub">最低支持 {{ release.minimumSupportedVersionCode }}</div>
                </td>
                <td>
                  <div>{{ humanSize(release.fileSize) }}</div>
                  <div class="cell-sub mono" :title="release.fileSha256">SHA {{ shortHash(release.fileSha256) }}</div>
                </td>
                <td>
                  <span class="tag tag-ok">签名通过</span>
                  <div class="cell-sub mono" :title="release.signingCertificateSha256">CERT {{ shortHash(release.signingCertificateSha256) }}</div>
                </td>
                <td><span class="tag" :class="statusClass(release.status)">{{ statusText(release.status) }}</span></td>
                <td>
                  <div class="actions">
                    <button v-if="release.status === 'UPLOADED'" class="btn btn-sm btn-primary" type="button" @click="openPublish(release)">配置并发布</button>
                    <button v-if="release.status === 'PUBLISHED'" class="btn btn-sm btn-danger" type="button" @click="disable(release)">停止发布</button>
                    <button
                      v-if="release.status === 'DISABLED' || release.status === 'SUPERSEDED'"
                      class="btn btn-sm"
                      type="button"
                      @click="restore(release)"
                    >重新发布</button>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </article>
    </DataState>

    <div v-if="selected" class="drawer-mask" @click.self="selected = null">
      <aside class="drawer">
        <header class="drawer-head">
          <div><span class="eyebrow">Publish release</span><h3>发布 v{{ selected.versionName }}</h3></div>
          <button class="btn btn-sm btn-ghost" type="button" @click="selected = null">关闭</button>
        </header>
        <div class="drawer-body stack">
          <div class="release-proof">
            <span>通道</span><strong>{{ selected.channel === 'DEBUG' ? '调试包' : '正式包' }}</strong>
            <span>包名</span><strong class="mono">{{ selected.packageName }}</strong>
            <span>证书</span><strong class="mono" :title="selected.signingCertificateSha256">{{ shortHash(selected.signingCertificateSha256) }}</strong>
            <span>文件</span><strong class="mono" :title="selected.fileSha256">{{ shortHash(selected.fileSha256) }}</strong>
          </div>
          <div v-if="publishError" class="alert">{{ publishError }}</div>
          <div class="form-grid">
            <div class="field span-2"><label>更新标题</label><input v-model="form.releaseTitle" class="input" maxlength="120" /></div>
            <div class="field span-2"><label>更新说明</label><textarea v-model="form.releaseNotes" class="textarea" rows="8" placeholder="每行一项，说明用户能感知到的变化"></textarea></div>
            <div class="field"><label>更新策略</label><select v-model="form.updateMode" class="select"><option value="OPTIONAL">可选更新</option><option value="RECOMMENDED">推荐更新</option><option value="REQUIRED">强制更新</option></select></div>
            <div class="field"><label>最低支持 versionCode</label><input v-model.number="form.minimumSupportedVersionCode" class="input" type="number" min="1" :max="selected.versionCode" /></div>
          </div>
          <div class="notice-box">发布会自动把上一个公开版本标记为“已替代”。强制更新会阻断低版本用户进入业务页面，请确认后再发布。</div>
        </div>
        <footer class="drawer-foot"><button class="btn" type="button" @click="selected = null">取消</button><button class="btn btn-primary" type="button" :disabled="publishing" @click="publish">{{ publishing ? '发布中…' : '确认发布' }}</button></footer>
      </aside>
    </div>
  </div>
</template>

<style scoped>
.release-upload-panel{border-top:3px solid var(--celadon)}
.release-channel{display:inline-flex;gap:6px;margin-left:auto;margin-right:12px}
.release-progress{display:flex;align-items:center;gap:12px;margin-top:16px;color:var(--ink-soft);font-size:13px}
.release-progress-track{height:6px;flex:1;background:var(--glaze-sunken);overflow:hidden;border-radius:99px}
.release-progress-track i{display:block;height:100%;background:var(--celadon);transition:width .18s ease}
.release-proof{display:grid;grid-template-columns:64px 1fr;gap:9px 12px;padding:14px;border:1px solid var(--line);background:var(--glaze-sunken)}
.release-proof span{color:var(--ash);font-size:12px}.release-proof strong{font-size:12px;overflow-wrap:anywhere}
.notice-box{padding:13px 14px;border-left:3px solid var(--amber);background:#f4ecdc;color:var(--ink-soft);font-size:13px;line-height:1.7}
.is-disabled{opacity:.56;pointer-events:none}
</style>
