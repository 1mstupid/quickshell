.pragma library

// The arithmetic behind the study widget. No QML types and no side effects, so it
// can be tested with plain node. A run is { title, start, end }, times in ms: one
// stretch of the task timer.

// the first and last hour rows shown when no run falls outside them
const FIRST_HOUR = 4
const LAST_HOUR = 20

function dayStart(ms) {
    const d = new Date(ms)
    return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
}

function nextDayStart(ms) {
    const d = new Date(ms)
    return new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1).getTime()
}

// a run cut at each local midnight, one piece per day it touches, oldest first
function splitByDay(run) {
    const out = []
    let start = run.start
    while (start < run.end) {
        const end = Math.min(run.end, nextDayStart(start))
        out.push({ title: run.title, start: start, end: end })
        start = end
    }
    return out
}

// "Mat 1" and "Mat 3 (Bloco 2)" are both "Mat": the number and a block name in
// brackets do not make another subject
function subjectOf(title) {
    const s = title.replace(/(?:\s*\([^()]*\)|\s+\d+)+\s*$/, "").trim()
    return s === "" ? title : s
}

// The subjects in colour order: the scheduled ones sorted, so each keeps its
// colour from day to day, then any other in the order it was studied.
function subjectOrder(scheduled, runs) {
    const out = []
    for (const t of scheduled) {
        const s = subjectOf(t)
        if (out.indexOf(s) < 0)
            out.push(s)
    }
    out.sort()
    for (const r of runs) {
        const s = subjectOf(r.title)
        if (out.indexOf(s) < 0)
            out.push(s)
    }
    return out
}

// the hue (0 to 1) of the i-th subject: golden-angle steps from `base`, which keep
// neighbours far apart however many there are
function hueAt(base, i) {
    return (Math.max(0, base) + i * 0.381966) % 1
}

// the hour on the wall clock, with its fraction
function clockHours(ms) {
    const d = new Date(ms)
    return d.getHours() + d.getMinutes() / 60 + d.getSeconds() / 3600
}

// The grid for the day holding `now`:
//   { first, last, segments: [{ hour, from, to, title, ms }], totalMs }
// `from` and `to` are fractions of the hour's row, and `ms` is the length of the
// whole run the segment is cut from. Runs are clipped to the day.
function grid(runs, now) {
    const begin = dayStart(now)
    const finish = nextDayStart(now)
    const segments = []
    let first = FIRST_HOUR
    let last = LAST_HOUR
    let totalMs = 0
    for (const r of runs) {
        const start = Math.max(r.start, begin)
        const end = Math.min(r.end, finish)
        if (end <= start)
            continue
        totalMs += end - start
        const a = clockHours(start)
        // a run ending on the next midnight ends at 24, not 0
        const b = end === finish ? 24 : clockHours(end)
        for (let h = Math.floor(a); h < b; h++) {
            segments.push({ hour: h, from: Math.max(0, a - h), to: Math.min(1, b - h),
                            title: r.title, ms: end - start })
            first = Math.min(first, h)
            last = Math.max(last, h)
        }
    }
    return { first: first, last: last, segments: segments, totalMs: totalMs }
}

// the segment at a point of the grid, or null; `at` is the fraction along the row
function segmentAt(segments, hour, at) {
    for (let i = segments.length - 1; i >= 0; i--) {
        const s = segments[i]
        if (s.hour === hour && at >= s.from && at <= s.to)
            return s
    }
    return null
}
