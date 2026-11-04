.pragma library

// Parsing and line edits for todo.md. No QML types and no side effects, so it
// can be tested with plain node.
//
//   ## 2026-11-04
//   - [ ] Send the weekly update
//   - [x] Pick up groceries  p1
//
// A "## YYYY-MM-DD" heading sets the due date of the tasks under it; text after
// the date is ignored. Any other heading ends that day, so tasks under it, or
// above the first date heading, have no due date and are skipped. A trailing
// p1 to p3 is an optional priority.

const dateRe = /^##\s+(\d{4}-\d{2}-\d{2})(?:\s|$)/
const headingRe = /^#{1,6}(?:\s|$)/
const taskRe = /^- \[( |x|X)\]\s+(\S.*?)(?:\s+p([1-3]))?\s*$/

// text in, tasks out: { done, title, due, priority, line, raw }. `line` and
// `raw` address the task for edit() below.
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
        if (m)
            out.push({
                done: m[1] !== " ",
                title: m[2],
                due: due,
                priority: m[3] ? parseInt(m[3]) : 0,
                line: i,
                raw: lines[i]
            })
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
