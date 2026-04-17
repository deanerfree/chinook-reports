<script>
  import ExcelDropzone from "./ExcelDropzone.svelte"
  import Heading from "./Heading.svelte"

  let { files = [], extraction_status = null, live } = $props()
</script>

<div class="container">
  <div class="max-w-4xl px-6">
  <Heading title="Chinook Reports" subtitle="Upload your Chinook Report Excel file to get started." />
    <div class="mt-8">
      <ExcelDropzone {files} {live} extractionStatus={extraction_status} />
    </div>
  </div>
</div>
