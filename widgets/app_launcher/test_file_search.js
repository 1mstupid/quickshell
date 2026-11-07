// Run: node test_file_search.js
// Loads FileSearch.js (stripping the QML-only .pragma line) and checks how a
// typed line is read and how ls / fd output becomes rows.
const fs = require("fs")
const path = require("path")
const assert = require("assert")

const src = fs.readFileSync(path.join(__dirname, "FileSearch.js"), "utf8")
    .replace(/^\.pragma library\s*$/m, "")
const { tilde, parentOf, classify, parseLs, prepare, fuzzy } =
    new Function(src + "\nreturn { tilde, parentOf, classify, parseLs, prepare, fuzzy };")()

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

const H = "/home/u"

test("a line starting with / or ~ browses, anything else searches", () => {
    assert.deepStrictEqual(classify("/etc/ng", H), { kind: "browse", dir: "/etc/", frag: "ng" })
    assert.deepStrictEqual(classify("/", H), { kind: "browse", dir: "/", frag: "" })
    assert.deepStrictEqual(classify("~", H), { kind: "browse", dir: "/home/u/", frag: "" })
    assert.deepStrictEqual(classify("~/Doc", H), { kind: "browse", dir: "/home/u/", frag: "Doc" })
    assert.deepStrictEqual(classify("~/a/b/", H), { kind: "browse", dir: "/home/u/a/b/", frag: "" })
    assert.deepStrictEqual(classify("report pdf", H), { kind: "search", pattern: "report pdf" })
    assert.deepStrictEqual(classify("~notes", H), { kind: "search", pattern: "~notes" })
    assert.deepStrictEqual(classify("  ", H), { kind: "none" })
})

test("tilde and parentOf", () => {
    assert.strictEqual(tilde("/home/u", H), "~")
    assert.strictEqual(tilde("/home/u/a/b", H), "~/a/b")
    assert.strictEqual(tilde("/home/user2/a", H), "/home/user2/a")
    assert.strictEqual(tilde("/etc", ""), "/etc")
    assert.strictEqual(parentOf("/home/u/a"), "/home/u")
    assert.strictEqual(parentOf("/a"), "/")
})

test("browse: folders first, hidden hidden, filtered by what is typed", () => {
    const out = "zeta.txt\nDocs/\n.config/\nalpha/\nnotes.md\n"
    assert.deepStrictEqual(parseLs(out, "/home/u/", "", H).map(e => e.name),
        ["alpha", "Docs", "notes.md", "zeta.txt"])
    assert.deepStrictEqual(parseLs(out, "/home/u/", "DOC", H).map(e => e.name), ["Docs"])
    assert.deepStrictEqual(parseLs(out, "/home/u/", ".c", H).map(e => e.name), [".config"])
})

test("browse rows: a folder opens into the line, a file does not", () => {
    const [d, f] = parseLs("Docs/\na.txt\n", "/home/u/", "", H)
    assert.strictEqual(d.path, "/home/u/Docs")
    assert.strictEqual(d.next, "~/Docs/")
    assert.strictEqual(d.dir, true)
    assert.strictEqual(f.next, "")
    assert.strictEqual(f.dir, false)
    assert.notStrictEqual(d.glyph, f.glyph)
    assert.strictEqual(parseLs("etc/\n", "/", "", H)[0].next, "/etc/")
})

test("browse: empty output, or a name that is only a slash, gives no rows", () => {
    assert.deepStrictEqual(parseLs("", "/x/", "", H), [])
    assert.deepStrictEqual(parseLs("/\n", "/x/", "", H), [])
})

const items = prepare([
    "/home/u/notes/todo.txt", "/home/u/todo/archive.md", "/home/u/proj/README.md",
    "/home/u/proj/src/", "/home/u/r/d/m/e", "/home/u/Music/Main.c", "/home/u/my_a_i_n.c",
    "/etc/hosts", ""
].join("\n"), H)

test("prepare: folders lose the slash, paths are lower-cased under home", () => {
    assert.strictEqual(items.length, 8)
    const d = items.find(i => i.path === "/home/u/proj/src")
    assert.strictEqual(d.dir, true)
    assert.strictEqual(items[0].low, "notes/todo.txt")
    assert.strictEqual(items.find(i => i.path === "/etc/hosts").low, "/etc/hosts")
    assert.deepStrictEqual(prepare("", H), [])
    assert.deepStrictEqual(prepare("\n\n", H), [])
})

test("fuzzy: letters in order match, others do not", () => {
    const r = fuzzy(items, "rdme", 50, H)
    assert.ok(r.top.some(e => e.name === "README.md"))
    assert.ok(!r.top.some(e => e.name === "hosts"))
    assert.strictEqual(fuzzy(items, "zzz", 50, H).top.length, 0)
})

test("fuzzy: a file-name match beats a folder-only match", () => {
    const r = fuzzy(items, "todo", 50, H)
    assert.strictEqual(r.top[0].path, "/home/u/notes/todo.txt")
})

test("fuzzy: the whole piece beats scattered letters, case does not matter", () => {
    const r = fuzzy(items, "MAIN", 50, H)
    assert.strictEqual(r.top[0].name, "Main.c")
    assert.strictEqual(r.top[1].name, "my_a_i_n.c")
})

test("fuzzy: rows carry the folder, the glyph and no next", () => {
    const [e] = fuzzy(items, "archive", 50, H).top
    assert.strictEqual(e.sub, "~/todo")
    assert.strictEqual(e.next, "")
    const d = fuzzy(items, "src", 50, H).top[0]
    assert.strictEqual(d.dir, true)
    assert.notStrictEqual(d.glyph, e.glyph)
})

test("fuzzy: spaces are ignored, an empty query has no rows, limit applies", () => {
    assert.deepStrictEqual(fuzzy(items, "to do", 50, H).top.map(e => e.path),
        fuzzy(items, "todo", 50, H).top.map(e => e.path))
    const r = fuzzy(items, "  ", 50, H)
    assert.deepStrictEqual(r, { pool: [], top: [] })
    assert.strictEqual(fuzzy(items, "e", 2, H).top.length, 2)
})

test("fuzzy: searching the pool of a shorter query gives the same rows", () => {
    const short = fuzzy(items, "re", 50, H)
    const viaPool = fuzzy(short.pool, "rea", 50, H)
    const whole = fuzzy(items, "rea", 50, H)
    assert.deepStrictEqual(viaPool.top, whole.top)
})

process.exitCode = failures ? 1 : 0
