// Run: node test_logic.js
// Loads TodoMd.js and MonthGrid.js (stripping the QML-only .pragma line) and
// checks them on small inputs.
const fs = require("fs")
const path = require("path")
const assert = require("assert")

function load(name, exports) {
    const src = fs.readFileSync(path.join(__dirname, name), "utf8")
        .replace(/^\.pragma library\s*$/m, "")
    return new Function(src + "\nreturn { " + exports + " };")()
}

const Todo = load("TodoMd.js", "parse, toggled, edit, upcoming, withSpent, fmtSpent, add")
const Month = load("MonthGrid.js", "grid")
const Sched = load("ScheduleMd.js", "parse, dayPlan, blockAt, slots, agenda, weekView, defaultText, dayIndex, fmtTime")

let failures = 0
function test(name, fn) {
    try {
        fn()
        console.log("ok   ", name)
    } catch (e) {
        failures++
        console.log("FAIL ", name, "\n     ", e.message)
    }
}

const sample = [
    "# Todo",
    "- [ ] before any date, skipped",
    "",
    "## 2026-11-04 Wednesday",
    "- [ ] Send the weekly update",
    "- [x] Pick up groceries  p1",
    "- [ ]   Extra spaces p3",
    "- [ ] ",
    "just a note",
    "",
    "## Notes",
    "- [ ] under a non-date heading, skipped",
    "",
    "## 2026-11-05",
    "- [ ] Send the weekly update",
    "- [ ] Buy p1 router",
    ""
].join("\n")

test("parse reads tasks, dates and priorities", () => {
    const t = Todo.parse(sample)
    assert.deepStrictEqual(t.map(x => [x.due, x.title, x.done, x.priority]), [
        ["2026-11-04", "Send the weekly update", false, 0],
        ["2026-11-04", "Pick up groceries", true, 1],
        ["2026-11-04", "Extra spaces", false, 3],
        ["2026-11-05", "Send the weekly update", false, 0],
        ["2026-11-05", "Buy p1 router", false, 0]
    ])
})

test("parse of empty text is empty", () => {
    assert.deepStrictEqual(Todo.parse(""), [])
})

test("parse keeps CRLF files working", () => {
    const t = Todo.parse("## 2026-11-04\r\n- [ ] One\r\n- [x] Two p2\r\n")
    assert.deepStrictEqual(t.map(x => [x.title, x.done, x.priority]), [["One", false, 0], ["Two", true, 2]])
})

test("toggled flips the box and nothing else", () => {
    assert.strictEqual(Todo.toggled("- [ ] A  p1"), "- [x] A  p1")
    assert.strictEqual(Todo.toggled("- [x] A"), "- [ ] A")
    assert.strictEqual(Todo.toggled("- [X] A"), "- [ ] A")
    assert.strictEqual(Todo.toggled("- [ ] A\r"), "- [x] A\r")
})

test("edit hits the task by position, even when identical tasks repeat", () => {
    const t = Todo.parse(sample)
    const second = t[3]
    const next = Todo.edit(sample, second.line, second.raw, Todo.toggled(second.raw))
    const after = Todo.parse(next)
    assert.strictEqual(after[0].done, false)
    assert.strictEqual(after[3].done, true)
    assert.strictEqual(next.split("\n").length, sample.split("\n").length)
})

test("edit with null removes the line", () => {
    const t = Todo.parse(sample)
    const next = Todo.edit(sample, t[1].line, t[1].raw, null)
    assert.strictEqual(next.indexOf("Pick up groceries"), -1)
    assert.strictEqual(Todo.parse(next).length, t.length - 1)
})

test("edit refuses a stale line", () => {
    const t = Todo.parse(sample)
    const moved = "added at the top\n" + sample
    assert.strictEqual(Todo.edit(moved, t[0].line, t[0].raw, "x"), null)
    assert.strictEqual(Todo.edit(sample, 999, "nope", "x"), null)
})

test("edit keeps a missing trailing newline missing", () => {
    const text = "## 2026-11-04\n- [ ] A"
    const t = Todo.parse(text)
    assert.strictEqual(Todo.edit(text, t[0].line, t[0].raw, Todo.toggled(t[0].raw)), "## 2026-11-04\n- [x] A")
})

test("grid: June 2025 matches the reference (starts 26 May, ends 6 July, 6 rows)", () => {
    const g = Month.grid("2025-06-15")
    assert.strictEqual(g.length, 42)
    assert.strictEqual(g[0].date, "2025-05-26")
    assert.strictEqual(g[0].inMonth, false)
    assert.strictEqual(g[6].date, "2025-06-01")
    assert.strictEqual(g[6].inMonth, true)
    assert.strictEqual(g[35].date, "2025-06-30")
    assert.strictEqual(g[41].date, "2025-07-06")
})

test("grid: November 2026 starts on Monday 26 October", () => {
    const g = Month.grid("2026-11-04")
    assert.strictEqual(g.length, 42)
    assert.strictEqual(g[0].date, "2026-10-26")
    assert.strictEqual(g.filter(c => c.inMonth).length, 30)
})

test("grid: February 2027 is exactly four rows", () => {
    const g = Month.grid("2027-02-10")
    assert.strictEqual(g.length, 28)
    assert.strictEqual(g[0].date, "2027-02-01")
    assert.strictEqual(g.every(c => c.inMonth), true)
})

test("grid: year boundaries and leap day", () => {
    const dec = Month.grid("2026-12-31")
    assert.strictEqual(dec[dec.length - 1].date, "2027-01-03")
    const feb = Month.grid("2028-02-29")
    assert.strictEqual(feb.filter(c => c.inMonth).length, 29)
})

test("grid: every row is seven days and days run one after another", () => {
    for (const day of ["2026-01-01", "2026-03-31", "2026-05-15", "2026-08-01", "2026-10-31"]) {
        const g = Month.grid(day)
        assert.strictEqual(g.length % 7, 0)
        for (let i = 1; i < g.length; i++) {
            const a = new Date(g[i - 1].date + "T12:00:00Z").getTime()
            const b = new Date(g[i].date + "T12:00:00Z").getTime()
            assert.strictEqual(b - a, 86400000)
        }
    }
})

test("grid of an empty day is empty", () => {
    assert.deepStrictEqual(Month.grid(""), [])
})

test("upcoming: overdue first, then priority, then file order; done and future are left out", () => {
    const text = [
        "## 2026-11-06",
        "- [ ] late, no priority",
        "## 2026-11-05",
        "- [ ] later still overdue earlier day p3",
        "## 2026-11-08",
        "- [ ] today plain",
        "- [ ] today p2  p2",
        "- [x] today done  p1",
        "- [ ] today p1  p1",
        "## 2026-11-09",
        "- [ ] tomorrow, not yet"
    ].join("\n")
    const titles = Todo.upcoming(Todo.parse(text), "2026-11-08").map(t => t.title)
    assert.deepStrictEqual(titles, [
        "later still overdue earlier day",
        "late, no priority",
        "today p1",
        "today p2",
        "today plain"
    ])
})

test("upcoming of nothing is empty", () => {
    assert.deepStrictEqual(Todo.upcoming([], "2026-11-08"), [])
})

test("parse reads the hour and the time spent, in any order", () => {
    const t = Todo.parse([
        "## 2026-11-08",
        "- [ ] Call mom @16:30",
        "- [ ] Report @9:05 p2 ~1h05m",
        "- [ ] Gym ~45m p1 @17:53",
        "- [ ] Mail me@home.org",
        "- [ ] Odd @25:00",
        "- [ ] Twice @10:00 @11:00",
        "- [ ] Only tilde ~",
        ""
    ].join("\n"))
    assert.deepStrictEqual(t.map(x => [x.title, x.time, x.priority, x.spent]), [
        ["Call mom", "16:30", 0, 0],
        ["Report", "09:05", 2, 65],
        ["Gym", "17:53", 1, 45],
        ["Mail me@home.org", "", 0, 0],
        ["Odd @25:00", "", 0, 0],
        ["Twice @10:00", "11:00", 0, 0],
        ["Only tilde ~", "", 0, 0]
    ])
})

test("withSpent replaces the token where it stands or adds one", () => {
    assert.strictEqual(Todo.withSpent("- [ ] A @15:00", 5), "- [ ] A @15:00 ~5m")
    assert.strictEqual(Todo.withSpent("- [ ] A ~10m @15:00 p1", 70), "- [ ] A ~1h10m @15:00 p1")
    assert.strictEqual(Todo.withSpent("- [ ] A @15:00 ~1h05m", 125), "- [ ] A @15:00 ~2h05m")
    assert.strictEqual(Todo.withSpent("- [ ] A\r", 3), "- [ ] A ~3m\r")
    assert.strictEqual(Todo.withSpent("- [x] A", 60), "- [x] A ~1h00m")
})

test("withSpent round-trips through parse", () => {
    const raw = "- [ ] Write the report @15:00 p2"
    const text = "## 2026-11-08\n" + raw
    const item = Todo.parse(text)[0]
    const next = Todo.parse("## 2026-11-08\n" + Todo.withSpent(item.raw, 42))[0]
    assert.deepStrictEqual([next.title, next.time, next.priority, next.spent], ["Write the report", "15:00", 2, 42])
})

test("upcoming: timed tasks come first within a day, earliest first", () => {
    const text = [
        "## 2026-11-07",
        "- [ ] late untimed p1  p1",
        "- [ ] late timed @08:00",
        "## 2026-11-08",
        "- [ ] today untimed p1  p1",
        "- [ ] today evening @21:00",
        "- [ ] today morning @09:30",
        "- [ ] today untimed"
    ].join("\n")
    assert.deepStrictEqual(Todo.upcoming(Todo.parse(text), "2026-11-08").map(t => t.title), [
        "late timed",
        "late untimed p1",
        "today morning",
        "today evening",
        "today untimed p1",
        "today untimed"
    ])
})

test("add puts lines after the day's last task and keeps blank lines between days", () => {
    const text = "## 2026-11-08\n- [ ] A\n- [x] B\n\n## 2026-11-09\n- [ ] C\n"
    const next = Todo.add(text, "2026-11-08", ["- [ ] New @09:00"])
    assert.strictEqual(next, "## 2026-11-08\n- [ ] A\n- [x] B\n- [ ] New @09:00\n\n## 2026-11-09\n- [ ] C\n")
    const t = Todo.parse(next)
    assert.deepStrictEqual(t.map(x => [x.due, x.title, x.time]), [
        ["2026-11-08", "A", ""], ["2026-11-08", "B", ""], ["2026-11-08", "New", "09:00"], ["2026-11-09", "C", ""]
    ])
})

test("add to the last day, and to a day that has no heading yet", () => {
    const text = "## 2026-11-08\n- [ ] A\n"
    assert.strictEqual(Todo.add(text, "2026-11-08", ["- [ ] B"]), "## 2026-11-08\n- [ ] A\n- [ ] B\n")
    assert.strictEqual(Todo.add(text, "2026-11-10", ["- [ ] B", "- [ ] C"]),
        "## 2026-11-08\n- [ ] A\n\n## 2026-11-10\n- [ ] B\n- [ ] C\n")
})

test("add to an empty or missing file, and under a heading that carries a weekday", () => {
    assert.strictEqual(Todo.add("", "2026-11-08", ["- [ ] A"]), "## 2026-11-08\n- [ ] A\n")
    const next = Todo.add("## 2026-11-08 Sunday\n- [ ] A\n## Notes\nsome text\n", "2026-11-08", ["- [ ] B"])
    assert.strictEqual(next, "## 2026-11-08 Sunday\n- [ ] A\n- [ ] B\n## Notes\nsome text\n")
})

test("add keeps CRLF files CRLF", () => {
    const next = Todo.add("## 2026-11-08\r\n- [ ] A\r\n", "2026-11-09", ["- [ ] B"])
    assert.strictEqual(next, "## 2026-11-08\r\n- [ ] A\r\n\r\n## 2026-11-09\r\n- [ ] B\r\n")
    assert.strictEqual(Todo.parse(next).length, 2)
})

// ── schedule.md ─────────────────────────────────────────────────────────────

const day = n => ["dom", "seg", "ter", "qua", "qui", "sex", "sab"].indexOf(n)
const defaults = () => Sched.parse(Sched.defaultText())

test("schedule: the built-in template reads without errors", () => {
    const sch = defaults()
    assert.deepStrictEqual(sch.errors, [])
    assert.strictEqual(sch.clock.length, 10)
    assert.deepStrictEqual(sch.clock[0], { start: 300, end: 450, name: "Bloco 1", kind: "Emergência", plan: false })
    assert.strictEqual(sch.clock[3].plan, true)
    assert.strictEqual(sch.clock[9].end, null)
    assert.strictEqual(sch.clock[9].start, 18 * 60 + 15)
    assert.deepStrictEqual(sch.colNames, ["Bloco 1", "Bloco 2", "Bloco 3", "Bloco 4", "Bloco 5", "Bloco 6"])
    assert.strictEqual(sch.week[1]["bloco 1"], "Mat 1")
    assert.strictEqual(sch.week[6]["bloco 5"], "")
})

test("schedule: day names in Portuguese or English, with or without accents", () => {
    assert.deepStrictEqual(["Seg", "terça", "QUA", "qui", "Sex", "Sáb", "sábado", "Dom", "Mon", "sun", "x", ""].map(Sched.dayIndex),
        [1, 2, 3, 4, 5, 6, 6, 0, 1, 0, -1, -1])
})

test("schedule: a weekday gets its subjects, the gym, the breaks and the marker, in clock order", () => {
    const plan = Sched.dayPlan(defaults(), day("seg"))
    assert.deepStrictEqual(plan.map(r => [Sched.fmtTime(r.start), r.name, r.subject, r.planned, r.marker]), [
        ["05:00", "Bloco 1", "Mat 1", true, false],
        ["07:30", "Pausa", "", false, false],
        ["07:45", "Bloco 2", "Fis 1", true, false],
        ["10:15", "Academia + Cardio", "Academia + Cardio", true, false],
        ["12:15", "Bloco 3", "Qui 1", true, false],
        ["14:15", "Almoço", "", false, false],
        ["15:00", "Bloco 4", "Gramática", true, false],
        ["16:30", "Bloco 5", "Mat 4", true, false],
        ["17:30", "Bloco 6", "Inglês", true, false],
        ["18:15", "Shutdown", "", false, true]
    ])
})

test("schedule: a compact Saturday drops the blocks and the end of the day moves up", () => {
    const plan = Sched.dayPlan(defaults(), day("sab"))
    assert.deepStrictEqual(plan.filter(r => r.planned).map(r => r.subject),
        ["Mat 3", "Fis 3", "Academia + Cardio", "Qui 2", "Redação"])
    const end = plan[plan.length - 1]
    assert.strictEqual(end.marker, true)
    assert.strictEqual(Sched.fmtTime(end.start), "16:30")
})

test("schedule: a day without a row is a day off, but no Week table means the clock every day", () => {
    assert.deepStrictEqual(Sched.dayPlan(defaults(), day("dom")), [])
    const clockOnly = Sched.parse("## Clock\n| Time | Block | Kind | Plan |\n| --- | --- | --- | --- |\n| 09:00-10:00 | Read | | yes |\n| 10:00-10:15 | Rest | | |\n")
    assert.deepStrictEqual(Sched.dayPlan(clockOnly, 0).map(r => [r.name, r.planned]), [["Read", true], ["Rest", false]])
})

test("schedule: blockAt finds the block that is on, never the marker", () => {
    const plan = Sched.dayPlan(defaults(), day("seg"))
    assert.strictEqual(Sched.blockAt(plan, 5 * 60).name, "Bloco 1")
    assert.strictEqual(Sched.blockAt(plan, 7 * 60 + 30).name, "Pausa")
    assert.strictEqual(Sched.blockAt(plan, 7 * 60 + 29).name, "Bloco 1")
    assert.strictEqual(Sched.blockAt(plan, 4 * 60), null)
    assert.strictEqual(Sched.blockAt(plan, 18 * 60 + 15), null)
})

test("schedule: slots are the planned blocks as tasks, repeated subjects told apart by block", () => {
    const sl = Sched.slots(Sched.dayPlan(defaults(), day("ter")))
    assert.deepStrictEqual(sl.map(s => [s.title, s.time, s.minutes]), [
        ["Mat 2", "05:00", 150], ["Fis 2", "07:45", 150], ["Academia + Cardio", "10:15", 120],
        ["Qui 2", "12:15", 120], ["Literatura", "15:00", 90], ["Fis 3", "16:30", 60], ["Inglês", "17:30", 45]
    ])
    const twice = Sched.parse("## Clock\n| T | B | K | P |\n|---|---|---|---|\n| 08:00-09:00 | A | | |\n| 09:00-10:00 | B | | |\n## Week\n| D | A | B |\n|---|---|---|\n| Mon | Read | Read |\n")
    assert.deepStrictEqual(Sched.slots(Sched.dayPlan(twice, 1)).map(s => s.title), ["Read (A)", "Read (B)"])
})

test("schedule: mistakes are reported with their line, and the rest still reads", () => {
    const sch = Sched.parse([
        "## Clock",
        "| Time | Block | Kind | Plan |",
        "| --- | --- | --- | --- |",
        "| 9am-10am | Bad | | |",
        "| 10:00-09:00 | Backwards | | |",
        "| 25:00-26:00 | Late | | |",
        "| 11:00-12:00 | | | |",
        "| 12:00-13:00 | Good | | |",
        "## Week",
        "| Day | Good | Typo |",
        "| --- | --- | --- |",
        "| Funday | a | b |",
        "| Mon | a | b |"
    ].join("\n"))
    assert.deepStrictEqual(sch.clock.map(c => c.name), ["Good"])
    assert.strictEqual(sch.errors.length, 6)
    assert.deepStrictEqual(sch.errors.slice(0, 5).map(e => e.split(":")[0]), ["line 4", "line 5", "line 6", "line 7", "line 12"])
    assert.ok(sch.errors[5].indexOf("Typo") >= 0)
})

test("schedule: empty text and CRLF files", () => {
    const empty = Sched.parse("")
    assert.deepStrictEqual([empty.clock.length, empty.errors.length, empty.hasWeek], [0, 0, false])
    assert.deepStrictEqual(Sched.dayPlan(empty, 1), [])
    const crlf = Sched.parse(Sched.defaultText().replace(/\n/g, "\r\n"))
    assert.deepStrictEqual(crlf.errors, [])
    assert.strictEqual(crlf.week[3]["bloco 4"], "Redação")
})

test("schedule: weekView has the columns in clock order and Monday first, Sunday last", () => {
    const text = Sched.defaultText().replace("| Sáb |", "| Dom |")
    const v = Sched.weekView(Sched.parse(text))
    assert.deepStrictEqual(v.cols.map(c => [c.name, c.time]),
        [["Bloco 1", "05:00"], ["Bloco 2", "07:45"], ["Bloco 3", "12:15"], ["Bloco 4", "15:00"], ["Bloco 5", "16:30"], ["Bloco 6", "17:30"]])
    assert.deepStrictEqual(v.rows.map(r => r.day), [1, 2, 3, 4, 5, 0])
    assert.deepStrictEqual(v.rows[0].cells, ["Mat 1", "Fis 1", "Qui 1", "Gramática", "Mat 4", "Inglês"])
})

// ── the day's list: tasks and slots together ────────────────────────────────

const todo = lines => Todo.parse(lines.join("\n"))
const slotsMon = () => Sched.slots(Sched.dayPlan(defaults(), day("seg")))

test("agenda: slots with no task show up, in time order among today's tasks, overdue first", () => {
    const items = todo([
        "## 2026-11-07", "- [ ] Old thing",
        "## 2026-11-09", "- [ ] Call mom @16:00", "- [ ] Untimed"
    ])
    const rows = Sched.agenda(Todo.upcoming(items, "2026-11-09"), items, slotsMon(), "2026-11-09", [])
    assert.deepStrictEqual(rows.map(r => [r.kind, r.title, r.time]), [
        ["task", "Old thing", ""],
        ["slot", "Mat 1", "05:00"], ["slot", "Fis 1", "07:45"], ["slot", "Academia + Cardio", "10:15"],
        ["slot", "Qui 1", "12:15"], ["slot", "Gramática", "15:00"],
        ["task", "Call mom", "16:00"],
        ["slot", "Mat 4", "16:30"], ["slot", "Inglês", "17:30"],
        ["task", "Untimed", ""]
    ])
    assert.strictEqual(rows[0].late, true)
})

test("agenda: a slot that became a task, or was ticked, is not shown twice; ended slots are left out", () => {
    const items = todo(["## 2026-11-09", "- [ ] Mat 1 @05:00", "- [x] Fis 1 @07:45 ~2h30m"])
    const rows = Sched.agenda(Todo.upcoming(items, "2026-11-09"), items, slotsMon(), "2026-11-09", ["Academia + Cardio"])
    assert.deepStrictEqual(rows.map(r => [r.kind, r.title]), [
        ["task", "Mat 1"], ["slot", "Qui 1"], ["slot", "Gramática"], ["slot", "Mat 4"], ["slot", "Inglês"]
    ])
    // the task for a block carries the block's hours, so the list can show it is on now
    assert.deepStrictEqual([rows[0].start, rows[0].end, rows[0].block], [300, 450, "Bloco 1"])
})

test("agenda: tomorrow's tasks and other days' slots never leak in; without a schedule it is the todo list", () => {
    const items = todo(["## 2026-11-09", "- [ ] A p2", "## 2026-11-10", "- [ ] Tomorrow"])
    const rows = Sched.agenda(Todo.upcoming(items, "2026-11-09"), items, [], "2026-11-09", [])
    assert.deepStrictEqual(rows.map(r => r.title), ["A"])
})

process.exitCode = failures ? 1 : 0
