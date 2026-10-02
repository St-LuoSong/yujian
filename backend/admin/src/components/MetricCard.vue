<script setup lang="ts">
defineProps<{
  label: string
  value: string | number
  unit?: string
  sub?: string
}>()
</script>

<template>
  <dl class="metric">
    <dt>{{ label }}</dt>
    <dd>
      {{ value }}<span v-if="unit" class="unit">{{ unit }}</span>
    </dd>
    <div v-if="sub" class="sub">{{ sub }}</div>
  </dl>
</template>
