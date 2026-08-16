<script lang="ts">
  import { onMount, onDestroy } from 'svelte'
  import { init, use } from 'echarts/core'
  import type { ECharts } from 'echarts/core'
  import { LineChart, ScatterChart } from 'echarts/charts'
  import {
    GridComponent, TooltipComponent, LegendComponent,
    MarkAreaComponent, MarkLineComponent, DataZoomComponent, TitleComponent,
  } from 'echarts/components'
  import { CanvasRenderer } from 'echarts/renderers'

  use([
    LineChart, ScatterChart,
    GridComponent, TooltipComponent, LegendComponent,
    MarkAreaComponent, MarkLineComponent, DataZoomComponent, TitleComponent,
    CanvasRenderer,
  ])

  // ── Types ────────────────────────────────────────────────────────────────────

  type SurveyPoint = { md: number; tvd: number; vertical_section: number }

  type Marker = {
    md: number; tvd: number; vertical_section: number
    event: string; inclination_deg?: number; azimuth_deg?: number
  }

  type SurveyData = { section_name: string; survey_points: SurveyPoint[]; markers: Marker[] }

  type CurvePoint = { md: number; rop: number | null; gas: number | null; gamma: number | null; interval_flag: number }

  type Interval = { from_depth: number; to_depth: number; quality: string; gas: number; lithology: string }

  type CurveRange = { max: number; min: number }

  type CurveMetadata = {
    null_value: number
    rop: CurveRange; gas: CurveRange; gamma: CurveRange
    cutoffs: { gas: number; gamma: number }
  }

  type LogData = { curve_data_cleaned: CurvePoint[]; intervals: Interval[]; curve_metadata: CurveMetadata }

  type Leg = { leg_name: string; survey: SurveyData | null; log_data: LogData | null }

  // ── Props ────────────────────────────────────────────────────────────────────

  let { legs, dark = false }: { legs: Leg[]; dark?: boolean } = $props()

  // ── Constants ────────────────────────────────────────────────────────────────

  const LEG_COLORS     = ['#3b82f6', '#10b981', '#f59e0b', '#8b5cf6', '#ef4444']

  const QUALITY_COLORS: Record<string, string> = {
    'Very Good': '#176935',
    'Good':      '#27ae60',
    'Fair':      '#f1c40f',
    'Poor':      '#e67e22',
    'Nil':       '#bdc3c7',
  }
  const QUALITY_ORDER = ['Very Good', 'Good', 'Fair', 'Poor', 'Nil']

  // MD log grid layout (pixels)
  const LEFT    = 62
  const RIGHT   = 20
  const Q_TOP   = 32
  const Q_H     = 38
  const GAP     = 14
  const C_H     = 118
  const ROP_TOP = Q_TOP + Q_H + GAP
  const GAS_TOP = ROP_TOP + C_H + GAP
  const GR_TOP  = GAS_TOP + C_H + GAP
  const MD_H    = GR_TOP + C_H + 62

  // ── State ────────────────────────────────────────────────────────────────────

  let selectedLeg       = $state(0)
  let hiddenVsMarkers   = $state(new Set<string>())
  let vsEventSeriesMap  = new Map<number, Marker[]>()

  function toggleVsMarker(event: string) {
    const next = new Set(hiddenVsMarkers)
    if (next.has(event)) next.delete(event)
    else next.add(event)
    hiddenVsMarkers = next
  }
  const hasQualityOnPath = $derived(
    legs.some(l =>
      l.survey?.survey_points?.length &&
      l.log_data?.intervals?.some(iv => iv.quality && QUALITY_COLORS[iv.quality])
    )
  )
  let vsContainer: HTMLDivElement
  let mdContainer: HTMLDivElement
  let vsChart: ECharts | null = null
  let mdChart: ECharts | null = null

  // ── Helpers ──────────────────────────────────────────────────────────────────

  function cssVar(name: string): string {
    return getComputedStyle(document.documentElement).getPropertyValue(name).trim()
  }

  function clean(v: number | null, nv: number): number | null {
    if (v == null || v === nv || !isFinite(v as number)) return null
    return v
  }

  function downsample<T>(arr: T[], step: number): T[] {
    return arr.filter((_, i) => i % step === 0)
  }

  function validMarkers(markers: Marker[]): Marker[] {
    return markers.filter(m => !(m.md > 500 && m.tvd < 100))
  }

  function interpolateSurvey(pts: SurveyPoint[], md: number): [number, number] | null {
    if (!pts.length) return null
    if (md <= pts[0].md) return [pts[0].vertical_section, pts[0].tvd]
    const last = pts[pts.length - 1]
    if (md >= last.md) return [last.vertical_section, last.tvd]
    for (let i = 0; i < pts.length - 1; i++) {
      if (pts[i].md <= md && md <= pts[i + 1].md) {
        const t = (md - pts[i].md) / (pts[i + 1].md - pts[i].md)
        return [
          pts[i].vertical_section + t * (pts[i + 1].vertical_section - pts[i].vertical_section),
          pts[i].tvd              + t * (pts[i + 1].tvd              - pts[i].tvd),
        ]
      }
    }
    return null
  }

  function findLateralBand(markers: Marker[]): { entry: Marker | null; exit: Marker | null } {
    const entry = markers.find(m => /heel|lateral.?start/i.test(m.event) && m.tvd > 100) ?? null
    const exit  = markers.find(m => /last survey/i.test(m.event)) ?? null
    return { entry, exit }
  }

  // ── VS trajectory chart ───────────────────────────────────────────────────────

  function buildVSOption() {
    const activeLegs = legs.filter(l => l.survey?.survey_points?.length)
    if (!activeLegs.length) return {}

    const textColor = dark ? '#a3b5a8' : '#555'
    const gridColor = dark ? '#1e2e24' : '#f0ede8'
    const axisColor = dark ? '#2a3d30' : '#e0ddd6'

    const series: object[] = []
    vsEventSeriesMap = new Map()

    activeLegs.forEach((leg, i) => {
      const pts = leg.survey!.survey_points.filter(
        p => p.vertical_section != null && p.tvd != null
      )
      const allMarkers = leg.survey!.markers ?? []
      const markers    = validMarkers(allMarkers)
      const { entry, exit } = findLateralBand(markers)
      const color = LEG_COLORS[i % LEG_COLORS.length]

      const markArea = entry && exit
        ? {
            markArea: {
              silent: true,
              itemStyle: { color: 'rgba(34,197,94,0.13)', borderColor: 'rgba(34,197,94,0.35)', borderWidth: 1 },
              label: {
                show: true, position: 'insideTop', fontSize: 9,
                color: dark ? '#86efac' : '#15803d', formatter: 'McLaren Lateral',
              },
              data: [[{ yAxis: Math.min(entry.tvd, exit.tvd) }, { yAxis: Math.max(entry.tvd, exit.tvd) }]],
            },
          }
        : {}

      const mclarenMarker = markers.find(m => /mclaren/i.test(m.event) && m.tvd > 100) ?? null
      const markLine = mclarenMarker
        ? {
            markLine: {
              silent: true,
              symbol: 'none',
              lineStyle: { color: 'rgba(34,197,94,0.7)', width: 1.5, type: 'dashed' as const },
              label: {
                zIndex: 100,
                show: true, position: 'insideEndBottom', fontSize: 8,
                color: dark ? '#86efac' : '#15803d', formatter: 'McLaren',
              },
              data: [{ yAxis: mclarenMarker.tvd }],
            },
          }
        : {}

      series.push({
        name: leg.leg_name ?? 'Wellbore',
        type: 'line',
        smooth: false,
        symbol: 'none',
        data: pts.map(p => [p.vertical_section, p.tvd]),
        lineStyle: { width: 1.4, color },
        itemStyle: { color },
        areaStyle: { color: `${color}0f`, origin: 'start' as const },
        ...markArea,
        ...markLine,
      })

      // Quality overlay: color each interval segment by reservoir quality
      const intervals = (leg.log_data?.intervals ?? [])
        .filter(iv => iv.quality && QUALITY_COLORS[iv.quality])

      intervals.forEach(iv => {
        const start   = interpolateSurvey(pts, iv.from_depth)
        const end     = interpolateSurvey(pts, iv.to_depth)
        const inner   = pts
          .filter(p => p.md > iv.from_depth && p.md < iv.to_depth)
          .map(p => [p.vertical_section, p.tvd] as [number, number])
        const segData: [number, number][] = [
          ...(start ? [start] : []),
          ...inner,
          ...(end   ? [end]   : []),
        ]
        if (segData.length < 2) return

        series.push({
          name: iv.quality,
          type: 'line',
          smooth: false,
          symbol: 'none',
          data: segData,
          lineStyle: { width: 3.5, color: QUALITY_COLORS[iv.quality] },
          itemStyle: { color: QUALITY_COLORS[iv.quality] },
          z: 5,
          tooltip: { show: false },
        })
      })

      const keyMarkers = markers.filter(m =>
        /kick off|kop|kelly|mclaren|heel|lateral|td\b|spud|last survey|top\b|base|entry|exit|intermediate casing/i.test(m.event)
      )
      if (keyMarkers.length) {
        const seriesIdx = series.length
        vsEventSeriesMap.set(seriesIdx, keyMarkers)
        series.push({
          name: 'Events',
          type: 'scatter',
          symbol: 'diamond',
          symbolSize: 7,
          z: 10,
          cursor: 'pointer',
          data: keyMarkers.map(m => ({
            value: [m.vertical_section, m.tvd],
            label: {
              show: !hiddenVsMarkers.has(m.event),
              position: 'top',
              offset: [-18, 0],
              fontSize: 11,
              color: textColor,
              backgroundColor: dark ? 'rgba(15,23,42,0.78)' : 'rgba(255,255,255,0.84)',
              borderRadius: 4,
              padding: [2, 6],
              formatter: () => m.event,
            },
          })),
          itemStyle: { color: '#f59e0b' },
          tooltip: { show: false },
        })
      }
    })

    return {
      backgroundColor: 'transparent',
      grid: { left: LEFT, right: RIGHT, top: 14, bottom: 30 },
      tooltip: {
        trigger: 'axis',
        axisPointer: { type: 'cross', crossStyle: { color: axisColor } },
        formatter: (params: { value: [number, number] }[]) => {
          const p = Array.isArray(params) ? params[0] : params
          if (!p?.value) return ''
          return `VS ${(+p.value[0]).toFixed(1)} m east<br/>TVD ${(+p.value[1]).toFixed(1)} m`
        },
      },
      xAxis: {
        type: 'value',
        name: 'VS (m east)',
        nameLocation: 'middle',
        nameGap: 20,
        nameTextStyle: { color: textColor, fontSize: 9 },
        axisLabel: { color: textColor, fontSize: 9 },
        axisLine: { lineStyle: { color: axisColor } },
        splitLine: { lineStyle: { color: gridColor, type: 'dashed' as const } },
      },
      yAxis: {
        type: 'value',
        inverse: true,
        name: 'TVD (m)',
        nameLocation: 'middle',
        nameGap: 42,
        nameTextStyle: { color: textColor, fontSize: 9 },
        axisLabel: { color: textColor, fontSize: 9 },
        axisLine: { lineStyle: { color: axisColor } },
        splitLine: { lineStyle: { color: gridColor, type: 'dashed' as const } },
      },
      series,
    }
  }

  // ── MD log chart ─────────────────────────────────────────────────────────────

  function buildMDOption() {
    const leg = legs[selectedLeg]
    const ld  = leg?.log_data
    if (!ld?.curve_data_cleaned?.length) return {}

    const ropColor   = cssVar('--color-chart-rop')
    const gasColor   = cssVar('--color-chart-gas')
    const gammaColor = cssVar('--color-chart-gamma')

    const textColor  = dark ? '#a3b5a8' : '#555'
    const mutedColor = dark ? '#6b8f74' : '#888'
    const gridColor  = dark ? '#1e2e24' : '#f0ede8'
    const axisColor  = dark ? '#2a3d30' : '#e0ddd6'

    const meta = ld.curve_metadata
    const nv   = meta?.null_value ?? -999.25
    const pts  = downsample(ld.curve_data_cleaned, 3)

    const mdMin = pts[0]?.md ?? 0
    const mdMax = pts[pts.length - 1]?.md ?? 1000

    const ropData   = pts.map(p => [p.md, clean(p.rop,   nv)])
    const gasData   = pts.map(p => [p.md, clean(p.gas,   nv)])
    const gammaData = pts.map(p => [p.md, clean(p.gamma, nv)])

    const qualityBands = (ld.intervals ?? [])
      .filter(iv => iv.quality && QUALITY_COLORS[iv.quality])
      .map(iv => [
        { xAxis: iv.from_depth, itemStyle: { color: QUALITY_COLORS[iv.quality] } },
        { xAxis: iv.to_depth },
      ])

    const baseXAxis = {
      type: 'value' as const,
      min: mdMin,
      max: mdMax,
      axisLine:  { lineStyle: { color: axisColor } },
      splitLine: { show: false },
      axisTick:  { show: true, lineStyle: { color: axisColor } },
    }

    const baseYAxis = {
      type: 'value' as const,
      nameTextStyle:  { color: textColor, fontSize: 9 },
      axisLabel:      { color: mutedColor, fontSize: 9 },
      axisLine:       { lineStyle: { color: axisColor } },
      splitLine:      { lineStyle: { color: gridColor, type: 'dashed' as const } },
    }

    return {
      backgroundColor: 'transparent',
      axisPointer: {
        link:  [{ xAxisIndex: 'all' }],
        label: { backgroundColor: dark ? '#334155' : '#e2e8f0', color: textColor, fontSize: 9 },
      },
      tooltip: {
        trigger: 'axis',
        confine: true,
        axisPointer: { type: 'cross' },
        formatter: (params: any) => {
          const arr: any[] = Array.isArray(params) ? params : [params]
          if (!arr.length) return ''
          const md = +(arr[0]?.axisValue ?? arr[0]?.value?.[0] ?? 0)
          const lines = arr
            .filter(p => p.seriesName !== '_quality' && p.value?.[1] != null)
            .map(p => `${p.marker}${p.seriesName}: <b>${(+p.value[1]).toFixed(2)}</b>`)
          return [`<span style="font-size:10px"><b>MD ${md.toFixed(1)} m</b></span>`, ...lines].join('<br/>')
        },
      },
      title: [
        { text: 'Quality Bands', top: Q_TOP - 18, left: LEFT, textStyle: { color: textColor, fontSize: 9, fontWeight: 'normal' as const } },
        { text: 'ROP',           top: ROP_TOP - 18, left: LEFT, textStyle: { color: ropColor,   fontSize: 9, fontWeight: 'bold' as const } },
        { text: 'Gas',           top: GAS_TOP - 18, left: LEFT, textStyle: { color: gasColor,   fontSize: 9, fontWeight: 'bold' as const } },
        { text: 'GR',            top: GR_TOP  - 18, left: LEFT, textStyle: { color: gammaColor, fontSize: 9, fontWeight: 'bold' as const } },
      ],
      grid: [
        { left: LEFT, right: RIGHT, top: Q_TOP,   height: Q_H },
        { left: LEFT, right: RIGHT, top: ROP_TOP, height: C_H },
        { left: LEFT, right: RIGHT, top: GAS_TOP, height: C_H },
        { left: LEFT, right: RIGHT, top: GR_TOP,  height: C_H },
      ],
      xAxis: [
        { ...baseXAxis, gridIndex: 0, axisLabel: { show: false }, axisTick: { show: false } },
        { ...baseXAxis, gridIndex: 1, axisLabel: { show: false } },
        { ...baseXAxis, gridIndex: 2, axisLabel: { show: false } },
        { ...baseXAxis, gridIndex: 3, name: 'Measured Depth (m)', nameLocation: 'middle' as const, nameGap: 28, nameTextStyle: { color: textColor, fontSize: 9 }, axisLabel: { color: mutedColor, fontSize: 9 } },
      ],
      yAxis: [
        { gridIndex: 0, show: false, min: 0, max: 1 },
        { ...baseYAxis, gridIndex: 1, name: 'ROP', nameLocation: 'middle' as const, nameGap: 40, nameRotate: 90 },
        { ...baseYAxis, gridIndex: 2, name: 'Gas', nameLocation: 'middle' as const, nameGap: 40, nameRotate: 90 },
        { ...baseYAxis, gridIndex: 3, name: 'GR',  nameLocation: 'middle' as const, nameGap: 40, nameRotate: 90 },
      ],
      dataZoom: [
        { type: 'inside', xAxisIndex: [0, 1, 2, 3], filterMode: 'none' },
        {
          type: 'slider',
          xAxisIndex: [0, 1, 2, 3],
          bottom: 8,
          height: 18,
          filterMode: 'none',
          handleStyle:    { color: dark ? '#475569' : '#94a3b8' },
          textStyle:      { color: textColor, fontSize: 8 },
          borderColor:    axisColor,
          fillerColor:    dark ? 'rgba(59,130,246,0.14)' : 'rgba(59,130,246,0.10)',
          dataBackground: { lineStyle: { color: axisColor }, areaStyle: { color: 'transparent' } },
        },
      ],
      series: [
        {
          name: '_quality',
          type: 'line',
          xAxisIndex: 0, yAxisIndex: 0,
          data: [], silent: true, symbol: 'none',
          markArea: { silent: true, data: qualityBands },
        },
        {
          name: 'ROP', type: 'line',
          xAxisIndex: 1, yAxisIndex: 1,
          data: ropData, smooth: false, symbol: 'none', connectNulls: false,
          lineStyle: { width: 1.4, color: ropColor }, itemStyle: { color: ropColor },
          areaStyle: { color: `${ropColor}0f`, origin: 'start' as const },
        },
        {
          name: 'Gas', type: 'line',
          xAxisIndex: 2, yAxisIndex: 2,
          data: gasData, smooth: false, symbol: 'none', connectNulls: false,
          lineStyle: { width: 1.4, color: gasColor }, itemStyle: { color: gasColor },
          areaStyle: { color: `${gasColor}0f`, origin: 'start' as const },
        },
        {
          name: 'GR', type: 'line',
          xAxisIndex: 3, yAxisIndex: 3,
          data: gammaData, smooth: false, symbol: 'none', connectNulls: false,
          lineStyle: { width: 1.4, color: gammaColor }, itemStyle: { color: gammaColor },
          areaStyle: { color: `${gammaColor}0f`, origin: 'start' as const },
        },
      ],
    }
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────────

  function updateAll() {
    vsChart?.setOption(buildVSOption(), { notMerge: true })
    mdChart?.setOption(buildMDOption(), { notMerge: true })
  }

  $effect(() => {
    void legs
    void dark
    void selectedLeg
    void hiddenVsMarkers
    updateAll()
  })

  onMount(() => {
    vsChart = init(vsContainer)
    mdChart = init(mdContainer)
    updateAll()

    vsChart.on('click', (params: any) => {
      if (params.componentType !== 'series') return
      const markers = vsEventSeriesMap.get(params.seriesIndex)
      if (!markers) return
      const marker = markers[params.dataIndex]
      if (marker) toggleVsMarker(marker.event)
    })

    const ro = new ResizeObserver(() => { vsChart?.resize(); mdChart?.resize() })
    ro.observe(vsContainer)
    ro.observe(mdContainer)
    return () => ro.disconnect()
  })

  onDestroy(() => { vsChart?.dispose(); mdChart?.dispose() })
</script>

{#if legs.length > 1}
  <div class="flex gap-1 mb-2">
    {#each legs as leg, i}
      <button
        class="px-2.5 py-0.5 text-xs rounded border transition-colors cursor-pointer
               {selectedLeg === i
                 ? 'bg-blue-600 text-white border-blue-600'
                 : 'bg-white text-gray-700 border-gray-300 hover:bg-gray-50'}"
        onclick={() => { selectedLeg = i }}
      >
        {leg.leg_name}
      </button>
    {/each}
  </div>
{/if}

<p class="text-xs font-semibold uppercase tracking-wider text-muted mb-1.5">
  Vertical Section · Wellbore Profile
</p>
{#if hasQualityOnPath}
  <div class="flex flex-wrap gap-x-3 gap-y-1 mb-1.5" style="margin-left: {LEFT}px">
    {#each QUALITY_ORDER as q}
      <span class="flex items-center gap-1 text-xs text-gray-500">
        <span class="inline-block w-3 h-2.5 rounded-sm border border-black/10"
              style="background: {QUALITY_COLORS[q]}"></span>
        {q}
      </span>
    {/each}
  </div>
{/if}
<div bind:this={vsContainer} style="width: 100%; height: 340px;"></div>

<p class="text-xs font-semibold uppercase tracking-wider text-muted mt-4 mb-1">
  Drilling Curves vs Measured Depth · ROP · Gas · GR · quality bands
</p>
<div class="flex flex-wrap gap-x-3 gap-y-1 mb-1" style="margin-left: {LEFT}px">
  {#each QUALITY_ORDER as q}
    <span class="flex items-center gap-1 text-xs text-gray-500">
      <span class="inline-block w-3 h-2.5 rounded-sm border border-black/10"
            style="background: {QUALITY_COLORS[q]}"></span>
      {q}
    </span>
  {/each}
</div>
<div bind:this={mdContainer} style="width: 100%; height: {MD_H}px;"></div>
