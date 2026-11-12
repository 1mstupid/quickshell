// Run: node test_fuzzy.js
// Loads Fuzzy.js (stripping the QML-only .pragma line) and checks the matching
// and the ranking on a few wallpaper names.
const fs = require("fs")
const path = require("path")
const assert = require("assert")

const src = fs.readFileSync(path.join(__dirname, "Fuzzy.js"), "utf8")
    .replace(/^\.pragma library\s*$/m, "")
const { score, rank } = new Function(src + "\nreturn { score, rank };")()

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

const names = ["mountain-city", "city-lights", "forest", "Night City Rain", "mountain", "a-city-by-the-sea"]
const rankNames = q => rank(names, q, n => n)

test("letters in order match, letters out of order do not", () => {
    assert.ok(score("mountain-city", "mtncty") >= 0)
    assert.strictEqual(score("mountain-city", "ytc"), -1)
    assert.strictEqual(score("forest", "x"), -1)
})

test("case and spaces in the query do not matter", () => {
    assert.ok(score("Night City Rain", "NIGHT city") >= 0)
    assert.ok(score("night_city", "night c") >= 0)
})

test("an empty query keeps everything, in order, as a copy", () => {
    const out = rankNames("")
    assert.deepStrictEqual(out, names)
    assert.notStrictEqual(out, names)
    assert.deepStrictEqual(rankNames("   "), names)
})

test("only matches are kept", () => {
    assert.deepStrictEqual(rankNames("forest"), ["forest"])
    assert.deepStrictEqual(rankNames("zzz"), [])
})

test("a name that starts with the query beats one that has it later", () => {
    const out = rankNames("city")
    assert.strictEqual(out[0], "city-lights")
    assert.strictEqual(out.length, 4)
})

test("a substring beats scattered letters", () => {
    const out = rank(["c-i-t-y", "the city"], "city", n => n)
    assert.deepStrictEqual(out, ["the city", "c-i-t-y"])
})

test("a word start beats the middle of a word", () => {
    const out = rank(["scarlet", "red-cat"], "ca", n => n)
    assert.strictEqual(out[0], "red-cat")
})

test("equal scores keep their original order", () => {
    assert.deepStrictEqual(rank(["b1", "a1"], "1", n => n), ["b1", "a1"])
})

test("items can be paths, matched by a name function", () => {
    const paths = ["/w/one.png", "/w/two.png"]
    const out = rank(paths, "tw", p => p.split("/").pop().replace(/\.[^.]+$/, ""))
    assert.deepStrictEqual(out, ["/w/two.png"])
})

process.exit(failures ? 1 : 0)
