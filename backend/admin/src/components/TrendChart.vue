<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref, watch } from 'vue'
import * as echarts from 'echarts/core'
import { LineChart } from 'echarts/charts'
import { GridComponent, LegendComponent, TooltipComponent } from 'echarts/components'
import { CanvasRenderer } from 'echarts/renderers'
import type { DailyPoint } from '../api/types'

// 按需注册：管理台只需要一条折线图，避免把整个 ECharts 打进首屏包。
echarts.use([LineChart, GridComponent, LegendComponent, TooltipComponent, CanvasRenderer])

const props = defineProps<{ points: DailyPoint[] }>()
const host = ref<HTMLDivElement | null>(null)
let chart: ReturnType<typeof echarts.init> | null = null

function render() {
  if (!host.value) return
  if (!chart) chart = echarts.init(host.value)
  const labels = props.points.map((point) => point.date.slice(5))
  chart.setOption(
    {
      color: ['#3F6F6A', '#A8341E'],
      tooltip: { trigger: 'axis' },
      legend: { right: 0, top: 0, icon: 'rect', itemWidth: 8, itemHeight: 8, textStyle: { color: '#7C8B87' } },
      grid: { left: 8, right: 8, top: 34, bottom: 4, containLabel: true },
      xAxis: {
        type: 'category',
        data: labels,
        axisLine: { lineStyle: { color: '#D8DED9' } },
        axisTick: { show: false },
        axisLabel: { color: '#7C8B87' },
      },
      yAxis: {
        type: 'value',
        minInterval: 1,
        splitLine: { lineStyle: { color: '#E4E8E4' } },
        axisLabel: { color: '#7C8B87' },
      },
      series: [
        {
          name: '规划方案',
          type: 'line',
          smooth: true,
          symbolSize: 5,
          data: props.points.map((point) => point.plans),
          areaStyle: { opacity: 0.1 },
        },
        {
          name: '工具调用',
          type: 'line',
          smooth: true,
          symbolSize: 5,
          data: props.points.map((point) => point.toolCalls),
        },
      ],
    },
    true,
  )
}

function resize() {
  chart?.resize()
}

onMounted(() => {
  render()
  window.addEventListener('resize', resize)
})

watch(() => props.points, render, { deep: true })

onBeforeUnmount(() => {
  window.removeEventListener('resize', resize)
  chart?.dispose()
  chart = null
})
</script>

<template>
  <div ref="host" class="chart"></div>
</template>
