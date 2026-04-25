type LiveViewHookContext = {
  el: HTMLElement
  pushEvent(event: string, payload?: object): void
  handleEvent(event: string, callback: (payload: unknown) => void): void
}

type SidebarHookContext = LiveViewHookContext & {
  observer?: MutationObserver
  applyCollapsed(): void
}

type TanStackTableHookContext = LiveViewHookContext & {
  table: any
}

const SidebarCollapseHook = {
  mounted(this: SidebarHookContext) {
    this.applyCollapsed()

    this.observer = new MutationObserver(() => {
      localStorage.setItem("sidebar-collapsed", String(this.el.classList.contains("collapsed")))
    })

    this.observer.observe(this.el, { attributes: true, attributeFilter: ["class"] })
  },

  // LiveView re-renders the sidebar on every navigation (current_page changes).
  // Without this, the server-patched DOM resets the class and the observer saves "false".
  updated(this: SidebarHookContext) {
    this.applyCollapsed()
  },

  applyCollapsed(this: SidebarHookContext) {
    const collapsed = localStorage.getItem("sidebar-collapsed") === "true"
    this.el.classList.toggle("collapsed", collapsed)
    document.getElementById("sidebar-toggle-chevron")?.classList.toggle("rotated", collapsed)
    // Hand off from the pre-mount CSS state to the class-based system
    delete document.documentElement.dataset.sidebarCollapsed
  },

  destroyed(this: SidebarHookContext) {
    this.observer?.disconnect()
  }
}

const TanStackTableHook = {
  mounted(this: TanStackTableHookContext) {
    // @ts-ignore
    this.table = new TanStack.Table(this.el, JSON.parse(this.el.dataset.tableConfig || "{}"))
  },

  updated(this: TanStackTableHookContext) {
    this.table?.setOptions(JSON.parse(this.el.dataset.tableConfig || "{}"))
  }
}

export { SidebarCollapseHook, TanStackTableHook }
