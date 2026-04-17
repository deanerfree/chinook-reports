<script>
  import ExtractionProgress from "./ExtractionProgress.svelte"

  let { multiple = false, live, files: entries = [], extractionStatus = null } = $props()

  const ACCEPTED_TYPES = [
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    "application/vnd.ms-excel",
  ]
  const ACCEPTED_EXTENSIONS = [".xlsx", ".xls"]

  let dragging = $state(false)
  let files = $state([])
  let error = $state("")
  let pendingSubmit = $state(false)

  // Once the user has clicked submit and all uploads reach 100%, fire the event
  $effect(() => {
    if (pendingSubmit && entries.length > 0 && entries.every((e) => e.progress === 100)) {
      pendingSubmit = false
      live.pushEvent("upload_excel", {})
    }
  })

  function isExcel(file) {
    if (ACCEPTED_TYPES.includes(file.type)) return true
    return ACCEPTED_EXTENSIONS.some((ext) => file.name.toLowerCase().endsWith(ext))
  }

  function addFiles(fileList) {
    error = ""
    const incoming = Array.from(fileList)
    for (const f of incoming) {
      if (!isExcel(f)) {
        error = `"${f.name}" is not an Excel file. Only .xlsx and .xls files are accepted.`
        return
      }
    }
    files = multiple ? [...files, ...incoming] : [incoming[0]]
    live.upload("excel", incoming)
  }

  function submitFiles() {
    if (entries.length > 0 && entries.every((e) => e.progress === 100)) {
      live.pushEvent("upload_excel", {})
    } else {
      pendingSubmit = true
    }
  }

  function handleDrop(e) {
    e.preventDefault()
    dragging = false
    if (e.dataTransfer?.files.length) {
      addFiles(e.dataTransfer.files)
    }
  }

  function handleDragOver(e) {
    e.preventDefault()
    dragging = true
  }

  function handleDragLeave(e) {
    if (!e.currentTarget.contains(e.relatedTarget)) {
      dragging = false
    }
  }

  function handleInputChange(e) {
    if (e.target.files.length) {
      addFiles(e.target.files)
    }
    e.target.value = ""
  }

  function removeFile(index) {
    const entry = entries[index]
    files = files.filter((_, i) => i !== index)
    if (entry?.ref) {
      live.pushEvent("cancel_upload", { ref: entry.ref })
    }
  }
</script>

<!-- svelte-ignore a11y_no_static_element_interactions -->
<div class="w-full">
  <div
    class="rounded-lg border-2 border-dashed p-10 text-center transition-colors
      {dragging ? 'border-primary bg-accent/20' : 'border-border hover:border-muted'}"
    ondragover={handleDragOver}
    ondragleave={handleDragLeave}
    ondrop={handleDrop}
  >
    <svg class="mx-auto h-12 w-12 text-muted" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
      <path stroke-linecap="round" stroke-linejoin="round" d="M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5m-13.5-9L12 3m0 0 4.5 4.5M12 3v13.5" />
    </svg>
    <p class="mt-4 text-lg font-medium text-copy">
      {dragging ? "Drop your Excel file here" : "Drag & drop Excel file here"}
    </p>
    <p class="mt-1 text-sm text-copy-secondary">or</p>
    <label class="mt-3 inline-block cursor-pointer rounded-full px-6 py-2 text-sm font-bold btn-primary">
      Browse files
      <input
        type="file"
        accept={ACCEPTED_EXTENSIONS.join(",")}
        {multiple}
        class="hidden"
        onchange={handleInputChange}
      />
    </label>
    <p class="mt-3 text-xs text-copy-secondary">Accepted formats: .xlsx, .xls</p>
  </div>

  {#if error}
    <div class="mt-4 rounded-md border border-danger/30 bg-danger/10 px-4 py-3 text-sm text-danger">
      {error}
    </div>
  {/if}

  {#if files.length > 0}
    <div class="flex flex-col items-center justify-end gap-8">
      <ul class="mt-6 space-y-2">
        {#each files as file, i}
          <li class="flex items-center justify-between rounded-md border border-border-light bg-surface-card px-4 py-3">
            <div class="flex items-center gap-3">
              <svg class="h-5 w-5 text-primary" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" d="M19.5 14.25v-2.625a3.375 3.375 0 0 0-3.375-3.375h-1.5A1.125 1.125 0 0 1 13.5 7.125v-1.5a3.375 3.375 0 0 0-3.375-3.375H8.25m2.25 0H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 0 0-9-9Z" />
              </svg>
              <span class="text-sm font-medium text-copy">{file.name}</span>
              <span class="text-xs text-copy-secondary">({(file.size / 1024).toFixed(1)} KB)</span>
              {#if entries[i]}
                <span class="text-xs text-copy-secondary">{entries[i].progress}%</span>
              {/if}
            </div>
            <button
              class="text-copy-secondary transition-colors hover:text-danger"
              onclick={() => removeFile(i)}
              aria-label="Remove {file.name}"
            >
              <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" d="M6 18 18 6M6 6l12 12" />
              </svg>
            </button>
          </li>
        {/each}
      </ul>
      <button type="submit" class="btn-primary mt-6" disabled={pendingSubmit || extractionStatus || entries.some(entry => entry?.progress < 100)} onclick={submitFiles}>
        {#if extractionStatus}
          Extracting…
        {:else if pendingSubmit && entries.some(entry => entry?.progress < 100)}
          Uploading…
        {:else}
          Process File
        {/if}
      </button>
    </div>
  {/if}

  <ExtractionProgress {extractionStatus} />
</div>
