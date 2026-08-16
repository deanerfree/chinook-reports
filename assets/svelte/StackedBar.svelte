<script lang="ts">
  export type Segment = {
    label: string
    value: number
    unit?: string
    color: string
  }

  type Props = {
    segments: Segment[]
    height?: string
    showLegend?: boolean
  }

  let { segments, height = '14px', showLegend = true }: Props = $props()

  const total = $derived(segments.reduce((sum, s) => sum + s.value, 0))

  function pct(value: number): number {
    return total === 0 ? 0 : (value / total) * 100
  }

  function fmt(value: number): string {
    return value % 1 === 0 ? String(value) : value.toFixed(1)
  }
</script>

<div class="flex flex-col gap-2 w-full">
  <div
    class="flex w-full overflow-hidden rounded"
    style="height: {height}; border: 1px solid var(--border, #e2e8f0);"
  >
    {#each segments as seg}
      {@const p = pct(seg.value)}
      {#if p > 0}
        <div
          title="{seg.label}: {fmt(seg.value)}{seg.unit ? seg.unit : ''} ({fmt(p)}%)"
          style="width: {p}%; background: {seg.color}; flex-shrink: 0;"
        ></div>
      {/if}
    {/each}
  </div>

  {#if showLegend}
    <div class="flex flex-wrap gap-x-4 gap-y-1">
      {#each segments as seg}
        {@const p = pct(seg.value)}
        <div class="flex items-center gap-1.5 text-xs text-gray-600">
          <span class="inline-block w-3 h-3 rounded-sm shrink-0" style="background: {seg.color};"></span>
          <span>{seg.label}</span>
          <span class="text-gray-400">{fmt(seg.value)}{seg.unit ?? ''} ({fmt(p)}%)</span>
        </div>
      {/each}
    </div>
  {/if}
</div>
