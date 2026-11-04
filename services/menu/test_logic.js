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

const Todo = load("TodoMd.js", "parse, toggled, edit")
const Month = load("MonthGrid.js", "grid")

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

process.exitCode = failures ? 1 : 0
