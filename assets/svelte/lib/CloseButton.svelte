<script lang="ts">
  // Small icon button for dismissing an overlay / panel.
  let {
    onclick,
    label = 'Close',
    size = 15,
  }: {
    onclick?: (e: MouseEvent) => void
    label?: string
    size?: number
  } = $props()
</script>

<button
  type="button"
  {onclick}
  aria-label={label}
  title={label}
  class="inline-flex items-center justify-center rounded-full p-0.5 text-gray-400 transition-colors cursor-pointer hover:bg-gray-100 hover:text-gray-600"
>
  <svg
    width={size}
    height={size}
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    stroke-width="2.5"
    stroke-linecap="round"
    aria-hidden="true"
  >
    <line x1="6" y1="6" x2="18" y2="18" />
    <line x1="18" y1="6" x2="6" y2="18" />
  </svg>
</button>
