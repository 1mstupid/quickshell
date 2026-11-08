.pragma library

// Parsing and line edits for todo.md. No QML types and no side effects, so it
// can be tested with plain node.
//
//   ## 2026-11-04
//   - [ ] Send the weekly update
//   - [ ] Call mom @16:30
//   - [x] Pick up groceries  p1
//   - [ ] Write the report @15:00 p2 ~1h05m
//
// A "## YYYY-MM-DD" heading sets the due date of the tasks under it; text after
// the date is ignored. Any other heading ends that day, so tasks under it, or
// above the first date heading, have no due date and are skipped. After the
// title come optional tokens, in any order: @HH:MM is the hour of the day it is
// due, p1 to p3 is the priority, and ~1h05m (or ~45m) is the time spent on it,
// which the task timer writes.

const dateRe = /^##\s+(\d{4}-\d{2}-\d{2})(?:\s|$)/
const headingRe = /^#{1,6}(?:\s|$)/
const taskRe = /^- \[( |x|X)\]\s+(\S.*?)\s*$/
const timeRe = /\s+@([01]?\d|2[0-3]):([0-5]\d)$/
const prioRe = /\s+p([1-3])$/
const spentRe = /\s+~(?:(\d+)h)?(?:(\d+)m)?$/

// the trailing token on s, or null: { kind, index } with `index` where its
// leading whitespace starts, plus time, priority or minutes by kind
function peel(s) {
    let m = s.match(timeRe)
    if (m)
        return { kind: "time", index: m.index, time: m[1].padStart(2, "0") + ":" + m[2] }
    m = s.match(prioRe)
    if (m)
        return { kind: "priority", index: m.index, priority: parseInt(m[1]) }
    m = s.match(spentRe)
    if (m && (m[1] !== undefined || m[2] !== undefined))
        return { kind: "spent", index: m.index, minutes: (parseInt(m[1]) || 0) * 60 + (parseInt(m[2]) || 0) }
    return null
}

// text in, tasks out: { done, title, due, priority, time, spent, line, raw }.
// `time` is "HH:MM" or "", `spent` is minutes. `line` and `raw` address the
// task for edit() below.
function parse(text) {
    const out = []
    const lines = text.split("\n")
    let due = ""
    for (let i = 0; i < lines.length; i++) {
        const h = lines[i].match(dateRe)
        if (h) {
            due = h[1]
            continue
        }
        if (headingRe.test(lines[i])) {
            due = ""
            continue
        }
        const m = due !== "" ? lines[i].match(taskRe) : null
        if (m) {
            let title = m[2]
            const got = {}
            for (;;) {
                const p = peel(title)
                // a second token of a kind stays in the title
                if (p === null || p.kind in got)
                    break
                got[p.kind] = p
                title = title.slice(0, p.index)
            }
            out.push({
                done: m[1] !== " ",
                title: title,
                due: due,
                priority: got.priority ? got.priority.priority : 0,
                time: got.time ? got.time.time : "",
                spent: got.spent ? got.spent.minutes : 0,
                line: i,
                raw: lines[i]
            })
        }
    }
    return out
}

// the task line with its box flipped
function toggled(raw) {
    return raw.replace(/^- \[[ xX]\]/, m => m === "- [ ]" ? "- [x]" : "- [ ]")
}

// Replaces line `line` with `to`, or removes it when `to` is null. Returns
// null when that line no longer reads `raw`, meaning the file changed since it
// was parsed. Addressing by position keeps identical tasks on different days apart.
function edit(text, line, raw, to) {
    const lines = text.split("\n")
    if (lines[line] !== raw)
        return null
    if (to === null)
        lines.splice(line, 1)
    else
        lines[line] = to
    return lines.join("\n")
}

// minutes as "45m" or "1h05m"
function fmtSpent(minutes) {
    const h = Math.floor(minutes / 60)
    const m = minutes % 60
    return h > 0 ? h + "h" + String(m).padStart(2, "0") + "m" : m + "m"
}

// the task line with its time spent set to `minutes`: the ~ token is replaced
// where it stands, or added at the end when there is none
function withSpent(raw, minutes) {
    const trail = raw.match(/\s*$/)[0]
    const s = raw.slice(0, raw.length - trail.length)
    let t = s
    for (;;) {
        const p = peel(t)
        if (p === null)
            break
        if (p.kind === "spent")
            return s.slice(0, p.index) + " ~" + fmtSpent(minutes) + s.slice(t.length) + trail
        t = t.slice(0, p.index)
    }
    return s + " ~" + fmtSpent(minutes) + trail
}

// What is left to do by `today`: open tasks due today or overdue, overdue first
// (oldest day first). Within a day the ones with an hour come first, earliest
// first, then the rest with p1 before p2 before p3 and unprioritised last, then
// file order. Returns the same objects parse() gave, so they can still be edited.
function upcoming(items, today) {
    const rank = t => (t.priority === 0 ? 4 : t.priority)
    return items
        .filter(t => !t.done && t.due !== "" && t.due <= today)
        .sort((a, b) => {
            const aLate = a.due < today, bLate = b.due < today
            if (aLate !== bLate)
                return aLate ? -1 : 1
            if (a.due !== b.due)
                return a.due < b.due ? -1 : 1
            if (a.time !== b.time) {
                if (a.time === "" || b.time === "")
                    return a.time === "" ? 1 : -1
                return a.time < b.time ? -1 : 1
            }
            return (rank(a) - rank(b)) || (a.line - b.line)
        })
}
