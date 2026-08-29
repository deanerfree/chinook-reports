<script lang="ts">
  // Accessible on/off switch. Two-way bindable via `bind:checked`.
  let {
    checked = $bindable(false),
    label,
    onColor = '#176935',
    offColor = '#cfd6d1',
    onchange,
  }: {
    checked?: boolean
    label?: string
    onColor?: string
    offColor?: string
    onchange?: (checked: boolean) => void
  } = $props()

  function toggle() {
    checked = !checked
    onchange?.(checked)
  }
</script>

<button
  type="button"
  role="switch"
  aria-checked={checked}
  aria-label={label}
  onclick={toggle}
  class="flex items-center gap-1.5 cursor-pointer text-[10px] font-bold uppercase tracking-wider text-gray-500"
>
  {#if label}<span>{label}</span>{/if}
  <span
    class="relative inline-block h-3.5 w-7 rounded-full transition-colors"
    style:background-color={checked ? onColor : offColor}
  >
    <span
      class="absolute top-px h-3 w-3 rounded-full bg-white shadow-sm transition-all"
      style:left={checked ? '15px' : '1px'}
    ></span>
  </span>
  <span class="w-6 text-left font-bold text-gray-800">{checked ? 'On' : 'Off'}</span>
</button>
