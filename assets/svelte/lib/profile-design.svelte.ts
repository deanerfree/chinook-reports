// Persisted design/style state for the wellbore profile chart.
//
// One object, branched by concern, serialised to localStorage as a single blob
// and restored on the next visit. Only *design* choices live here — ephemeral
// view state (selected leg, drawer open, zoom window, hidden event labels) stays
// as plain `$state` in the component.

type CurveKey = 'rop' | 'gas' | 'gamma'

export type ProfileDesign = {
  version: 1
  legend: {
    show: boolean
  }
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
    labels: boolean  // formation name printed on each top line
    hidden: string[] // formation names the user has switched off
  }
  axes: {
    // Fixed axis bounds in metres; null fits that end to the data.
    xMin: number | null
    xMax: number | null
    yMin: number | null
    yMax: number | null
  }
}

const VERSION = 1
const KEY = 'chinook:profile-design'

// Fresh defaults on every call — never share object references into `$state`.
function defaults(): ProfileDesign {
  return {
    version: VERSION,
    legend: { show: true },
    style: { showBackdrop: true, backdropOpacity: 0.16, showColors: true, pathOpacity: 1 },
    curves: {
      overlayOn: true,
      show: { rop: true, gas: true, gamma: true },
      quality: { rop: true, gas: true, gamma: true },
    },
    tops: { show: true, labels: true, hidden: [] },
    axes: { xMin: -10, xMax: null, yMin: null, yMax: null },
  }
}

// Deep-merge a (possibly partial, possibly stale) saved blob over the defaults so
// options added after the blob was written still get a sane value.
function hydrate(saved: any): ProfileDesign {
  const d = defaults()
  if (!saved || typeof saved !== 'object' || saved.version !== VERSION) return d
  return {
    version: VERSION,
    legend: { ...d.legend, ...saved.legend },
    style: { ...d.style, ...saved.style },
    curves: {
      ...d.curves,
      ...saved.curves,
      show: { ...d.curves.show, ...saved.curves?.show },
      quality: { ...d.curves.quality, ...saved.curves?.quality },
    },
    tops: {
      show: saved.tops?.show ?? d.tops.show,
      labels: saved.tops?.labels ?? d.tops.labels,
      hidden: Array.isArray(saved.tops?.hidden) ? saved.tops.hidden.filter((f: unknown) => typeof f === 'string') : [],
    },
    axes: {
      xMin: bound(saved.axes, 'xMin', d.axes.xMin),
      xMax: bound(saved.axes, 'xMax', d.axes.xMax),
      yMin: bound(saved.axes, 'yMin', d.axes.yMin),
      yMax: bound(saved.axes, 'yMax', d.axes.yMax),
    },
  }
}

// A saved axis bound: a finite number, an explicit null (cleared by the user),
// or — when the key is missing from an older blob — the default.
function bound(saved: any, key: string, fallback: number | null): number | null {
  if (!saved || typeof saved !== 'object' || !(key in saved)) return fallback
  const v = saved[key]
  return typeof v === 'number' && Number.isFinite(v) ? v : null
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
