<script>
  let { extractionStatus = null } = $props()
</script>

{#if extractionStatus}
  <div class="mt-8 w-full max-w-md mx-auto">
    <p class="text-sm font-semibold text-copy mb-4">Extracting data…</p>
    <div class="space-y-2">
      {#each extractionStatus.steps as step}
        <div
          class="flex items-center gap-3 rounded-md border px-4 py-2 text-sm transition-all
            {step.status === 'extracting'
              ? 'border-primary bg-primary/10'
              : step.status === 'completed'
                ? 'border-success bg-success/10'
                : 'border-border bg-surface-card'}"
        >
          {#if step.status === 'completed'}
            <svg class="h-4 w-4 shrink-0 text-success" fill="none" viewBox="0 0 24 24" stroke-width="2.5" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" d="M4.5 12.75l6 6 9-13.5" />
            </svg>
          {:else if step.status === 'extracting'}
            <div class="h-4 w-4 shrink-0 rounded-full border-2 border-primary border-t-transparent animate-spin"></div>
          {:else}
            <div class="h-4 w-4 shrink-0 rounded-full border-2 border-border"></div>
          {/if}

          <span
            class="font-medium
              {step.status === 'extracting'
                ? 'text-primary'
                : step.status === 'completed'
                  ? 'text-success'
                  : 'text-copy-secondary'}"
          >
            {step.label}
          </span>
        </div>
      {/each}
    </div>
  </div>
{/if}
