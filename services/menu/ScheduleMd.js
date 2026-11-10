.pragma library

// Parsing and planning for schedule.md. No QML types and no side effects, so it
// can be tested with plain node.
//
// The schedule is a fixed clock of blocks plus a weekly grid of what goes in
// them: the times never move, only the subject inside a block changes with the
// day. The file is markdown with two pipe tables; headings other than Clock and
// Week, and any text outside the tables, are ignored.
//
//   ## Clock
//   | Time        | Block             | Kind       | Plan |
//   | ----------- | ----------------- | ---------- | ---- |
//   | 05:00-07:30 | Bloco 1           | Emergência |      |
//   | 07:30-07:45 | Pausa             | Recuperação |      |
//   | 10:15-12:15 | Academia + Cardio | Saúde      | yes  |
//   | 18:15       | Shutdown          |            |      |
//
//   ## Week
//   | Day | Bloco 1 | Bloco 2 |
//   | --- | ------- | ------- |
//   | Seg | Mat 1   | Fis 1   |
//   | Sáb | Mat 3   | -       |
//
// Clock rows: a range is a block, a single time is the end-of-day marker. A block
// named as a Week column is filled from that table; a block that is not gets a
// task of its own name only when its Plan cell is yes (sim, x, 1), so breaks stay
// breaks. In the Week table a "-" or an empty cell drops that block for the day
// (a compact Saturday), and a day with no row at all is a day off. Day names are
// matched on their first three letters, in Portuguese or English.

const DAY_KEYS = { dom: 0, sun: 0, seg: 1, mon: 1, ter: 2, tue: 2, qua: 3, wed: 3,
                   qui: 4, thu: 4, sex: 5, fri: 5, sab: 6, sat: 6 }

function pad(n) {
    return (n < 10 ? "0" : "") + n
}

// minutes since midnight as "HH:MM"
function fmtTime(min) {
    return pad(Math.floor(min / 60)) + ":" + pad(min % 60)
}

// "5:30" or "05:30" to minutes since midnight, or -1
function toMin(s) {
    const m = /^(\d{1,2}):([0-5]\d)$/.exec(s.trim())
    if (m === null || parseInt(m[1]) > 23)
        return -1
    return parseInt(m[1]) * 60 + parseInt(m[2])
}

// 0 = Sunday to 6 = Saturday, or -1 when the name is not a day
function dayIndex(name) {
    const k = name.trim().toLowerCase().replace(/[áàâã]/g, "a").slice(0, 3)
    return DAY_KEYS.hasOwnProperty(k) ? DAY_KEYS[k] : -1
}

function isYes(s) {
    return /^(y|yes|s|sim|x|true|1)$/i.test(s.trim())
}

// a Week cell that drops the block for the day
function isOff(s) {
    return s === "" || /^[-–—]+$/.test(s)
}

// the cells of a table row, or null when the line is not one
function cells(line) {
    const t = line.trim()
    if (t.charAt(0) !== "|")
        return null
    const parts = t.slice(1).split("|")
    if (parts[parts.length - 1].trim() === "")
        parts.pop()
    return parts.map(c => c.trim())
}

function isSeparator(cs) {
    return cs.length > 0 && cs.every(c => /^:?-{3,}:?$/.test(c))
}

function parseClockRow(cs, at, out) {
    const m = /^(\d{1,2}:\d{2})(?:\s*[-–—]\s*(\d{1,2}:\d{2}))?$/.exec(cs[0])
    if (m === null) {
        out.errors.push(at + "\"" + cs[0] + "\" is not a time or a time range")
        return
    }
    const start = toMin(m[1])
    const end = m[2] === undefined ? null : toMin(m[2])
    if (start < 0 || (m[2] !== undefined && end < 0)) {
        out.errors.push(at + "\"" + cs[0] + "\" is not a valid time")
        return
    }
    if (end !== null && end <= start) {
        out.errors.push(at + "\"" + cs[0] + "\" ends before it starts")
        return
    }
    const name = cs.length > 1 ? cs[1] : ""
    if (name === "") {
        out.errors.push(at + "the block at " + cs[0] + " has no name")
        return
    }
    out.clock.push({
        start: start,
        end: end,
        name: name,
        kind: cs.length > 2 ? cs[2] : "",
        plan: cs.length > 3 && isYes(cs[3])
    })
}

function parseWeekRow(cs, at, out) {
    if (!out.hasWeek) {
        out.errors.push(at + "the Week table needs a header row with the block names")
        return
    }
    const d = dayIndex(cs[0])
    if (d < 0) {
        out.errors.push(at + "\"" + cs[0] + "\" is not a day of the week")
        return
    }
    const row = {}
    for (let j = 0; j < out.cols.length; j++) {
        if (out.cols[j] === "")
            continue
        const v = j + 1 < cs.length ? cs[j + 1] : ""
        row[out.cols[j]] = isOff(v) ? "" : v
    }
    out.week[d] = row
}

// text in, schedule out:
//   { clock: [{ start, end, name, kind, plan }], cols, colNames, hasWeek,
//     week: { day: { "block name in lower case": subject } }, errors }
// `end` is null for the end-of-day marker, times are minutes since midnight and
// `errors` lists what could not be read, each with its line number.
function parse(text) {
    const out = { clock: [], cols: [], colNames: [], hasWeek: false, week: {}, errors: [] }
    const lines = text.split("\n").map(l => l.replace(/\r$/, ""))
    let section = ""
    for (let i = 0; i < lines.length; i++) {
        const h = /^#{1,6}\s+(.*?)\s*$/.exec(lines[i])
        if (h !== null) {
            const name = h[1].toLowerCase()
            section = name.indexOf("clock") === 0 ? "clock" : name.indexOf("week") === 0 ? "week" : ""
            continue
        }
        if (section === "")
            continue
        const cs = cells(lines[i])
        if (cs === null || isSeparator(cs))
            continue
        // a row followed by a separator is the table's header
        const next = i + 1 < lines.length ? cells(lines[i + 1]) : null
        if (next !== null && isSeparator(next)) {
            if (section === "week") {
                out.hasWeek = true
                out.colNames = cs.slice(1)
                out.cols = out.colNames.map(c => c.toLowerCase())
            }
            continue
        }
        const at = "line " + (i + 1) + ": "
        if (section === "clock")
            parseClockRow(cs, at, out)
        else
            parseWeekRow(cs, at, out)
    }
    // a Week column that names no block is most likely a typo
    if (out.clock.length > 0) {
        for (let j = 0; j < out.cols.length; j++) {
            const key = out.cols[j]
            if (key !== "" && !out.clock.some(c => c.end !== null && c.name.toLowerCase() === key))
                out.errors.push("Week column \"" + out.colNames[j] + "\" is not a block in the Clock")
        }
    }
    return out
}

// The day's rows, in clock order, for weekday `wd` (0 = Sunday):
//   { start, end, name, kind, subject, planned, marker }
// A block that is a Week column takes its subject from the day's row and is left
// out when that cell is off. A day with no row in a Week table that exists is a
// day off and has no rows. The end-of-day marker moves up to the end of the last
// planned block when the blocks after it were dropped.
function dayPlan(sch, wd) {
    const row = sch.week[wd]
    if (sch.hasWeek && row === undefined)
        return []
    const kept = []
    let marker = null
    const dropped = []
    for (const c of sch.clock) {
        if (c.end === null) {
            marker = c
            continue
        }
        const key = c.name.toLowerCase()
        const inWeek = sch.cols.indexOf(key) >= 0
        let subject = ""
        if (inWeek) {
            subject = row !== undefined && row[key] !== undefined ? row[key] : ""
            if (subject === "") {
                dropped.push(c)
                continue
            }
        } else if (c.plan) {
            subject = c.name
        }
        kept.push({ start: c.start, end: c.end, name: c.name, kind: c.kind,
                    subject: subject, planned: subject !== "", marker: false })
    }
    const planned = kept.filter(r => r.planned)
    if (planned.length === 0)
        return []
    if (marker !== null) {
        const lastEnd = Math.max.apply(null, planned.map(r => r.end))
        const cut = dropped.some(c => c.start >= lastEnd)
        kept.push({ start: cut ? lastEnd : marker.start, end: null, name: marker.name,
                    kind: marker.kind, subject: "", planned: false, marker: true })
    }
    return kept.sort((a, b) => a.start - b.start)
}

// the row of the plan that is on at `nowMin`, or null; the marker is never on
function blockAt(plan, nowMin) {
    for (const r of plan)
        if (!r.marker && r.start <= nowMin && nowMin < r.end)
            return r
    return null
}

// The day's planned blocks as tasks: { title, subject, block, kind, start, end,
// time, minutes }. Todo titles identify a task within a day, so a subject that
// comes up twice is told apart by its block name.
function slots(plan) {
    const rows = plan.filter(r => r.planned)
    const count = {}
    for (const r of rows)
        count["k" + r.subject] = (count["k" + r.subject] || 0) + 1
    return rows.map(r => ({
        title: count["k" + r.subject] > 1 ? r.subject + " (" + r.name + ")" : r.subject,
        subject: r.subject,
        block: r.name,
        kind: r.kind,
        start: r.start,
        end: r.end,
        time: fmtTime(r.start),
        minutes: r.end - r.start
    }))
}

// What is left to do, tasks and schedule together, in the order to do it.
// `upcoming` is TodoMd.upcoming() (open tasks due today or overdue), `items` the
// whole list. A slot shows as a row of its own only while no task for today
// carries its title, so one that has been started or ticked is not shown twice,
// and only until its block is over (`past` lists the titles of the ended ones).
// Rows: { kind: "task" | "slot", task, title, due, time, late, priority, start, end, block }.
// Overdue tasks come first; today's rows follow by hour, those without one last.
function agenda(upcoming, items, slotList, today, past) {
    const taken = {}
    for (const t of items)
        if (t.due === today)
            taken["k" + t.title] = true
    const over = {}
    for (const t of past)
        over["k" + t] = true
    const byTitle = {}
    for (const s of slotList)
        byTitle["k" + s.title] = s

    const rows = []
    for (const t of upcoming) {
        const s = t.due === today ? byTitle["k" + t.title] : undefined
        rows.push({ kind: "task", task: t, title: t.title, due: t.due, time: t.time,
                    late: t.due < today, priority: t.priority,
                    start: s ? s.start : -1, end: s ? s.end : -1, block: s ? s.block : "",
                    order: rows.length })
    }
    for (const s of slotList) {
        if (taken["k" + s.title] || over["k" + s.title])
            continue
        rows.push({ kind: "slot", task: null, title: s.title, due: today, time: s.time,
                    late: false, priority: 0, start: s.start, end: s.end, block: s.block,
                    order: rows.length })
    }
    return rows.sort((a, b) => {
        if (a.late !== b.late)
            return a.late ? -1 : 1
        if (a.late && a.due !== b.due)
            return a.due < b.due ? -1 : 1
        if (!a.late && a.time !== b.time) {
            if (a.time === "" || b.time === "")
                return a.time === "" ? 1 : -1
            return a.time < b.time ? -1 : 1
        }
        return a.order - b.order
    })
}

// The Week table laid out for showing: the blocks that are Week columns in clock
// order, and a row per day present, Monday first and Sunday last.
//   { cols: [{ name, start, end, time }], rows: [{ day, cells: [subject] }] }
function weekView(sch) {
    const cols = []
    for (const c of sch.clock)
        if (c.end !== null && sch.cols.indexOf(c.name.toLowerCase()) >= 0)
            cols.push({ name: c.name, start: c.start, end: c.end, time: fmtTime(c.start) })
    cols.sort((a, b) => a.start - b.start)
    const rows = []
    for (const d of [1, 2, 3, 4, 5, 6, 0]) {
        const r = sch.week[d]
        if (r === undefined)
            continue
        rows.push({ day: d, cells: cols.map(c => r[c.name.toLowerCase()] || "") })
    }
    return { cols: cols, rows: rows }
}

// The template shown, and written by Schedule.init(), while there is no
// schedule.md. It follows the example grid in the study-plan PDF: a clock that
// starts at 05:00 with two heavy blocks, the gym between them, and a day that
// ends at 18:15, and a Monday to Saturday grid with a compact Saturday.
function defaultText() {
    return [
        "# Schedule",
        "",
        "The clock never moves: the start and end of every block are fixed and only the",
        "subject inside changes with the day. Edit the tables below; the notch reads this",
        "file whenever it changes.",
        "",
        "Clock: a time range is a block, a single time is the end of the day. A block named",
        "as a column of the Week table takes its subject from there; any other block only",
        "becomes a task when its Plan cell says yes. Week: a - or an empty cell drops that",
        "block for the day, and a day with no row is a day off.",
        "",
        "## Clock",
        "",
        "| Time        | Block             | Kind        | Plan |",
        "| ----------- | ----------------- | ----------- | ---- |",
        "| 05:00-07:30 | Bloco 1           | Emergência  |      |",
        "| 07:30-07:45 | Pausa             | Recuperação |      |",
        "| 07:45-10:15 | Bloco 2           | Emergência  |      |",
        "| 10:15-12:15 | Academia + Cardio | Saúde       | yes  |",
        "| 12:15-14:15 | Bloco 3           | Atenção     |      |",
        "| 14:15-15:00 | Almoço            | Descanso    |      |",
        "| 15:00-16:30 | Bloco 4           | Manutenção  |      |",
        "| 16:30-17:30 | Bloco 5           | Manutenção  |      |",
        "| 17:30-18:15 | Bloco 6           | Secundária  |      |",
        "| 18:15       | Shutdown          |             |      |",
        "",
        "## Week",
        "",
        "| Day | Bloco 1 | Bloco 2 | Bloco 3 | Bloco 4    | Bloco 5 | Bloco 6 |",
        "| --- | ------- | ------- | ------- | ---------- | ------- | ------- |",
        "| Seg | Mat 1   | Fis 1   | Qui 1   | Gramática  | Mat 4   | Inglês  |",
        "| Ter | Mat 2   | Fis 2   | Qui 2   | Literatura | Fis 3   | Inglês  |",
        "| Qua | Mat 3   | Fis 4   | Qui 3   | Redação    | Mat 5   | Inglês  |",
        "| Qui | Mat 1   | Fis 1   | Qui 1   | Gramática  | Qui 3   | Inglês  |",
        "| Sex | Mat 2   | Fis 2   | Qui 2   | Literatura | Fis 4   | Inglês  |",
        "| Sáb | Mat 3   | Fis 3   | Qui 2   | Redação    | -       | -       |",
        ""
    ].join("\n")
}
