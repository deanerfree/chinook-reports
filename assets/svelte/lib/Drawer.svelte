<script lang="ts">
  // Slide-in settings panel anchored to the right edge of the viewport.
  // Two-way bindable via `bind:open`.
  import type { Snippet } from 'svelte'

  let {
    open = $bindable(false),
    title = 'Settings',
    width = 288,
    children,
  }: {
    open?: boolean
    title?: string
    width?: number
    children: Snippet
  } = $props()

  function close() { open = false }

  function onkeydown(e: KeyboardEvent) {
    if (e.key === 'Escape' && open) close()
  }
</script>

<svelte:window {onkeydown} />

{#if open}
  <button
    type="button"
    aria-label="Close settings"
    tabindex="-1"
    class="fixed inset-0 z-40 cursor-default bg-black/20"
    onclick={close}
  ></button>
{/if}

<aside
  class="fixed right-0 top-0 z-50 flex h-full flex-col border-l border-gray-200 bg-white shadow-xl transition-transform duration-200 ease-out"
  class:translate-x-0={open}
  class:translate-x-full={!open}
  style:width="{width}px"
  aria-hidden={!open}
>
  <header class="flex items-center justify-between border-b border-gray-200 px-4 py-3">
    <h2 class="m-0 text-xs font-semibold uppercase tracking-wider text-gray-600">{title}</h2>
    <button
      type="button"
      onclick={close}
      aria-label="Close settings"
      class="inline-flex cursor-pointer items-center justify-center rounded p-0.5 text-gray-400 transition-colors hover:bg-gray-100 hover:text-gray-600"
    >
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" aria-hidden="true">
        <line x1="6" y1="6" x2="18" y2="18" />
        <line x1="18" y1="6" x2="6" y2="18" />
      </svg>
    </button>
  </header>
  <div class="flex-1 overflow-y-auto px-4 py-4">
    {@render children()}
  </div>
</aside>
