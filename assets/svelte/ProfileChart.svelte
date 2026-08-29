<script lang="ts">
  import { onMount, onDestroy } from 'svelte'
  import { init, use } from 'echarts/core'
  import type { ECharts } from 'echarts/core'
  import { LineChart, ScatterChart, CustomChart } from 'echarts/charts'
  import {
    GridComponent, TooltipComponent, LegendComponent,
    MarkAreaComponent, MarkLineComponent, DataZoomComponent, TitleComponent,
  } from 'echarts/components'
  import { CanvasRenderer } from 'echarts/renderers'

  import Toggle from './lib/Toggle.svelte'
  import ToggleChip from './lib/ToggleChip.svelte'
  import RangeSlider from './lib/RangeSlider.svelte'
  import Drawer from './lib/Drawer.svelte'
  import DrawerSection from './lib/DrawerSection.svelte'

  use([
    LineChart, ScatterChart, CustomChart,
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

  type Casing = { section: string; size: number | null; set_at: number | null }
  type FormationTop = {
    formation: string
    samples?: { md?: number | null; tvd?: number | null; subsea?: number | null }
  }
  type PlanPoint = { tvd: number; vertical_section: number }

  // ── Props ────────────────────────────────────────────────────────────────────

  let {
    legs,
    dark = false,
    layout = 'lateral',
    casing = [],
    tops = [],
    elevations = {},
    td = {},
    plan = [],
    show_curves = true,
    overlay_curves = false,
  }: {
    legs: Leg[]
    dark?: boolean
    layout?: 'lateral' | 'vertical'
    casing?: Casing[]
    tops?: FormationTop[]
    elevations?: Record<string, number>
    td?: Record<string, number>
    plan?: PlanPoint[]
    show_curves?: boolean
    overlay_curves?: boolean
  } = $props()

  let overlayOn = $state(true)
  let settingsOpen = $state(false)

  // Formation tops on the profile. `showTops` is the master switch; `topVisible`
  // holds the per-top state, keyed by formation name (absent key ⇒ visible).
  let showTops = $state(true)
  let topVisible = $state<Record<string, boolean>>({})

  // VS-plot layer visibility (driven by the control cluster above the chart)
  let showBackdrop    = $state(true)   // full-height reservoir-quality stripes
  let backdropOpacity = $state(0.16)   // stripe fill opacity (0–0.5)
  let showColors   = $state(true)   // quality-coloured segments on the wellbore path
  let curveShow    = $state({ rop: true, gas: true, gamma: true })
  // Reservoir-quality shading behind each Fig. 02 overlay band, per curve.
  let curveQuality = $state({ rop: true, gas: true, gamma: true })

  // Preserved Y-axis (TVD) zoom window, so control toggles don't reset the view.
  // Plain (non-reactive) on purpose: it is written from the chart's own dataZoom
  // event and only re-read when some *other* state triggers a rebuild.
  let vsYZoom: { start: number; end: number } | null = null

  // ── Constants ────────────────────────────────────────────────────────────────

  const LEG_COLORS     = ['#3b82f6', '#10b981', '#f59e0b', '#8b5cf6', '#ef4444']

  const OVERLAY_BANDS = [
    { key: 'rop',   label: 'ROP', color: '#000000' },
    { key: 'gas',   label: 'GAS', color: '#dc3545' },
    { key: 'gamma', label: 'GR',  color: '#176935' },
  ] as const
  const OVERLAY_HI_FALLBACK: Record<'rop' | 'gas' | 'gamma', number> = { rop: 300, gas: 2000, gamma: 200 }

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
  const RIGHT   = 38   // wide enough to seat the VS chart's TVD zoom slider
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
  // Formations that carry a usable TVD, in file order — the candidates for the
  // profile overlay and the drawer's per-top toggles.
  const topList = $derived(
    (tops ?? []).filter((t) => t?.samples?.tvd != null).map((t) => t.formation),
  )
  const hasTops = $derived(topList.length > 0)

  const hasSettings = $derived(
    layout === 'vertical'
      ? hasTops
      : hasQualityOnPath || overlay_curves || hasTops,
  )

  // Formation tops the user has kept visible (master switch + per-top state).
  const activeTops = $derived(
    showTops ? topList.filter((f) => topVisible[f] !== false) : [],
  )
  let vsContainer = $state<HTMLDivElement>()
  let mdContainer = $state<HTMLDivElement>()
  let dcContainer = $state<HTMLDivElement>()
  let vsChart: ECharts | null = null
  let mdChart: ECharts | null = null
  let dcChart: ECharts | null = null

  const isVertical = $derived(layout === 'vertical')

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

    // Curve samples keyed by vertical section, for the hover tooltip over the
    // Fig. 02 overlay (populated below when the overlay is on).
    let curveTip: { vs: number; rop: number | null; gas: number | null; gamma: number | null }[] | null = null

    // Full-height reservoir-quality stripes behind the whole plot, keyed by the
    // vertical-section position of each reservoir interval.
    {
      const qLeg = legs[selectedLeg] ?? legs[0]
      const qSp  = (qLeg?.survey?.survey_points ?? []).filter(
        p => p.vertical_section != null && p.md != null
      )
      const qIvs = (qLeg?.log_data?.intervals ?? []).filter(
        iv => iv.quality && QUALITY_COLORS[iv.quality]
      )
      if (showBackdrop && qSp.length > 1 && qIvs.length) {
        const toVs = (md: number) => {
          const hit = interpolateSurvey(qSp, md)
          return hit ? hit[0] : qSp[qSp.length - 1].vertical_section
        }
        series.push({
          name: '_qualityBg',
          type: 'line',
          data: [],
          silent: true,
          z: 0,
          symbol: 'none',
          tooltip: { show: false },
          markArea: {
            silent: true,
            data: qIvs.map(iv => {
              const a = toVs(iv.from_depth)
              const b = toVs(iv.to_depth)
              return [
                { xAxis: Math.min(a, b), itemStyle: { color: QUALITY_COLORS[iv.quality], opacity: backdropOpacity } },
                { xAxis: Math.max(a, b) },
              ]
            }),
          },
        })
      }
    }

    if (plan.length > 1) {
      series.push({
        name: 'Plan',
        type: 'line',
        smooth: false,
        symbol: 'none',
        z: 2,
        data: plan.map(p => [p.vertical_section, p.tvd]),
        lineStyle: { width: 1.3, color: dark ? '#7d8a80' : '#93a995', type: 'dashed' as const },
        itemStyle: { color: '#93a995' },
        tooltip: { show: false },
      })
    }

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
      const intervals = showColors
        ? (leg.log_data?.intervals ?? []).filter(iv => iv.quality && QUALITY_COLORS[iv.quality])
        : []

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

    // ── Formation tops: horizontal TVD markers across the whole plot ──────────
    if (activeTops.length) {
      const shownTops = new Set(activeTops)
      const topLines = (tops ?? [])
        .filter(t => shownTops.has(t.formation) && t.samples?.tvd != null)
        .map(t => ({
          yAxis: t.samples!.tvd as number,
          lineStyle: { color: dark ? '#7d8a80' : '#9aa39c', width: 1, type: 'dashed' as const },
          label: {
            show: true, position: 'insideEndTop' as const, fontSize: 8.5,
            color: textColor, formatter: t.formation,
          },
        }))
      if (topLines.length) {
        series.push({
          name: '_tops',
          type: 'line',
          data: [],
          silent: true,
          z: 1,
          symbol: 'none',
          tooltip: { show: false },
          markLine: {
            silent: true,
            symbol: 'none',
            // No grow-in animation — the horizontal rule would otherwise wipe
            // left-to-right on every rebuild.
            animation: false,
            data: topLines,
          },
        })
      }
    }

    // ── Fig. 02 overlay: drilling curves superimposed on the VS plot ──────────
    if (overlay_curves && overlayOn) {
      const leg = legs[selectedLeg] ?? legs[0]
      const ld  = leg?.log_data
      const sp  = (leg?.survey?.survey_points ?? []).filter(
        p => p.vertical_section != null && p.md != null
      )
      const curves = ld?.curve_data_cleaned ?? []

      if (ld && sp.length > 1 && curves.length) {
        const nv   = ld.curve_metadata?.null_value ?? -999.25
        const meta = (ld.curve_metadata ?? {}) as any
        const mdToVs = (md: number): number => {
          const hit = interpolateSurvey(sp, md)
          return hit ? hit[0] : sp[sp.length - 1].vertical_section
        }
        const bands = OVERLAY_BANDS
          .filter(b => curveShow[b.key])
          .map(b => ({ ...b, hi: meta[b.key]?.max ?? OVERLAY_HI_FALLBACK[b.key] }))
        const qb = (ld.intervals ?? []).filter(iv => iv.quality && QUALITY_COLORS[iv.quality])

        curveTip = curves
          .map((p: any) => ({
            vs: mdToVs(p.md),
            rop: clean(p.rop, nv),
            gas: clean(p.gas, nv),
            gamma: clean(p.gamma, nv),
          }))
          .sort((a, b) => a.vs - b.vs)

        if (bands.length) series.push({
          type: 'custom',
          xAxisIndex: 0,
          yAxisIndex: 0,
          z: 6,
          silent: true,
          clip: true,
          // No enter/update transition: toggling curves changes the child list
          // of the returned group, and ECharts' element diffing otherwise
          // strands ghost rectangles at interpolated positions.
          animation: false,
          tooltip: { show: false },
          data: [0],
          renderItem: (params: any, api: any) => {
            const cs = params.coordSys
            const xPix = (vs: number) => api.coord([vs, 0])[0]
            const x0 = xPix(mdToVs(curves[0].md))
            const x1 = xPix(mdToVs(curves[curves.length - 1].md))
            const bGap = 10
            // const bH = 10
            const bH = Math.max(40, Math.min(25, (cs.height - 20 - bGap * (bands.length - 1)) / bands.length))
            const y0 = cs.y + 52
            const children: any[] = []

            bands.forEach((b, k) => {
              const top = y0 + k * (bH + bGap)
              const showQuality = curveQuality[b.key] && qb.length > 0

              // Track fill + reservoir-quality shading. The rects are always
              // emitted — invisible when the toggle is off — so the group's
              // child list stays fixed across re-renders. When quality is off
              // the track is transparent and the VS plot shows through.
              children.push({
                type: 'rect',
                shape: { x: x0, y: top, width: x1 - x0, height: bH },
                style: { fill: showQuality ? '#fff' : 'transparent' },
              })
              qb.forEach(iv => {
                const a = xPix(mdToVs(iv.from_depth))
                const c = xPix(mdToVs(iv.to_depth))
                children.push({
                  type: 'rect',
                  shape: { x: Math.min(a, c), y: top, width: Math.max(1, Math.abs(c - a)), height: bH },
                  style: { fill: QUALITY_COLORS[iv.quality], opacity: showQuality ? 0.8 : 0 },
                })
              })

              let seg: number[][] = []
              const flush = () => {
                if (seg.length > 1) {
                  children.push({ type: 'polyline', shape: { points: seg.slice() }, style: { stroke: 'rgba(255,255,255,.9)', lineWidth: 2.6, fill: 'none' } })
                  children.push({ type: 'polyline', shape: { points: seg.slice() }, style: { stroke: b.color, lineWidth: 1.2, fill: 'none' } })
                }
                seg = []
              }
              curves.forEach((p: any) => {
                const v = p[b.key]
                if (v == null || v === nv) { flush(); return }
                const clamped = Math.max(0, Math.min(v, b.hi))
                seg.push([xPix(mdToVs(p.md)), top + bH - (clamped / b.hi) * bH])
              })
              flush()

              children.push({ type: 'rect', shape: { x: x0, y: top, width: x1 - x0, height: bH }, style: { fill: 'none', stroke: '#c9c9c5' } })
              children.push({ type: 'rect', shape: { x: x0 + 3, y: top + 3, width: b.label.length * 7 + 12, height: 13 }, style: { fill: 'rgba(255,255,255,.85)' } })
              children.push({ type: 'text', x: x0 + 7, y: top + 4, style: { text: b.label, fill: b.color, font: '700 9px Roboto, sans-serif' } })
              children.push({ type: 'text', x: x1 - 4, y: top + 4, style: { text: String(Math.round(b.hi)), fill: '#a8b5ab', font: '8px Roboto, sans-serif', align: 'right' } })
            })

            return { type: 'group', children }
          },
        })
      }
    }

    return {
      backgroundColor: 'transparent',
      grid: { left: LEFT, right: RIGHT, top: 14, bottom: 30 },
      dataZoom: [
        {
          id: 'vsY',
          type: 'inside',
          yAxisIndex: 0,
          filterMode: 'none',
          zoomOnMouseWheel: false,
          moveOnMouseMove: true,
          moveOnMouseWheel: false,
          ...(vsYZoom ?? {}),
        },
        {
          id: 'vsYSlider',
          type: 'slider',
          yAxisIndex: 0,
          right: 4,
          width: 14,
          filterMode: 'none',
          showDetail: false,
          brushSelect: false,
          handleSize: '80%',
          handleStyle:    { color: dark ? '#475569' : '#94a3b8' },
          moveHandleSize:  4,
          textStyle:      { color: textColor, fontSize: 8 },
          borderColor:    axisColor,
          fillerColor:    dark ? 'rgba(59,130,246,0.14)' : 'rgba(59,130,246,0.10)',
          dataBackground: { lineStyle: { color: axisColor }, areaStyle: { color: 'transparent' } },
          ...(vsYZoom ?? {}),
        },
      ],
      tooltip: {
        trigger: 'axis',
        axisPointer: { type: 'cross', crossStyle: { color: axisColor } },
        formatter: (params: any) => {
          const arr = Array.isArray(params) ? params : [params]
          const wellPt = arr.find(p => p?.value?.length === 2)
          const vs = wellPt ? +wellPt.value[0] : +(arr[0]?.axisValue ?? NaN)
          if (!isFinite(vs)) return ''

          const lines = [`VS ${vs.toFixed(1)} m east`]
          if (wellPt) lines.push(`TVD ${(+wellPt.value[1]).toFixed(1)} m`)

          if (curveTip && curveTip.length) {
            let lo = 0, hi = curveTip.length - 1
            while (lo < hi) {
              const mid = (lo + hi) >> 1
              if (curveTip[mid].vs < vs) lo = mid + 1
              else hi = mid
            }
            const a = curveTip[Math.max(0, lo - 1)]
            const b = curveTip[lo]
            const near = Math.abs(a.vs - vs) <= Math.abs(b.vs - vs) ? a : b
            const fmt = (label: string, v: number | null) =>
              v == null ? null : `${label} <b>${v.toFixed(v >= 100 ? 0 : 1)}</b>`
            const curveLines = [
              fmt('ROP', near.rop),
              fmt('Gas', near.gas),
              fmt('GR', near.gamma),
            ].filter(Boolean)
            if (curveLines.length) lines.push('<span style="opacity:.6">— curves —</span>', ...curveLines as string[])
          }

          return lines.join('<br/>')
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
        boundaryGap: ['5%', '5%'],
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
        boundaryGap: ['1%', '1%'],
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

  // ── Vertical depth column (profile + casing + formation tops) ────────────────

  function buildDepthColumnOption() {
    const leg = legs[selectedLeg] ?? legs[0]
    const pts = (leg?.survey?.survey_points ?? []).filter(
      p => p.tvd != null && p.vertical_section != null
    )
    if (!pts.length) return {}

    const textColor  = dark ? '#a3b5a8' : '#555'
    const mutedColor = dark ? '#6b8f74' : '#8d998f'
    const gridColor  = dark ? '#1e2e24' : '#f4f4f2'
    const axisColor  = dark ? '#2a3d30' : '#1b1b1b'

    const maxTvd = Math.max(...pts.map(p => p.tvd), td?.tvd ?? 0) * 1.03

    const mdToTvd = (md: number): number => {
      const hit = interpolateSurvey(pts, md)
      return hit ? hit[1] : md
    }

    const casingLines = (casing ?? [])
      .filter(c => c.set_at != null)
      .map(c => ({
        yAxis: mdToTvd(c.set_at as number),
        lineStyle: { color: dark ? '#86efac' : '#114a26', width: 1.4 },
        label: {
          show: true, position: 'insideStartTop' as const, fontSize: 8,
          color: dark ? '#86efac' : '#114a26',
          formatter: c.size != null ? `${Math.round(c.size)} mm` : (c.section ?? ''),
        },
      }))

    const shownTops = new Set(activeTops)
    const topLines = (tops ?? [])
      .filter(t => shownTops.has(t.formation) && (t.samples!.tvd as number) <= maxTvd)
      .map(t => ({
        yAxis: t.samples!.tvd as number,
        lineStyle: { color: mutedColor, width: 1, type: 'dashed' as const },
        label: {
          show: true, position: 'insideEndTop' as const, fontSize: 8.5,
          color: textColor, formatter: t.formation,
        },
      }))

    return {
      backgroundColor: 'transparent',
      grid: { left: 52, right: 132, top: 24, bottom: 30 },
      tooltip: {
        trigger: 'axis',
        axisPointer: { type: 'cross' },
        formatter: (params: { value: [number, number] }[]) => {
          const p = Array.isArray(params) ? params[0] : params
          if (!p?.value) return ''
          return `TVD ${(+p.value[1]).toFixed(1)} m<br/>VS ${(+p.value[0]).toFixed(1)} m`
        },
      },
      xAxis: {
        type: 'value',
        name: 'VS (m)',
        nameLocation: 'middle' as const,
        nameGap: 18,
        nameTextStyle: { color: textColor, fontSize: 9 },
        axisLabel: { color: mutedColor, fontSize: 9 },
        axisLine: { lineStyle: { color: axisColor } },
        splitLine: { lineStyle: { color: gridColor } },
      },
      yAxis: {
        type: 'value',
        inverse: true,
        min: 0,
        max: Math.ceil(maxTvd),
        name: 'TVD (m)',
        nameLocation: 'middle' as const,
        nameGap: 40,
        nameTextStyle: { color: textColor, fontSize: 9 },
        axisLabel: { color: mutedColor, fontSize: 9 },
        axisLine: { lineStyle: { color: axisColor } },
        splitLine: { lineStyle: { color: gridColor } },
      },
      series: [
        {
          name: leg?.leg_name ?? 'Profile',
          type: 'line',
          smooth: false,
          symbol: 'none',
          data: pts.map(p => [p.vertical_section, p.tvd]),
          lineStyle: { width: 1.6, color: dark ? '#4ade80' : '#114a26' },
          itemStyle: { color: dark ? '#4ade80' : '#114a26' },
          markLine: {
            silent: true,
            symbol: 'none',
            animation: false,
            data: [...casingLines, ...topLines],
          },
        },
      ],
    }
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────────

  function updateAll() {
    if (isVertical) {
      dcChart?.setOption(buildDepthColumnOption(), { notMerge: true })
      return
    }
    vsChart?.setOption(buildVSOption(), { notMerge: true })
    mdChart?.setOption(buildMDOption(), { notMerge: true })
  }

  $effect(() => {
    void legs
    void dark
    void layout
    void plan
    void casing
    void tops
    void selectedLeg
    void hiddenVsMarkers
    void overlayOn
    void overlay_curves
    void show_curves
    void showBackdrop
    void backdropOpacity
    void showColors
    void curveShow.rop; void curveShow.gas; void curveShow.gamma
    void curveQuality.rop; void curveQuality.gas; void curveQuality.gamma
    void showTops
    for (const k in topVisible) void topVisible[k]
    updateAll()
  })

  onMount(() => {
    // Each container is conditionally rendered: dc only in vertical layout, md
    // only when there are drilling curves. init() throws on a missing DOM node,
    // so guard every call on the container actually being present.
    if (isVertical) {
      if (dcContainer) dcChart = init(dcContainer)
    } else {
      if (vsContainer) vsChart = init(vsContainer)
      if (mdContainer) mdChart = init(mdContainer)

      vsChart?.on('click', (params: any) => {
        if (params.componentType !== 'series') return
        const markers = vsEventSeriesMap.get(params.seriesIndex)
        if (!markers) return
        const marker = markers[params.dataIndex]
        if (marker) toggleVsMarker(marker.event)
      })

      // Remember the TVD (Y-axis) window the user drags to, so unrelated
      // control toggles (which rebuild the option) don't snap it back.
      vsChart?.on('dataZoom', () => {
        const dz = ((vsChart?.getOption() as any)?.dataZoom as any[])
          ?.find(d => d.id === 'vsYSlider')
        if (!dz) return
        vsYZoom = (dz.start <= 0.05 && dz.end >= 99.95)
          ? null
          : { start: dz.start, end: dz.end }
      })

      // Double-click anywhere on the plot resets the Y-axis zoom.
      vsChart?.getZr().on('dblclick', () => {
        if (!vsYZoom) return
        vsYZoom = null
        updateAll()
      })
    }
    updateAll()

    const ro = new ResizeObserver(() => {
      vsChart?.resize()
      mdChart?.resize()
      dcChart?.resize()
    })
    if (dcContainer) ro.observe(dcContainer)
    if (vsContainer) ro.observe(vsContainer)
    if (mdContainer) ro.observe(mdContainer)
    return () => ro.disconnect()
  })

  onDestroy(() => { vsChart?.dispose(); mdChart?.dispose(); dcChart?.dispose() })
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

{#snippet settingsButton()}
  <button
    type="button"
    onclick={() => { settingsOpen = true }}
    aria-haspopup="dialog"
    aria-expanded={settingsOpen}
    class="flex items-center gap-1 rounded-full border border-gray-300 bg-white px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-gray-600 transition-colors cursor-pointer hover:bg-gray-50"
  >
    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
      <circle cx="12" cy="12" r="3" />
      <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.6 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.6a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z" />
    </svg>
    Settings
  </button>
{/snippet}

{#if isVertical}
  <div class="flex items-start justify-between gap-3 mb-1.5">
    <p class="text-xs font-semibold uppercase tracking-wider text-muted m-0 pt-1">
      Depth Column · Profile · Casing · Formation Tops
    </p>
    {#if hasSettings}{@render settingsButton()}{/if}
  </div>
  <div bind:this={dcContainer} style="width: 100%; height: 640px;"></div>
{:else}
  <div class="flex items-start justify-between gap-3 mb-1.5">
    <p class="text-xs font-semibold uppercase tracking-wider text-muted m-0 pt-1">
      Vertical Section · Wellbore Profile
    </p>
    <div class="flex flex-wrap items-center justify-end gap-x-3 gap-y-1.5 text-[10px] text-gray-500">
      {#if plan.length > 1}
        <span class="flex items-center gap-1.5">
          <svg width="14" height="4"><line x1="0" y1="2" x2="14" y2="2" stroke="#93a995" stroke-width="1.4" stroke-dasharray="4 3" /></svg>
          Plan
        </span>
      {/if}
      <span class="flex items-center gap-1.5">
        <svg width="14" height="4"><line x1="0" y1="2" x2="14" y2="2" stroke="#114a26" stroke-width="1.6" /></svg>
        Actual
      </span>

      {#if hasSettings}{@render settingsButton()}{/if}
    </div>
  </div>

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
  <div bind:this={vsContainer} style="width: 100%; height: {overlay_curves ? 400 : 340}px;"></div>

  {#if show_curves}
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
  {/if}
{/if}

{#if hasSettings}
  <Drawer bind:open={settingsOpen} title="Chart Settings">
    {#if hasQualityOnPath}
      <DrawerSection title="Chart Style" description="Reservoir-quality styling on the wellbore plot.">
        <ToggleChip bind:pressed={showBackdrop} label="Quality backdrop" />
        {#if showBackdrop}
          <RangeSlider
            bind:value={backdropOpacity}
            min={0}
            max={1}
            step={0.02}
            label="Opacity"
            format={(v) => `${Math.round(v * 100)}`}
          />
        {/if}
        <ToggleChip bind:pressed={showColors} label="Path colours" />
      </DrawerSection>
    {/if}

    {#if hasTops}
      <DrawerSection
        title="Formation Tops"
        description="Formation tops picked from samples, drawn across the profile at their TVD."
        collapsible
      >
        <Toggle bind:checked={showTops} label="Show tops" />
        {#if showTops}
          <div class="flex flex-wrap gap-1.5">
            {#each topList as formation}
              <ToggleChip
                pressed={topVisible[formation] !== false}
                label={formation}
                onchange={(v) => (topVisible[formation] = v)}
              />
            {/each}
          </div>
        {/if}
      </DrawerSection>
    {/if}

    {#if overlay_curves}
      <DrawerSection title="Fig. 02 Overlay" description="Drilling curves superimposed on the VS plot. Toggle reservoir-quality shading per curve.">
        <Toggle bind:checked={overlayOn} label="Overlay" />
        {#if overlayOn}
          <div class="flex flex-col gap-2">
            {#each OVERLAY_BANDS as band}
              <div class="flex flex-wrap items-center gap-1.5">
                <ToggleChip bind:pressed={curveShow[band.key]} label={band.label} dotColor={band.color} />
                {#if curveShow[band.key] && hasQualityOnPath}
                  <ToggleChip bind:pressed={curveQuality[band.key]} label="Quality" />
                {/if}
              </div>
            {/each}
          </div>
        {/if}
      </DrawerSection>
    {/if}
  </Drawer>
{/if}
