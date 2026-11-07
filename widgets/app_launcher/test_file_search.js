// Run: node test_file_search.js
// Loads FileSearch.js (stripping the QML-only .pragma line) and checks how a
// typed line is read and how ls / fd output becomes rows.
const fs = require("fs")
const path = require("path")
const assert = require("assert")

const src = fs.readFileSync(path.join(__dirname, "FileSearch.js"), "utf8")
    .replace(/^\.pragma library\s*$/m, "")
const { tilde, parentOf, classify, parseLs, parseFd } =
    new Function(src + "\nreturn { tilde, parentOf, classify, parseLs, parseFd };")()

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

test("search: shallow first, folders with or without a trailing slash", () => {
    const rows = parseFd("/home/u/a/b/c.txt\n/home/u/c.txt\n/home/u/a/c/\n", H)
    assert.deepStrictEqual(rows.map(r => r.path), ["/home/u/c.txt", "/home/u/a/c", "/home/u/a/b/c.txt"])
    assert.deepStrictEqual(rows.map(r => r.dir), [false, true, false])
    assert.deepStrictEqual(rows.map(r => r.sub), ["~", "~/a", "~/a/b"])
    assert.strictEqual(rows[0].name, "c.txt")
    assert.strictEqual(rows[1].name, "c")
    assert.strictEqual(rows[1].next, "")
})

test("search: no output gives no rows", () => {
    assert.deepStrictEqual(parseFd("", H), [])
    assert.deepStrictEqual(parseFd("\n\n", H), [])
})

process.exitCode = failures ? 1 : 0
