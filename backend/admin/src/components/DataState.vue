<script setup lang="ts">
defineProps<{
  loading?: boolean
  error?: string | null
  empty?: boolean
  emptyText?: string
}>()
</script>

<template>
  <div v-if="loading" class="state">正在加载…</div>
  <div v-else-if="error" class="state">
    <strong>加载失败</strong>
    <span>{{ error }}</span>
  </div>
  <div v-else-if="empty" class="state">
    <strong>暂无数据</strong>
    <span>{{ emptyText ?? '当前筛选条件下没有记录。' }}</span>
  </div>
  <slot v-else />
</template>
