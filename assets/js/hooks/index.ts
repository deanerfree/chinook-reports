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

const DialogHook = {
  mounted(this: LiveViewHookContext) {
    const dialog = this.el as HTMLDialogElement
    this.el.addEventListener("dialog:open", () => dialog.showModal())
    this.el.addEventListener("dialog:close", () => dialog.close())
  }
}

// Input mask for a Canadian UWI: inserts the "/", "-" and "W" separators as
// the user types, so "100162304623" reads "100/16-23-046-23W". Mirrors the
// formats in ChinookReports.Reports.UWI (the server still validates). Leading
// zeros stay optional: typing the separator ends a segment early ("6-").
type UWIToken = { len: number; re: RegExp } | { lit: string; optional?: boolean }

const alnum = /[0-9a-z]/i
const digit = /[0-9]/
const seg = (len: number, re: RegExp): UWIToken => ({ len, re })

// DLS, e.g. 100/16-36-046-23W3/00 (optional M after the meridian)
const UWI_DLS: UWIToken[] = [
  seg(3, alnum), { lit: "/" }, seg(2, digit), { lit: "-" }, seg(2, digit), { lit: "-" },
  seg(3, digit), { lit: "-" }, seg(2, digit), { lit: "W" }, seg(1, digit),
  { lit: "M", optional: true }, { lit: "/" }, seg(2, alnum)
]

// NTS, e.g. 200/d-096-H/094-A-16/00
const UWI_NTS: UWIToken[] = [
  seg(3, alnum), { lit: "/" }, seg(1, /[a-l]/i), { lit: "-" }, seg(3, digit), { lit: "-" },
  seg(1, /[a-l]/i), { lit: "/" }, seg(3, digit), { lit: "-" }, seg(1, /[a-p]/i), { lit: "-" },
  seg(2, digit), { lit: "/" }, seg(2, alnum)
]

function formatUWI(value: string): string {
  const mask = value[0] === "1" ? UWI_DLS : value[0] === "2" ? UWI_NTS : null
  if (!mask) return value

  let out = ""
  let t = 0 // current token
  let n = 0 // chars filled in the current segment

  // Whether `c` is one of the separators that can follow token t, so typing
  // it closes a short segment early.
  const isNextSeparator = (c: string) => {
    for (let k = t + 1; k < mask.length; k++) {
      const tok = mask[k]
      if (!("lit" in tok)) return false
      if (c.toUpperCase() === tok.lit) return true
      if (!tok.optional) return false
    }
    return false
  }

  for (const c of value) {
    while (t < mask.length) {
      const tok = mask[t]
      if ("lit" in tok) {
        if (c.toUpperCase() === tok.lit) { out += tok.lit; t++; n = 0; break }
        if (tok.optional) { t++; continue }
        out += tok.lit; t++; n = 0 // auto-insert, then place c in the next segment
        continue
      }
      if (n < tok.len && tok.re.test(c)) { out += c; n++; break }
      if (n === tok.len || (n > 0 && isNextSeparator(c))) { t++; n = 0; continue }
      break // c doesn't fit here; drop it
    }
  }

  // A full segment shows its separator straight away. Stops at an optional
  // literal (the meridian's M) so the user can still type it.
  const tok = mask[t]
  if (tok && !("lit" in tok) && n === tok.len) {
    for (t++; t < mask.length; t++) {
      const next = mask[t]
      if (!("lit" in next) || next.optional) break
      out += next.lit
    }
  }
  return out
}

const UWIMaskHook = {
  mounted(this: LiveViewHookContext) {
    const input = this.el as HTMLInputElement
    input.addEventListener("input", (e) => {
      // Only Canada has a UWI format; only reformat while typing forward, so
      // backspacing over an auto-inserted separator isn't undone.
      if (input.dataset.uwiCountry !== "Canada") return
      if (!(e as InputEvent).inputType?.startsWith("insert")) return
      if (input.selectionEnd !== input.value.length) return
      const formatted = formatUWI(input.value)
      if (formatted !== input.value) input.value = formatted
    })
  }
}

export { SidebarCollapseHook, TanStackTableHook, DialogHook, UWIMaskHook, formatUWI }
