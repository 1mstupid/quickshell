.pragma library

// Per-notification state for the toasts and the history, kept by notification id:
//   { time: "14:32", quiet: true }
// `quiet` means the toast is over, or was never shown. The notification itself
// stays in the history until it is dismissed. Every function returns a new
// object when something changed, so a QML property holding it notifies. No QML
// types, so it can be tested with plain node.

// The state after a notification arrives. Entries for ids not in `live` (the
// ids still kept) are dropped, so the map never outgrows the history.
function arrived(meta, live, id, time, quiet) {
    const out = {}
    for (const k of live)
        if (meta[k] !== undefined)
            out[k] = meta[k]
    out[id] = { time: time, quiet: quiet }
    return out
}

// the state after the toast of `id` is over; the same object if it already was
function expired(meta, id) {
    const m = meta[id]
    if (m !== undefined && m.quiet)
        return meta
    const out = Object.assign({}, meta)
    out[id] = { time: m !== undefined ? m.time : "", quiet: true }
    return out
}

// an id that is not known yet shows as a toast
function isToast(meta, id) {
    const m = meta[id]
    return m === undefined || !m.quiet
}

function timeOf(meta, id) {
    const m = meta[id]
    return m === undefined ? "" : m.time
}
