<script lang="ts">
  // Compact pill toggle for layer / series visibility. Bindable via `bind:pressed`.
  let {
    pressed = $bindable(true),
    label,
    dotColor,
    onchange,
  }: {
    pressed?: boolean
    label: string
    dotColor?: string
    onchange?: (pressed: boolean) => void
  } = $props()

  function toggle() {
    pressed = !pressed
    onchange?.(pressed)
  }
</script>

<button
  type="button"
  aria-pressed={pressed}
  onclick={toggle}
  class="flex items-center gap-1 rounded-full border px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide transition-colors cursor-pointer
         {pressed
           ? 'border-gray-300 bg-gray-100 text-gray-700'
           : 'border-gray-200 bg-white text-gray-400'}"
>
  {#if dotColor}
    <span
      class="inline-block h-2 w-2 rounded-full transition-opacity"
      style:background-color={dotColor}
      style:opacity={pressed ? '1' : '0.3'}
    ></span>
  {/if}
  {label}
</button>
