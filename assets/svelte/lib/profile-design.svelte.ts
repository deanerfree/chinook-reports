// Persisted design/style state for the wellbore profile chart.
//
// One object, branched by concern, serialised to localStorage as a single blob
// and restored on the next visit. Only *design* choices live here — ephemeral
// view state (selected leg, drawer open, zoom window, hidden event labels) stays
// as plain `$state` in the component.

type CurveKey = 'rop' | 'gas' | 'gamma'

export type ProfileDesign = {
  version: 1
  style: {
    showBackdrop: boolean
    backdropOpacity: number
    showColors: boolean
    pathOpacity: number
  }
  curves: {
    overlayOn: boolean
    show: Record<CurveKey, boolean>
    quality: Record<CurveKey, boolean>
  }
  tops: {
    show: boolean
    hidden: string[] // formation names the user has switched off
  }
}

const VERSION = 1
const KEY = 'chinook:profile-design'

// Fresh defaults on every call — never share object references into `$state`.
function defaults(): ProfileDesign {
  return {
    version: VERSION,
    style: { showBackdrop: true, backdropOpacity: 0.16, showColors: true, pathOpacity: 1 },
    curves: {
      overlayOn: true,
      show: { rop: true, gas: true, gamma: true },
      quality: { rop: true, gas: true, gamma: true },
    },
    tops: { show: true, hidden: [] },
  }
}

// Deep-merge a (possibly partial, possibly stale) saved blob over the defaults so
// options added after the blob was written still get a sane value.
function hydrate(saved: any): ProfileDesign {
  const d = defaults()
  if (!saved || typeof saved !== 'object' || saved.version !== VERSION) return d
  return {
    version: VERSION,
    style: { ...d.style, ...saved.style },
    curves: {
      ...d.curves,
      ...saved.curves,
      show: { ...d.curves.show, ...saved.curves?.show },
      quality: { ...d.curves.quality, ...saved.curves?.quality },
    },
    tops: {
      show: saved.tops?.show ?? d.tops.show,
      hidden: Array.isArray(saved.tops?.hidden) ? saved.tops.hidden.filter((f: unknown) => typeof f === 'string') : [],
    },
  }
}

function load(): ProfileDesign {
  if (typeof localStorage === 'undefined') return defaults() // SSR
  try {
    const raw = localStorage.getItem(KEY)
    return raw ? hydrate(JSON.parse(raw)) : defaults()
  } catch {
    return defaults()
  }
}

/**
 * Reactive, self-persisting profile-design state. Call once from a component's
 * top-level script; the write-back `$effect` is torn down with that component.
 */
export function createProfileDesign(): ProfileDesign {
  const design = $state<ProfileDesign>(load())

  $effect(() => {
    const snap = $state.snapshot(design) // deep read → re-runs on any nested change
    try {
      localStorage.setItem(KEY, JSON.stringify(snap))
    } catch {
      /* private mode / quota / disabled — the UI still works, it just won't persist */
    }
  })

  return design
}

/** Reset a live design object back to defaults in place (keeps the same proxy). */
export function resetProfileDesign(design: ProfileDesign): void {
  Object.assign(design, defaults())
}
