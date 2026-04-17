const DownloadHook = {
  mounted() {
    this.handleEvent("download", ({ url }) => {
      const link = document.createElement("a")
      link.href = url
      link.download = ""
      document.body.appendChild(link)
      link.click()
      document.body.removeChild(link)
    })
  }
}

const DragNDropHook = {
  mounted() {
    this.el.addEventListener("dragover", (event: DragEvent) => {
      event.preventDefault()
      this.el.classList.add("drag-over")
    })

    this.el.addEventListener("dragleave", () => {
      this.el.classList.remove("drag-over")
    })

    this.el.addEventListener("drop", () => {
      this.el.classList.remove("drag-over")
    })
  }
}