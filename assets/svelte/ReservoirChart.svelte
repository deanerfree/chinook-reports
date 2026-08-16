<script lang="ts">
  import Chart from './Chart.svelte'
  import { buildChartOption, CHART_TYPES, type ChartData, type ChartType } from '../js/charts/charts'

  type CurvePoint = { md: number; rop: number; gas: number; gamma: number; interval_flag: number }
  type Interval   = { from_depth: number; to_depth: number; interval: number; quality: string; gas: number; lithology: string }
  type LogData = {
    quality_summary:   { quality: string; metres: number; percent: number }[]
    lithology_summary: { lithology: string; metres: number; percent: number }[]
    curve_data_cleaned: CurvePoint[]
    intervals: Interval[]
    curve_metadata: {
      null_value: number
      rop:   { max: number; min: number }
      gas:   { max: number; min: number }
      gamma: { max: number; min: number }
      cutoffs: { gas: number; gamma: number }
    }
  }
  type Leg = { leg_name: string; log_data: LogData }

  type Dataset = { id: string; label: string; defaultType: ChartType }

  const DATASETS: Dataset[] = [
    { id: 'quality',       label: 'Quality (m)',        defaultType: 'bar-horizontal'  },
    { id: 'lithology',     label: 'Lithology (m)',       defaultType: 'bar-horizontal'  },
    { id: 'intervals-gas', label: 'Intervals — Gas',     defaultType: 'bar-vertical'    },
    { id: 'log-curves',    label: 'Log Curves',          defaultType: 'line-horizontal' },
  ]

  let { legs }: { legs: Leg[] } = $props()

  let selectedLeg     = $state(0)
  let selectedDataset = $state('quality')

  function downsample<T>(arr: T[], step: number): T[] {
    return arr.filter((_, i) => i % step === 0)
  }

  function toChartData(legIdx: number, datasetId: string): ChartData {
    const ld = legs[legIdx]?.log_data
    if (!ld) return { categories: [], series: [] }

    switch (datasetId) {
      case 'quality':
        return {
          categories: ld.quality_summary.map(q => q.quality),
          series: [{ name: 'Metres', data: ld.quality_summary.map(q => q.metres) }],
        }

      case 'lithology': {
        const items = ld.lithology_summary.filter(l => l.metres > 0)
        return {
          categories: items.map(l => l.lithology),
          series: [{ name: 'Metres', data: items.map(l => l.metres) }],
        }
      }

      case 'intervals-gas':
        return {
          categories: ld.intervals.map(iv => `${iv.from_depth}–${iv.to_depth}`),
          series: [
            { name: 'Gas (units)',  data: ld.intervals.map(iv => iv.gas)      },
            { name: 'Length (m)',   data: ld.intervals.map(iv => iv.interval) },
          ],
        }

      case 'log-curves': {
        const pts  = downsample(ld.curve_data_cleaned, 4)
        const meta = ld.curve_metadata
        const nv   = meta.null_value

        // Normalize each curve to 0–100 so they share an axis
        const norm = (v: number, min: number, max: number) =>
          v == null || v === nv || max === min
            ? 0
            : Math.round(((v - min) / (max - min)) * 100)

        return {
          categories: pts.map(p => String(p.md)),
          series: [
            { name: 'GR %',  data: pts.map(p => norm(p.gamma, meta.gamma.min, meta.gamma.max)) },
            { name: 'Gas %', data: pts.map(p => norm(p.gas,   meta.gas.min,   meta.gas.max))   },
            { name: 'ROP %', data: pts.map(p => norm(p.rop,   meta.rop.min,   meta.rop.max))   },
          ],
        }
      }

      default:
        return { categories: [], series: [] }
    }
  }

  const currentLeg     = $derived(legs[selectedLeg])
  const currentDataset = $derived(DATASETS.find(d => d.id === selectedDataset)!)
  const chartData      = $derived(toChartData(selectedLeg, selectedDataset))
  const chartTitle     = $derived(`${currentLeg?.leg_name ?? ''} — ${currentDataset?.label ?? ''}`)
  const chartType      = $derived(currentDataset?.defaultType ?? 'bar-horizontal')
</script>

<div class="flex flex-col gap-3 w-full">
  {#if legs.length > 1}
    <div class="flex flex-wrap gap-1">
      {#each legs as leg, i}
        <button
          class="px-3 py-1 text-xs rounded border transition-colors cursor-pointer
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

  <div class="flex flex-wrap gap-1">
    {#each DATASETS as ds}
      <button
        class="px-3 py-1 text-xs rounded border transition-colors cursor-pointer
               {selectedDataset === ds.id
                 ? 'bg-emerald-600 text-white border-emerald-600'
                 : 'bg-white text-gray-700 border-gray-300 hover:bg-gray-50'}"
        onclick={() => { selectedDataset = ds.id }}
      >
        {ds.label}
      </button>
    {/each}
  </div>

  <Chart data={chartData} chartType={chartType} title={chartTitle} height="480px" />
</div>
