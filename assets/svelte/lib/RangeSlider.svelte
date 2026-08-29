<script lang="ts">
  // Compact labelled range input. Two-way bindable via `bind:value`.
  let {
    value = $bindable(0),
    min = 0,
    max = 1,
    step = 0.01,
    label,
    format = (v: number) => String(v),
    onchange,
  }: {
    value?: number
    min?: number
    max?: number
    step?: number
    label?: string
    format?: (v: number) => string
    onchange?: (value: number) => void
  } = $props()

  const pct = $derived(((value - min) / (max - min)) * 100)
</script>

<label class="flex items-center gap-1.5 text-[10px] font-semibold uppercase tracking-wide text-gray-500">
  {#if label}<span>{label}</span>{/if}
  <input
    type="range"
    {min}
    {max}
    {step}
    bind:value
    oninput={() => onchange?.(value)}
    aria-label={label}
    class="range h-1 w-20 cursor-pointer appearance-none rounded-full bg-gray-200"
    style:--pct="{pct}%"
  />
  <span class="w-7 text-right tabular-nums font-bold text-gray-700">{format(value)}</span>
</label>

<style>
  .range {
    background: linear-gradient(
      to right,
      #176935 0%,
      #176935 var(--pct),
      var(--tw-color-gray-200, #e5e7eb) var(--pct),
      var(--tw-color-gray-200, #e5e7eb) 100%
    );
  }
  .range::-webkit-slider-thumb {
    appearance: none;
    height: 12px;
    width: 12px;
    border-radius: 9999px;
    background: #fff;
    border: 1px solid #94a3b8;
    box-shadow: 0 1px 2px rgb(0 0 0 / 0.15);
  }
  .range::-moz-range-thumb {
    height: 12px;
    width: 12px;
    border-radius: 9999px;
    background: #fff;
    border: 1px solid #94a3b8;
    box-shadow: 0 1px 2px rgb(0 0 0 / 0.15);
  }
</style>
