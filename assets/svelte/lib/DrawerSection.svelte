<script lang="ts">
  // Titled group of related controls inside a Drawer.
  // Pass `collapsible` to render the title as an expand/collapse toggle;
  // the open state is two-way bindable via `bind:open`.
  import type { Snippet } from 'svelte'

  let {
    title,
    description,
    collapsible = false,
    open = $bindable(true),
    children,
  }: {
    title: string
    description?: string
    collapsible?: boolean
    open?: boolean
    children: Snippet
  } = $props()
</script>

<section class="mb-5 last:mb-0">
  {#if collapsible}
    <button
      type="button"
      onclick={() => (open = !open)}
      aria-expanded={open}
      class="flex w-full cursor-pointer items-center justify-between gap-2 py-0.5"
    >
      <h3 class="m-0 text-[10px] font-bold uppercase tracking-wider text-gray-400">{title}</h3>
      <svg
        width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor"
        stroke-width="3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"
        class="text-gray-400 transition-transform" class:rotate-180={open}
      >
        <polyline points="6 9 12 15 18 9" />
      </svg>
    </button>
  {:else}
    <h3 class="m-0 mb-0.5 text-[10px] font-bold uppercase tracking-wider text-gray-400">{title}</h3>
  {/if}

  {#if !collapsible || open}
    {#if description}
      <p class="m-0 mb-2 mt-0.5 text-[10px] leading-tight text-gray-400">{description}</p>
    {:else}
      <div class="mb-2"></div>
    {/if}
    <div class="flex flex-col gap-2.5">
      {@render children()}
    </div>
  {/if}
</section>
