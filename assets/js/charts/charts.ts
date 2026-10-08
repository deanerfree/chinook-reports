import type { EChartsCoreOption as EChartsOption } from 'echarts/core'

export type ChartType =
  | 'bar-vertical'
  | 'bar-horizontal'
  | 'pie'
  | 'line'
  | 'line-horizontal'
  | 'scatter'
  | 'scatter-horizontal'

export type SeriesItem = {
  name: string
  data: number[]
}

export type ChartData = {
  categories: string[]
  series: SeriesItem[]
}

export const CHART_TYPES: { type: ChartType; label: string }[] = [
  { type: 'bar-vertical',       label: 'Column'     },
  { type: 'bar-horizontal',     label: 'Bar'        },
  { type: 'pie',                label: 'Pie'        },
  { type: 'line',               label: 'Line'       },
  { type: 'line-horizontal',    label: 'Line H'     },
  { type: 'scatter',            label: 'Scatter'    },
  { type: 'scatter-horizontal', label: 'Scatter H'  },
]

/** At most two decimals, without padding: 124.93684 → 124.94, 3.5 → 3.5. */
export function round2(n: number): number {
  return Math.round(n * 100) / 100
}

/** `round2` as display text (for labels / categories built from raw numbers). */
export function fmt2(n: number | null | undefined): string {
  return n == null || Number.isNaN(n) ? '—' : String(round2(n))
}

export function buildChartOption(
  type: ChartType,
  rawData: ChartData,
  title?: string
): EChartsOption {
  // Round once on the way in so every tooltip, label and axis shows at most
  // two decimals (the extractor's floats run to 5+); nulls stay gaps.
  const data: ChartData = {
    ...rawData,
    series: rawData.series.map(s => ({
      ...s,
      data: s.data.map(v => (typeof v === 'number' ? round2(v) : v)),
    })),
  }

  switch (type) {
    case 'bar-vertical':       return barVertical(data, title)
    case 'bar-horizontal':     return barHorizontal(data, title)
    case 'pie':                return pie(data, title)
    case 'line':               return line(data, title)
    case 'line-horizontal':    return lineHorizontal(data, title)
    case 'scatter':            return scatter(data, title)
    case 'scatter-horizontal': return scatterHorizontal(data, title)
  }
}

// ── helpers ──────────────────────────────────────────────────────────────────

function titleOpt(text?: string): Partial<EChartsOption> {
  return text ? { title: { text, left: 'center' } } : {}
}

function legendOpt(data: ChartData): Partial<EChartsOption> {
  return data.series.length > 1 ? { legend: { bottom: 0 } } : {}
}

function axisTooltip(): Pick<EChartsOption, 'tooltip'> {
  return { tooltip: { trigger: 'axis' } }
}

// ── builders ─────────────────────────────────────────────────────────────────

function barVertical(data: ChartData, title?: string): EChartsOption {
  return {
    ...titleOpt(title),
    ...legendOpt(data),
    ...axisTooltip(),
    xAxis: { type: 'category', data: data.categories },
    yAxis: { type: 'value' },
    series: data.series.map(s => ({ ...s, type: 'bar' })),
  }
}

function barHorizontal(data: ChartData, title?: string): EChartsOption {
  return {
    ...titleOpt(title),
    ...legendOpt(data),
    ...axisTooltip(),
    xAxis: { type: 'value' },
    yAxis: { type: 'category', data: data.categories },
    series: data.series.map(s => ({ ...s, type: 'bar' })),
  }
}

function pie(data: ChartData, title?: string): EChartsOption {
  const first = data.series[0]
  const pieData = data.categories.map((cat, i) => ({
    name: cat,
    value: first?.data[i] ?? 0,
  }))

  return {
    ...titleOpt(title),
    tooltip: { trigger: 'item', formatter: '{b}: {c} ({d}%)' },
    legend: { orient: 'vertical', left: 'left' },
    series: [
      {
        name: first?.name ?? 'Values',
        type: 'pie',
        radius: ['0%', '60%'],
        data: pieData,
        emphasis: {
          itemStyle: {
            shadowBlur: 10,
            shadowOffsetX: 0,
            shadowColor: 'rgba(0,0,0,0.5)',
          },
        },
      },
    ],
  }
}

function line(data: ChartData, title?: string): EChartsOption {
  return {
    ...titleOpt(title),
    ...legendOpt(data),
    ...axisTooltip(),
    xAxis: { type: 'category', data: data.categories },
    yAxis: { type: 'value' },
    series: data.series.map(s => ({ ...s, type: 'line', smooth: true })),
  }
}

function lineHorizontal(data: ChartData, title?: string): EChartsOption {
  return {
    ...titleOpt(title),
    ...legendOpt(data),
    ...axisTooltip(),
    xAxis: { type: 'value' },
    yAxis: { type: 'category', data: data.categories },
    series: data.series.map(s => ({ ...s, type: 'line', smooth: true })),
  }
}

function scatter(data: ChartData, title?: string): EChartsOption {
  return {
    ...titleOpt(title),
    ...legendOpt(data),
    tooltip: {
      trigger: 'item',
      formatter: (p: any) => `${p.seriesName}<br/>${p.value[0]}: ${p.value[1]}`,
    },
    xAxis: { type: 'category', data: data.categories },
    yAxis: { type: 'value' },
    series: data.series.map(s => ({
      name: s.name,
      type: 'scatter',
      data: s.data.map((v, i) => [data.categories[i], v]),
    })),
  }
}

function scatterHorizontal(data: ChartData, title?: string): EChartsOption {
  return {
    ...titleOpt(title),
    ...legendOpt(data),
    tooltip: {
      trigger: 'item',
      formatter: (p: any) => `${p.seriesName}<br/>${p.value[1]}: ${p.value[0]}`,
    },
    xAxis: { type: 'value' },
    yAxis: { type: 'category', data: data.categories },
    series: data.series.map(s => ({
      name: s.name,
      type: 'scatter',
      data: s.data.map((v, i) => [v, data.categories[i]]),
    })),
  }
}
