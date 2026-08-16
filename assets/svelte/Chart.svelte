<script lang="ts">
  import { onMount, onDestroy } from 'svelte'
  import { init, use, type ECharts } from 'echarts/core'
  import { BarChart, LineChart, ScatterChart, PieChart } from 'echarts/charts'
  import {
    TitleComponent,
    TooltipComponent,
    LegendComponent,
    GridComponent,
  } from 'echarts/components'
  import { CanvasRenderer } from 'echarts/renderers'
  import { buildChartOption, CHART_TYPES, type ChartType, type ChartData } from '../js/charts/charts'
  import { untrack } from 'svelte'

  use([
    BarChart, LineChart, ScatterChart, PieChart,
    TitleComponent, TooltipComponent, LegendComponent, GridComponent,
    CanvasRenderer,
  ])

  type Props = {
    data: ChartData
    chartType?: ChartType
    title?: string
    height?: string
  }

  let { data, chartType = 'bar-vertical', title, height = '400px' }: Props = $props()

  let currentType = $state<ChartType>(untrack(() => chartType))
  let container: HTMLDivElement
  let chart: ECharts | null = null

  // Sync if the server sends a new chartType prop
  $effect(() => { currentType = chartType })

  function updateChart() {
    if (!chart) return
    chart.setOption(buildChartOption(currentType, data, title), { notMerge: true })
  }

  $effect(() => {
    void currentType
    void data
    void title
    updateChart()
  })

  onMount(() => {
    chart = init(container)
    updateChart()

    const ro = new ResizeObserver(() => chart?.resize())
    ro.observe(container)
    return () => ro.disconnect()
  })

  onDestroy(() => {
    chart?.dispose()
  })
</script>

<div class="flex flex-col gap-2 w-full">
  <div class="flex flex-wrap gap-1">
    {#each CHART_TYPES as { type, label }}
      <button
        class="px-3 py-1 text-xs rounded border transition-colors cursor-pointer
               {currentType === type
                 ? 'bg-blue-600 text-white border-blue-600'
                 : 'bg-white text-gray-700 border-gray-300 hover:bg-gray-50'}"
        onclick={() => { currentType = type }}
      >
        {label}
      </button>
    {/each}
  </div>

  <div bind:this={container} style="width: 100%; height: {height};"></div>
</div>
