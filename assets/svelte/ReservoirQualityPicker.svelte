<script lang="ts">
  // Reservoir Quality picker — author quality intervals by dragging on the
  // well-log chart; the bottom box is the editor for the new / selected section.
  // Ephemeral interaction state (draft band, drag, selection, toggles) lives
  // here; every committed change is pushed to the ReservoirQualityLive
  // LiveComponent as the full interval list, which validates, persists and
  // echoes the canonical list back.

  type CurvePoint = { md: number; gamma: number | null; rop: number | null; gas: number | null }
  type Interval = {
    id?: string
    from_depth: number
    to_depth: number
    quality: string
    lithology?: string | null
  }
  type Range = { min?: number; max?: number }
  type CurveMeta = {
    gamma?: Range
    rop?: Range
    gas?: Range
    cutoffs?: { gamma?: number; gas?: number }
    rop_max?: number
  }
  type LiveRef = { pushEvent: (event: string, payload?: object) => void }
  type Row = { id?: string; from: number; to: number; q: string; lith: string }

  let {
    intervals = [],
    curves = [],
    curve_metadata = {},
    md_min = null,
    md_max = null,
    quality_options = [],
    well_type = 'horizontal',
    editable = false,
    live,
  }: {
    intervals?: Interval[]
    curves?: CurvePoint[]
    curve_metadata?: CurveMeta
    md_min?: number | null
    md_max?: number | null
    quality_options?: string[]
    well_type?: string
    editable?: boolean
    live: LiveRef
  } = $props()

  const QC: Record<string, string> = {
    'Very Good': '#176935',
    Good: '#27ae60',
    Fair: '#f1c40f',
    Poor: '#e67e22',
    Nil: '#bdc3c7',
  }
  const QORDER = $derived(
    quality_options.length ? quality_options : ['Very Good', 'Good', 'Fair', 'Poor', 'Nil'],
  )

  // ── domain / scales ───────────────────────────────────────────────────────
  const mdLo = $derived(
    md_min ?? (intervals.length ? Math.min(...intervals.map((i) => i.from_depth)) : 0),
  )
  const mdHi = $derived(
    md_max ?? (intervals.length ? Math.max(...intervals.map((i) => i.to_depth)) : 1),
  )
  const span = $derived(Math.max(1, mdHi - mdLo))
  const ropMax = $derived(curve_metadata.rop_max ?? curve_metadata.rop?.max ?? 300)
  const gammaMax = $derived(curve_metadata.gamma?.max ?? 200)
  const gasMax = $derived(curve_metadata.gas?.max ?? 2000)

  // Horizontal layout (px, matches the mockup's 3a grid)
  const H = { L: 56, PW: 1020, TOP: 30, PH: 200, RIB: 246, RIBH: 28, SVGW: 1100, SVGH: 310 }
  // Vertical strip-log layout
  const V = {
    TOP: 40,
    PH: 560,
    GRX: 66,
    GRW: 150,
    ROPX: 228,
    ROPW: 140,
    GASX: 380,
    GASW: 140,
    QX: 532,
    QW: 64,
    IW: 466,
    SVGW: 940,
    SVGH: 640,
  }

  const xH = (md: number) => H.L + ((md - mdLo) / span) * H.PW
  const mdH = (off: number) => mdLo + (off / H.PW) * span
  const yV = (md: number) => V.TOP + ((md - mdLo) / span) * V.PH
  const mdV = (off: number) => mdLo + (off / V.PH) * span

  // ── canonical + preview lists ─────────────────────────────────────────────
  const curvePts = $derived<CurvePoint[]>(Array.isArray(curves) ? curves : [])

  const server = $derived<Row[]>(
    (Array.isArray(intervals) ? intervals : [])
      .map((iv) => ({
        id: iv.id,
        from: iv.from_depth,
        to: iv.to_depth,
        q: iv.quality,
        lith: iv.lithology || 'Sandstone',
      }))
      .sort((a, b) => a.from - b.from),
  )

  const sorted = $derived<Row[]>(
    server
      .map((iv) => {
        if (resizePreview && resizePreview.id === iv.id)
          return { ...iv, from: resizePreview.from, to: resizePreview.to }
        if (editId && draft && iv.id === editId)
          return { ...iv, from: draft.from, to: draft.to }
        return iv
      })
      .sort((a, b) => a.from - b.from),
  )

  function gapsOf(list: Row[]): { lo: number; hi: number }[] {
    const out: { lo: number; hi: number }[] = []
    let cur = mdLo
    for (const i of list) {
      if (i.from - cur > 1) out.push({ lo: cur, hi: i.from })
      cur = Math.max(cur, i.to)
    }
    if (mdHi - cur > 1) out.push({ lo: cur, hi: mdHi })
    return out
  }
  const gapList = $derived(gapsOf(sorted))

  const ivAt = (md: number) => sorted.find((i) => md >= i.from && md <= i.to) || null
  const gapAt = (md: number) => gapList.find((g) => md >= g.lo && md <= g.hi) || null

  function snap(md: number, gap: { lo: number; hi: number }) {
    let v = Math.round(md)
    for (const b of [gap.lo, gap.hi]) if (Math.abs(v - b) <= 8) v = b
    return Math.max(gap.lo, Math.min(gap.hi, v))
  }

  // ── ephemeral state ───────────────────────────────────────────────────────
  // svelte-ignore state_referenced_locally  (seed the layout once; the toggle then owns it)
  let wellType = $state(well_type === 'vertical' ? 'vertical' : 'horizontal')
  let graphMode = $state<'combined' | 'separate'>('combined')
  // `draft` holds the working From/To for the bottom editor box — for a brand new
  // section (editId null) or for an existing one being adjusted (editId set).
  let draft = $state<{ from: number; to: number } | null>(null)
  let editId = $state<string | null>(null)
  let resizePreview = $state<{ id: string; from: number; to: number } | null>(null)
  let selId = $state<string | null>(null)
  let popQ = $state('')
  let hover = $state<number | null>(null)

  // non-reactive drag scratch
  let drag:
    | { mode: 'new'; anchor: number; gap: { lo: number; hi: number } }
    | { mode: 'resize'; id: string; edge: 'from' | 'to' }
    | null = null
  let edgePick: { id: string; edge: 'from' | 'to' } | null = null

  const fmt = (n: number) => Math.round(n).toString()

  // ── commit ────────────────────────────────────────────────────────────────
  function commit(list: Row[]) {
    live.pushEvent('commit_intervals', {
      intervals: list.map((r) => ({
        id: r.id ?? null,
        from_depth: Math.round(r.from),
        to_depth: Math.round(r.to),
        quality: r.q,
        lithology: r.lith || 'Sandstone',
      })),
    })
  }

  // Select an existing section and load it into the bottom editor box.
  function openEdit(id: string) {
    const r = server.find((i) => i.id === id)
    if (!r) return
    selId = id
    editId = id
    draft = { from: r.from, to: r.to }
    popQ = r.q
  }

  // "Add section" (new) / "Save" (edit) — commit the bottom box.
  function saveSection() {
    if (!draft || !popQ) return
    if (editId) {
      const id = editId
      commit(
        server.map((iv) =>
          iv.id === id ? { ...iv, from: draft!.from, to: draft!.to, q: popQ } : iv,
        ),
      )
    } else {
      commit([...server, { from: draft.from, to: draft.to, q: popQ, lith: 'Sandstone' }])
    }
    clearForm()
  }

  function clearForm() {
    draft = null
    editId = null
    selId = null
    popQ = ''
  }

  function deleteSection() {
    if (editId) commit(server.filter((iv) => iv.id !== editId))
    clearForm()
  }

  function deleteRow(id: string) {
    commit(server.filter((iv) => iv.id !== id))
    if (selId === id) clearForm()
  }

  function setRowQuality(id: string, q: string) {
    commit(server.map((iv) => (iv.id === id ? { ...iv, q } : iv)))
  }

  function findGap() {
    const g = [...gapList].sort((a, b) => b.hi - b.lo - (a.hi - a.lo))[0]
    if (!g) return
    const s = g.hi - g.lo
    draft = { from: Math.round(g.lo + s * 0.2), to: Math.round(g.hi - s * 0.2) }
    editId = null
    selId = null
    popQ = ''
  }

  function setDraftEdge(which: 'from' | 'to', raw: string) {
    const v = Math.round(parseFloat(raw))
    if (isNaN(v) || !draft) return
    if (editId) {
      // adjusting an existing section — clamp against its neighbours
      const idx = server.findIndex((i) => i.id === editId)
      const lo = idx > 0 ? server[idx - 1].to : mdLo
      const hi = idx >= 0 && idx < server.length - 1 ? server[idx + 1].from : mdHi
      draft =
        which === 'from'
          ? { from: Math.max(lo, Math.min(v, draft.to - 1)), to: draft.to }
          : { from: draft.from, to: Math.min(hi, Math.max(v, draft.from + 1)) }
    } else {
      const gap = gapAt(which === 'from' ? draft.to : draft.from) || gapAt(v)
      if (!gap) return
      const c = Math.max(gap.lo, Math.min(gap.hi, v))
      draft =
        which === 'from'
          ? { from: Math.min(c, draft.to - 1), to: draft.to }
          : { from: draft.from, to: Math.max(c, draft.from + 1) }
    }
  }

  // ── pointer interaction ───────────────────────────────────────────────────
  function localMd(e: PointerEvent, orient: 'h' | 'v') {
    const rect = (e.currentTarget as HTMLElement).getBoundingClientRect()
    return orient === 'v' ? mdV(e.clientY - rect.top) : mdH(e.clientX - rect.left)
  }

  function onDown(orient: 'h' | 'v') {
    return (e: PointerEvent) => {
      if (!editable) return
      // Stop the browser starting a text/image selection-drag ("ghost" of the page).
      e.preventDefault()
      const md = localMd(e, orient)
      try {
        ;(e.currentTarget as HTMLElement).setPointerCapture(e.pointerId)
      } catch {}
      if (edgePick) {
        drag = { mode: 'resize', id: edgePick.id, edge: edgePick.edge }
        selId = edgePick.id
        edgePick = null
        draft = null
        editId = null
        return
      }
      const iv = ivAt(md)
      if (iv?.id) {
        openEdit(iv.id)
        return
      }
      const gap = gapAt(md)
      if (!gap) return
      const a = snap(md, gap)
      drag = { mode: 'new', anchor: a, gap }
      draft = { from: a, to: a }
      editId = null
      selId = null
      popQ = ''
    }
  }

  function onMove(orient: 'h' | 'v') {
    return (e: PointerEvent) => {
      const md = localMd(e, orient)
      if (!drag) {
        hover = editable ? Math.round(md) : null
        return
      }
      if (drag.mode === 'new') {
        const v = snap(md, drag.gap)
        draft = { from: Math.min(drag.anchor, v), to: Math.max(drag.anchor, v) }
        hover = Math.round(md)
        return
      }
      // resize
      const d = drag
      const list = sorted
      const idx = list.findIndex((i) => i.id === d.id)
      if (idx < 0) return
      const iv = server.find((i) => i.id === d.id)
      if (!iv) return
      const lo = idx > 0 ? list[idx - 1].to : mdLo
      const hi = idx < list.length - 1 ? list[idx + 1].from : mdHi
      let v = Math.round(md)
      if (d.edge === 'from') v = Math.max(lo, Math.min(iv.to - 3, v))
      else v = Math.min(hi, Math.max(iv.from + 3, v))
      resizePreview =
        d.edge === 'from' ? { id: d.id, from: v, to: iv.to } : { id: d.id, from: iv.from, to: v }
      hover = Math.round(md)
    }
  }

  function onUp(e: PointerEvent) {
    try {
      ;(e.currentTarget as HTMLElement).releasePointerCapture(e.pointerId)
    } catch {}
    if (drag?.mode === 'new') {
      if (draft && draft.to - draft.from >= 3) {
        // leave `draft` in place — the bottom box is now the "New section" editor
        editId = null
        selId = null
        popQ = ''
      } else {
        draft = null
      }
    } else if (drag?.mode === 'resize' && resizePreview) {
      const rp = resizePreview
      const orig = server.find((iv) => iv.id === rp.id)
      resizePreview = null
      if (orig && (rp.from !== orig.from || rp.to !== orig.to)) {
        commit(server.map((iv) => (iv.id === rp.id ? { ...iv, from: rp.from, to: rp.to } : iv)))
        // Load the adjusted band into the bottom box so its quality can be confirmed / changed.
        selId = rp.id
        editId = rp.id
        draft = { from: rp.from, to: rp.to }
        popQ = orig.q
      }
    }
    drag = null
  }

  const onLeave = () => {
    if (!drag) hover = null
  }

  // ── curve paths ───────────────────────────────────────────────────────────
  function pathH(key: 'gamma' | 'rop' | 'gas', top: number, h: number, max: number) {
    let d = ''
    let pen = false
    for (const p of curvePts) {
      const val = p[key]
      if (val == null || p.md == null) {
        pen = false
        continue
      }
      const x = xH(p.md).toFixed(1)
      const y = (top + h - (val / max) * h).toFixed(1)
      d += `${pen ? 'L' : 'M'}${x} ${y} `
      pen = true
    }
    return d.trim()
  }

  function pathV(key: 'gamma' | 'rop' | 'gas', x0: number, w: number, max: number) {
    let d = ''
    let pen = false
    for (const p of curvePts) {
      const val = p[key]
      if (val == null || p.md == null) {
        pen = false
        continue
      }
      const x = (x0 + (val / max) * w).toFixed(1)
      const y = yV(p.md).toFixed(1)
      d += `${pen ? 'L' : 'M'}${x} ${y} `
      pen = true
    }
    return d.trim()
  }

  function avgGas(from: number, to: number): string {
    const g = curvePts.filter((p) => p.md >= from && p.md <= to && p.gas != null).map((p) => p.gas as number)
    if (!g.length) return '—'
    return Math.round(g.reduce((a, b) => a + b, 0) / g.length).toLocaleString()
  }

  const hasCurves = $derived(curvePts.length > 0)

  function tickMds(): number[] {
    if (!Number.isFinite(mdLo) || !Number.isFinite(mdHi) || mdHi <= mdLo) return []
    const step = span > 1200 ? 200 : span > 500 ? 100 : 50
    const out: number[] = []
    for (let m = Math.ceil(mdLo / step) * step; m <= mdHi && out.length < 60; m += step) out.push(m)
    return out
  }
  const hTicks = $derived.by(() => tickMds().map((m) => ({ md: m, x: xH(m) })))
  const vTicks = $derived.by(() => tickMds().map((m) => ({ md: m, y: yV(m) })))

  // ── derived view models ───────────────────────────────────────────────────
  const combined = $derived(graphMode === 'combined')

  const hBands = $derived(
    sorted.map((iv) => {
      const left = xH(iv.from) - H.L
      const width = xH(iv.to) - xH(iv.from)
      const sel = iv.id === selId
      return { iv, left, width, sel, color: QC[iv.q] || '#999' }
    }),
  )
  const hGaps = $derived(
    gapList.map((g) => ({ left: xH(g.lo) - H.L, width: xH(g.hi) - xH(g.lo), wide: xH(g.hi) - xH(g.lo) > 90 })),
  )
  // dashed overlay only for a brand-new section — an existing one being adjusted
  // shows the move on its own band via `sorted`
  const draftBoxH = $derived(
    draft && !editId
      ? {
          left: xH(draft.from) - H.L,
          width: xH(draft.to) - xH(draft.from),
          color: popQ ? QC[popQ] : '#176935',
        }
      : null,
  )

  const vBands = $derived(
    sorted.map((iv) => {
      const topPx = yV(iv.from) - V.TOP
      const h = yV(iv.to) - yV(iv.from)
      return { iv, topPx, h, sel: iv.id === selId, color: QC[iv.q] || '#999' }
    }),
  )
  const vLabels = $derived(
    sorted
      .filter((iv) => yV(iv.to) - yV(iv.from) > 13)
      .map((iv) => ({ iv, y: yV(iv.from) + 1, sel: iv.id === selId })),
  )
  const draftBoxV = $derived(
    draft && !editId
      ? {
          top: yV(draft.from) - V.TOP,
          h: yV(draft.to) - yV(draft.from),
          color: popQ ? QC[popQ] : '#176935',
        }
      : null,
  )

  const fromVal = $derived(draft ? String(draft.from) : '')
  const toVal = $derived(draft ? String(draft.to) : '')
  const lenLabel = $derived(draft ? `= ${fmt(draft.to - draft.from)} m` : '')
  const statusText = $derived(
    !editable
      ? 'Read-only — this report is no longer active.'
      : editId
        ? 'Adjust From / To / Quality below, then Save — or Delete the section.'
        : draft
          ? 'Pick a quality below and Add the section.'
          : 'Drag across the log to mark a section, or click a band to edit it.',
  )

  // rows for the table: intervals + unclassified gaps + the pending draft, in depth order
  type Seg = { kind: 'iv' | 'gap' | 'draft'; from: number; to: number; row?: Row }
  const tableSegs = $derived.by<Seg[]>(() => {
    const segs: Seg[] = sorted.map((r) => ({ kind: 'iv', from: r.from, to: r.to, row: r }))
    for (const g of gapList) {
      if (draft && !editId && draft.from >= g.lo && draft.to <= g.hi) {
        if (draft.from - g.lo > 1) segs.push({ kind: 'gap', from: g.lo, to: draft.from })
        segs.push({ kind: 'draft', from: draft.from, to: draft.to })
        if (g.hi - draft.to > 1) segs.push({ kind: 'gap', from: draft.to, to: g.hi })
      } else {
        segs.push({ kind: 'gap', from: g.lo, to: g.hi })
      }
    }
    return segs.sort((a, b) => a.from - b.from)
  })

  const setWell = (t: 'horizontal' | 'vertical') => (wellType = t)
  const setGraph = (m: 'combined' | 'separate') => (graphMode = m)

  function segBtn(active: boolean) {
    return `flex:1;padding:6px 12px;font:600 11.5px 'Roboto',system-ui,sans-serif;border:none;cursor:pointer;background:${
      active ? '#176935' : '#fff'
    };color:${active ? '#fff' : '#555'}`
  }
</script>

<div style="font-family:'Roboto',system-ui,sans-serif;color:#1a1a1a;display:flex;flex-direction:column;gap:14px">
  <!-- toggles -->
  <div style="display:flex;align-items:center;flex-wrap:wrap;gap:12px">
    {#if editable}
      <div style="display:flex;border:1px solid #e0e0e0;border-radius:6px;overflow:hidden;width:236px">
        <button type="button" style={segBtn(wellType === 'horizontal')} onclick={() => setWell('horizontal')}>Horizontal well</button>
        <button type="button" style={segBtn(wellType === 'vertical')} onclick={() => setWell('vertical')}>Vertical well</button>
      </div>
    {/if}
    {#if hasCurves}
      <div style="display:flex;border:1px solid #e0e0e0;border-radius:6px;overflow:hidden;width:232px">
        <button type="button" style={segBtn(combined)} onclick={() => setGraph('combined')}>Combined graph</button>
        <button type="button" style={segBtn(!combined)} onclick={() => setGraph('separate')}>Separate graphs</button>
      </div>
    {/if}
    <span style="font:400 11px 'Roboto',system-ui,sans-serif;color:#93a995">{statusText}</span>
  </div>

  <!-- ── HORIZONTAL ──────────────────────────────────────────────────────── -->
  {#if wellType === 'horizontal'}
    <div style="overflow-x:auto">
      <div style="position:relative;width:{H.SVGW}px;height:{H.SVGH}px;background:#fff;border:1px solid #ececec;border-radius:8px;user-select:none;-webkit-user-select:none">
        {#if hasCurves}
          <svg width={H.SVGW} height={H.SVGH} style="position:absolute;left:0;top:0;pointer-events:none">
            <g stroke="#f0ede8" stroke-width="1">
              <line x1={H.L} y1="80" x2={H.L + H.PW} y2="80" />
              <line x1={H.L} y1="130" x2={H.L + H.PW} y2="130" />
              <line x1={H.L} y1="180" x2={H.L + H.PW} y2="180" />
            </g>
            <g stroke="#e0ddd6" stroke-width="1">
              <line x1={H.L} y1={H.TOP} x2={H.L} y2={H.TOP + H.PH} />
              <line x1={H.L} y1={H.TOP + H.PH} x2={H.L + H.PW} y2={H.TOP + H.PH} />
            </g>
            {#if combined}
              <path d={pathH('gas', H.TOP, H.PH, gasMax)} fill="none" stroke="#dc3545" stroke-width="1.1" opacity="0.85" />
              <path d={pathH('rop', H.TOP, H.PH, ropMax)} fill="none" stroke="#000" stroke-width="1.1" opacity="0.7" />
              <path d={pathH('gamma', H.TOP, H.PH, gammaMax)} fill="none" stroke="#176935" stroke-width="1.4" />
            {:else}
              <path d={pathH('gamma', 30, 60, gammaMax)} fill="none" stroke="#176935" stroke-width="1.2" />
              <path d={pathH('rop', 100, 60, ropMax)} fill="none" stroke="#000" stroke-width="1.2" />
              <path d={pathH('gas', 170, 60, gasMax)} fill="none" stroke="#dc3545" stroke-width="1.2" />
            {/if}
          </svg>
          <div style="position:absolute;left:{H.L}px;top:10px;font:700 9.5px 'Roboto',system-ui,sans-serif;color:#555;letter-spacing:.04em">
            {#if combined}
              NORMALISED — <span style="color:#176935">GR</span> · <span style="color:#000">ROP</span> · <span style="color:#dc3545">GAS</span> (% of range)
            {:else}
              SEPARATE TRACKS · <span style="color:#176935">GR 0–{gammaMax}</span> · <span style="color:#000">ROP 0–{ropMax}</span> · <span style="color:#dc3545">GAS 0–{gasMax}</span>
            {/if}
          </div>
        {:else}
          <div style="position:absolute;left:{H.L}px;top:10px;font:700 9.5px 'Roboto',system-ui,sans-serif;color:#93a995">NO LOG CURVES — COVERAGE RIBBON ONLY</div>
        {/if}

        <div style="position:absolute;left:0;top:{H.RIB - 4}px;width:48px;text-align:right;font:700 9px 'Roboto',system-ui,sans-serif;color:#555">QUAL</div>

        {#each hTicks as t (t.md)}
          <div style="position:absolute;top:280px;left:{t.x}px;width:60px;margin-left:-30px;text-align:center;font:400 9.5px 'Roboto',system-ui,sans-serif;color:#888">{t.md}</div>
        {/each}
        <div style="position:absolute;left:{H.L}px;top:294px;width:{H.PW}px;text-align:center;font:400 9.5px 'Roboto',system-ui,sans-serif;color:#555">Measured Depth (m)</div>

        <!-- interactive overlay -->
        <div
          role="presentation"
          onpointerdown={onDown('h')}
          onpointermove={onMove('h')}
          onpointerup={onUp}
          onpointerleave={onLeave}
          style="position:absolute;left:{H.L}px;top:{H.TOP}px;width:{H.PW}px;height:{H.RIB - H.TOP + H.RIBH}px;cursor:{editable ? 'crosshair' : 'default'};touch-action:none"
        >
          <!-- faint per-band backdrop over the plot -->
          {#each hBands as b, bi (b.iv.id ?? 'b' + bi)}
            <div
              role="presentation"
              onclick={() => b.iv.id && openEdit(b.iv.id)}
              style="position:absolute;top:0;height:{H.PH}px;left:{b.left}px;width:{b.width}px;background:{b.color}{b.sel ? '22' : '14'};box-sizing:border-box;border-left:1px solid rgba(0,0,0,.08);cursor:pointer;{b.sel ? 'box-shadow:inset 0 0 0 1px rgba(0,0,0,.35);z-index:2;' : 'z-index:1;'}"
            ></div>
          {/each}
          <!-- coverage ribbon -->
          {#each hBands as b, bi (b.iv.id ?? 'b' + bi)}
            <div
              role="presentation"
              onclick={() => b.iv.id && openEdit(b.iv.id)}
              style="position:absolute;top:{H.RIB - H.TOP}px;height:{H.RIBH}px;left:{b.left}px;width:{b.width}px;background:{b.color};box-sizing:border-box;border-left:1px solid rgba(0,0,0,.18);cursor:pointer;display:flex;align-items:center;padding-left:4px;font:700 9.5px 'Roboto',system-ui,sans-serif;color:{b.iv.q === 'Fair' || b.iv.q === 'Nil' ? '#000' : '#fff'};{b.sel ? 'outline:2px solid #111;outline-offset:-1px;z-index:4;' : 'z-index:3;'}"
            >
              {b.width > 40 ? b.iv.q : ''}
            </div>
          {/each}
          {#each hGaps as g, gi (gi)}
            <div
              style="position:absolute;top:{H.RIB - H.TOP}px;height:{H.RIBH}px;left:{g.left}px;width:{g.width}px;background:#e6e6e6;background-image:repeating-linear-gradient(45deg,#fff 0 3px,transparent 3px 6px);box-sizing:border-box;border:1px dashed #b5b5b5;z-index:3;display:flex;align-items:center;padding-left:4px;font:500 9px 'Roboto',system-ui,sans-serif;color:#777"
            >
              {g.wide ? 'Unclassified' : ''}
            </div>
          {/each}
          <!-- resize edge handles -->
          {#if editable}
            {#each hBands as b, bi (b.iv.id ?? 'b' + bi)}
              {#if b.sel && b.iv.id}
                <div
                  role="presentation"
                  onpointerdown={() => (edgePick = { id: b.iv.id!, edge: 'from' })}
                  style="position:absolute;top:{H.RIB - H.TOP - 4}px;height:{H.RIBH + 8}px;width:7px;left:{b.left - 4}px;cursor:ew-resize;z-index:7;background:#111;border:1px solid #fff;border-radius:2px;box-shadow:0 1px 3px rgba(0,0,0,.45)"
                ></div>
                <div
                  role="presentation"
                  onpointerdown={() => (edgePick = { id: b.iv.id!, edge: 'to' })}
                  style="position:absolute;top:{H.RIB - H.TOP - 4}px;height:{H.RIBH + 8}px;width:7px;left:{b.left + b.width - 3}px;cursor:ew-resize;z-index:7;background:#111;border:1px solid #fff;border-radius:2px;box-shadow:0 1px 3px rgba(0,0,0,.45)"
                ></div>
              {/if}
            {/each}
          {/if}
          {#if draftBoxH}
            <div style="position:absolute;top:0;height:{H.RIB - H.TOP + H.RIBH}px;left:{draftBoxH.left}px;width:{draftBoxH.width}px;background:{draftBoxH.color}2b;border:2px dashed {draftBoxH.color};box-sizing:border-box;z-index:6;pointer-events:none"></div>
          {/if}
        </div>

      </div>
    </div>

  <!-- ── VERTICAL ────────────────────────────────────────────────────────── -->
  {:else}
    <div style="overflow-x:auto">
      <div style="position:relative;width:{V.SVGW}px;height:{V.SVGH}px;background:#fff;border:1px solid #ececec;border-radius:8px;user-select:none;-webkit-user-select:none">
        {#if hasCurves}
          <svg width={V.SVGW} height={V.SVGH} style="position:absolute;left:0;top:0;pointer-events:none">
            <g stroke="#e0ddd6" stroke-width="1">
              <line x1={V.GRX} y1={V.TOP} x2={V.GRX} y2={V.TOP + V.PH} />
              <line x1={V.GRX + V.IW} y1={V.TOP} x2={V.GRX + V.IW} y2={V.TOP + V.PH} />
              <line x1={V.GRX} y1={V.TOP} x2={V.GRX + V.IW} y2={V.TOP} />
              <line x1={V.GRX} y1={V.TOP + V.PH} x2={V.GRX + V.IW} y2={V.TOP + V.PH} />
            </g>
            {#if combined}
              <path d={pathV('gas', V.GRX, V.IW - 12, gasMax)} fill="none" stroke="#dc3545" stroke-width="1.1" opacity="0.85" />
              <path d={pathV('rop', V.GRX, V.IW - 12, ropMax)} fill="none" stroke="#000" stroke-width="1.1" opacity="0.7" />
              <path d={pathV('gamma', V.GRX, V.IW - 12, gammaMax)} fill="none" stroke="#176935" stroke-width="1.4" />
            {:else}
              <path d={pathV('gamma', V.GRX, V.GRW, gammaMax)} fill="none" stroke="#176935" stroke-width="1.1" />
              <path d={pathV('rop', V.ROPX, V.ROPW, ropMax)} fill="none" stroke="#000" stroke-width="1.1" />
              <path d={pathV('gas', V.GASX, V.GASW, gasMax)} fill="none" stroke="#dc3545" stroke-width="1.1" />
            {/if}
          </svg>
          <div style="position:absolute;left:{V.GRX}px;top:16px;width:{V.IW}px;text-align:center;font:700 9.5px 'Roboto',system-ui,sans-serif;color:#555">
            {#if combined}
              NORMALISED — <span style="color:#176935">GR</span> · <span style="color:#000">ROP</span> · <span style="color:#dc3545">GAS</span>
            {:else}
              <span style="color:#176935">GR 0–{gammaMax}</span> · <span style="color:#000">ROP 0–{ropMax}</span> · <span style="color:#dc3545">GAS 0–{gasMax}</span>
            {/if}
          </div>
        {/if}
        <div style="position:absolute;left:0;top:16px;width:56px;text-align:right;font:700 9.5px 'Roboto',system-ui,sans-serif;color:#555">MD m</div>
        <div style="position:absolute;left:{V.QX}px;top:16px;width:{V.QW}px;text-align:center;font:700 9.5px 'Roboto',system-ui,sans-serif;color:#555">QUAL</div>
        <div style="position:absolute;left:{V.QX + V.QW + 10}px;top:16px;font:700 9.5px 'Roboto',system-ui,sans-serif;color:#555">SECTION</div>

        {#each vTicks as t (t.md)}
          <div style="position:absolute;left:0;top:{t.y - 6}px;width:56px;text-align:right;font:400 9.5px 'Roboto',system-ui,sans-serif;color:#888">{t.md}</div>
        {/each}

        <div
          role="presentation"
          onpointerdown={onDown('v')}
          onpointermove={onMove('v')}
          onpointerup={onUp}
          onpointerleave={onLeave}
          style="position:absolute;left:{V.GRX}px;top:{V.TOP}px;width:{V.IW + V.QW}px;height:{V.PH}px;cursor:{editable ? 'crosshair' : 'default'};touch-action:none"
        >
          {#each vBands as b, bi (b.iv.id ?? 'b' + bi)}
            <div
              role="presentation"
              onclick={() => b.iv.id && openEdit(b.iv.id)}
              style="position:absolute;left:0;width:{V.IW}px;top:{b.topPx}px;height:{b.h}px;background:{b.color}{b.sel ? '2e' : '1c'};box-sizing:border-box;border-top:1px solid {b.color}66;cursor:pointer;{b.sel ? 'box-shadow:inset 0 0 0 1px rgba(0,0,0,.35);z-index:2;' : 'z-index:1;'}"
            ></div>
            <div
              role="presentation"
              onclick={() => b.iv.id && openEdit(b.iv.id)}
              style="position:absolute;left:{V.IW}px;width:{V.QW}px;top:{b.topPx}px;height:{b.h}px;background:{b.color};box-sizing:border-box;border-top:1px solid rgba(0,0,0,.15);cursor:pointer;{b.sel ? 'outline:2px solid #111;outline-offset:-1px;z-index:4;' : 'z-index:3;'}"
            ></div>
            {#if editable && b.sel && b.iv.id}
              <div role="presentation" onpointerdown={() => (edgePick = { id: b.iv.id!, edge: 'from' })} style="position:absolute;left:0;width:{V.IW + V.QW}px;height:7px;top:{b.topPx - 4}px;cursor:ns-resize;z-index:7;background:#111;border:1px solid #fff;border-radius:2px;box-shadow:0 1px 3px rgba(0,0,0,.45)"></div>
              <div role="presentation" onpointerdown={() => (edgePick = { id: b.iv.id!, edge: 'to' })} style="position:absolute;left:0;width:{V.IW + V.QW}px;height:7px;top:{b.topPx + b.h - 3}px;cursor:ns-resize;z-index:7;background:#111;border:1px solid #fff;border-radius:2px;box-shadow:0 1px 3px rgba(0,0,0,.45)"></div>
            {/if}
          {/each}
          {#if draftBoxV}
            <div style="position:absolute;left:0;width:{V.IW + V.QW}px;top:{draftBoxV.top}px;height:{draftBoxV.h}px;background:{draftBoxV.color}2b;border:2px dashed {draftBoxV.color};box-sizing:border-box;z-index:6;pointer-events:none"></div>
          {/if}
        </div>

        {#each vLabels as l, li (l.iv.id ?? 'l' + li)}
          <div style="position:absolute;left:{V.QX + V.QW + 10}px;top:{l.y}px;font:{l.sel ? '700' : '400'} 9.5px 'Roboto',system-ui,sans-serif;white-space:nowrap;color:{l.iv.q === 'Nil' ? '#93a995' : '#333'}">
            {fmt(l.iv.from)}–{fmt(l.iv.to)}&nbsp;&nbsp;{l.iv.q} {l.iv.lith}
          </div>
        {/each}

      </div>
    </div>
  {/if}

  <!-- ── SECTION EDITOR ──────────────────────────────────────────────────── -->
  {#if editable}
    {@const busy = !!draft && !!popQ}
    <div style="border:1px solid {editId ? '#176935' : '#ececec'};background:#fff;border-radius:8px;padding:12px 14px">
      <div style="display:flex;align-items:flex-end;flex-wrap:wrap;gap:10px">
        <span style="font:700 11px 'Roboto',system-ui,sans-serif;color:{editId ? '#176935' : '#555'};text-transform:uppercase;letter-spacing:.06em;padding-bottom:7px">
          {editId ? 'Edit section' : 'New section'}
        </span>
        <label style="display:flex;flex-direction:column;gap:3px;font:500 10px 'Roboto',system-ui,sans-serif;color:#93a995">
          FROM (m)
          <input
            type="number" step="1" placeholder="—" value={fromVal} disabled={!draft}
            onchange={(e) => setDraftEdge('from', (e.currentTarget as HTMLInputElement).value)}
            style="width:96px;box-sizing:border-box;border:1px solid #e0e0e0;border-radius:4px;padding:6px 7px;font:400 13px 'Roboto',system-ui,sans-serif"
          />
        </label>
        <label style="display:flex;flex-direction:column;gap:3px;font:500 10px 'Roboto',system-ui,sans-serif;color:#93a995">
          TO (m)
          <input
            type="number" step="1" placeholder="—" value={toVal} disabled={!draft}
            onchange={(e) => setDraftEdge('to', (e.currentTarget as HTMLInputElement).value)}
            style="width:96px;box-sizing:border-box;border:1px solid #e0e0e0;border-radius:4px;padding:6px 7px;font:400 13px 'Roboto',system-ui,sans-serif"
          />
        </label>
        <span style="font:500 11px 'Roboto',system-ui,sans-serif;color:#93a995;padding-bottom:7px">{lenLabel}</span>
        <label style="display:flex;flex-direction:column;gap:3px;font:500 10px 'Roboto',system-ui,sans-serif;color:#93a995">
          QUALITY
          <select
            value={popQ} disabled={!draft}
            onchange={(e) => (popQ = (e.currentTarget as HTMLSelectElement).value)}
            style="width:150px;box-sizing:border-box;border:1px solid #e0e0e0;border-radius:4px;padding:6px 8px;font:400 13px 'Roboto',system-ui,sans-serif"
          >
            <option value="">Select…</option>
            {#each QORDER as q}<option value={q}>{q}</option>{/each}
          </select>
        </label>
        <button
          type="button"
          onclick={saveSection}
          disabled={!busy}
          style="font:700 11.5px 'Roboto',system-ui,sans-serif;padding:8px 15px;border:none;border-radius:9999px;color:#fff;background:{busy ? '#176935' : '#93a995'};cursor:{busy ? 'pointer' : 'not-allowed'}"
        >
          {editId ? 'Save' : 'Add section'}
        </button>
        {#if editId}
          <button type="button" onclick={deleteSection} style="background:transparent;color:#dc3545;font:700 11.5px 'Roboto',system-ui,sans-serif;padding:6px 13px;border:2px solid #dc3545;border-radius:9999px;cursor:pointer">Delete</button>
        {:else}
          <button type="button" onclick={findGap} style="background:transparent;color:#114a26;font:700 11.5px 'Roboto',system-ui,sans-serif;padding:6px 13px;border:2px solid #114a26;border-radius:9999px;cursor:pointer">Find gap</button>
        {/if}
        <button type="button" onclick={clearForm} disabled={!draft} style="background:transparent;border:none;color:#93a995;font:500 11.5px 'Roboto',system-ui,sans-serif;cursor:{draft ? 'pointer' : 'default'};text-decoration:underline;padding-bottom:8px">
          {editId ? 'Cancel' : 'Clear'}
        </button>
      </div>
    </div>
  {/if}

  <!-- ── TABLE ───────────────────────────────────────────────────────────── -->
  <div style="border:1px solid #ececec;border-radius:8px;overflow:hidden;background:#fff">
    <div style="display:flex;align-items:center;justify-content:space-between;padding:9px 14px;background:#f8f8f8;border-bottom:1px solid #ececec">
      <span style="font:600 12px 'Roboto',system-ui,sans-serif;color:#555;text-transform:uppercase;letter-spacing:.06em">Sections{editable ? ' · live-synced' : ''}</span>
      <span style="font:400 11px 'Roboto',system-ui,sans-serif;color:#93a995">
        {sorted.length} section{sorted.length === 1 ? '' : 's'} · {gapList.length} unclassified gap{gapList.length === 1 ? '' : 's'}
      </span>
    </div>
    <div style="overflow-x:auto">
      <table style="width:100%;border-collapse:collapse;font-size:12px">
        <thead>
          <tr style="background:#176935;color:#fff">
            {#each ['From (m)', 'To (m)', 'Interval (m)', 'Quality', 'Avg gas (units)', 'Lithology'] as h}
              <th style="text-align:{h === 'Avg gas (units)' ? 'right' : 'left'};padding:7px 14px;font:600 11px 'Roboto',system-ui,sans-serif;border-bottom:2px solid #114a26;white-space:nowrap">{h}</th>
            {/each}
            {#if editable}<th style="border-bottom:2px solid #114a26"></th>{/if}
          </tr>
        </thead>
        <tbody>
          {#each tableSegs as s, si (si)}
            {@const isIv = s.kind === 'iv'}
            {@const isDraft = s.kind === 'draft'}
            {@const c = isIv ? QC[s.row!.q] : isDraft && popQ ? QC[popQ] : '#cfcfcf'}
            <!-- svelte-ignore a11y_click_events_have_key_events a11y_no_static_element_interactions -->
            <tr
              onclick={() => isIv && s.row?.id && openEdit(s.row.id)}
              style="cursor:{isIv ? 'pointer' : 'default'};font:{isIv && s.row?.id === selId ? 700 : 400} 12px 'Roboto',system-ui,sans-serif;background:{isDraft ? '#fff8dc' : isIv && s.row?.id === selId ? '#d3e8d5' : s.kind === 'gap' ? '#fafafa' : 'transparent'}{s.kind === 'gap' || isDraft ? ';color:#555' : ''}"
            >
              <td style="padding:5px 14px;border-bottom:1px solid #ececec">{fmt(s.from)}</td>
              <td style="padding:5px 14px;border-bottom:1px solid #ececec">{fmt(s.to)}</td>
              <td style="padding:5px 14px;border-bottom:1px solid #ececec">{fmt(s.to - s.from)}</td>
              <td style="padding:5px 14px;border-bottom:1px solid #ececec">
                <span style="display:inline-flex;align-items:center;gap:7px">
                  <span style="display:inline-block;width:11px;height:9px;border-radius:2px;border:1px solid rgba(0,0,0,.12);background:{c}{s.kind === 'gap' ? ';background-image:repeating-linear-gradient(45deg,#fff 0 2px,transparent 2px 4px)' : ''}"></span>
                  {#if isIv && editable && s.row?.id}
                    <select
                      value={s.row.q}
                      onchange={(e) => setRowQuality(s.row!.id!, (e.currentTarget as HTMLSelectElement).value)}
                      onclick={(e) => e.stopPropagation()}
                      style="border:1px solid #e0e0e0;border-radius:4px;padding:2px 4px;font:400 11.5px 'Roboto',system-ui,sans-serif;background:#fff"
                    >
                      {#each QORDER as q}<option value={q}>{q}</option>{/each}
                    </select>
                  {:else}
                    {isIv ? s.row!.q : isDraft ? popQ || 'Setting quality…' : 'Unclassified'}
                  {/if}
                </span>
              </td>
              <td style="padding:5px 14px;border-bottom:1px solid #ececec;text-align:right;font-variant-numeric:tabular-nums">
                {isIv ? avgGas(s.from, s.to) : '—'}
              </td>
              <td style="padding:5px 14px;border-bottom:1px solid #ececec;color:#555">{isIv ? s.row!.lith : '—'}</td>
              {#if editable}
                <td style="padding:5px 10px;border-bottom:1px solid #ececec;text-align:right">
                  {#if isIv && s.row?.id}
                    <button type="button" title="Delete section" onclick={(e) => { e.stopPropagation(); deleteRow(s.row!.id!) }} style="background:transparent;border:none;color:#93a995;font:400 15px 'Roboto',system-ui,sans-serif;cursor:pointer;line-height:1">×</button>
                  {/if}
                </td>
              {/if}
            </tr>
          {/each}
          {#if tableSegs.length === 0}
            <tr><td colspan={editable ? 7 : 6} style="padding:14px;color:#93a995">No sections yet.</td></tr>
          {/if}
        </tbody>
      </table>
    </div>
  </div>

  <!-- ── LEGEND ──────────────────────────────────────────────────────────── -->
  <div style="display:flex;flex-wrap:wrap;align-items:center;gap:14px;font:400 10.5px 'Roboto',system-ui,sans-serif;color:#555">
    {#each QORDER as q}
      <span style="display:flex;align-items:center;gap:5px">
        <span style="display:inline-block;width:13px;height:10px;border-radius:2px;border:1px solid rgba(0,0,0,.12);background:{QC[q] || '#999'}"></span>{q}
      </span>
    {/each}
    <span style="display:flex;align-items:center;gap:5px">
      <span style="display:inline-block;width:13px;height:10px;border-radius:2px;border:1px solid rgba(0,0,0,.12);background:#cfcfcf;background-image:repeating-linear-gradient(45deg,#fff 0 2px,transparent 2px 4px)"></span>Unclassified
    </span>
    {#if hover !== null}<span style="margin-left:auto;font:500 11px ui-monospace,Menlo,monospace;color:#555">MD {hover} m</span>{/if}
  </div>
</div>
