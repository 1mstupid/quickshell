// Run: node test_modes.js
// Loads Modes.js (stripping the QML-only .pragma line) and checks the bang
// parsing and the reading of qalc output.
const fs = require("fs")
const path = require("path")
const assert = require("assert")

const src = fs.readFileSync(path.join(__dirname, "Modes.js"), "utf8")
    .replace(/^\.pragma library\s*$/m, "")
const { parse, hints, answer, find } = new Function(src + "\nreturn { parse, hints, answer, find };")()

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

test("a bang and a space enters the mode, the rest is the text", () => {
    assert.deepStrictEqual(parse("!calc 2+2"), { mode: "calc", text: "2+2" })
    assert.deepStrictEqual(parse("!CALC 5 km to mi"), { mode: "calc", text: "5 km to mi" })
    assert.deepStrictEqual(parse("!calc "), { mode: "calc", text: "" })
})

test("no space yet, an unknown bang, or no bang: plain text", () => {
    for (const t of ["!calc", "!nope 1", "calc 1", "", "firefox", " !calc 1"])
        assert.deepStrictEqual(parse(t), { mode: "", text: t })
})

test("the text after the bang keeps its own spaces and bangs", () => {
    assert.deepStrictEqual(parse("!calc  3 ! "), { mode: "calc", text: " 3 ! " })
})

test("hints complete a half-typed bang", () => {
    assert.deepStrictEqual(hints("!").map(m => m.name), ["calc"])
    assert.deepStrictEqual(hints("!ca").map(m => m.name), ["calc"])
    assert.deepStrictEqual(hints("!calc").map(m => m.name), ["calc"])
    assert.deepStrictEqual(hints("!x"), [])
    assert.deepStrictEqual(hints("!calc 1"), [])
    assert.deepStrictEqual(hints("calc"), [])
    assert.deepStrictEqual(hints(""), [])
})

test("find returns the mode or null", () => {
    assert.strictEqual(find("calc").name, "calc")
    assert.strictEqual(find("x"), null)
})

test("answer takes the result line", () => {
    assert.strictEqual(answer("4\n", "2+2"), "4")
    assert.strictEqual(answer("  0.3333333333 \n\n", "1/3"), "0.3333333333")
})

test("answer skips warnings, rejects errors, empty output and echoes", () => {
    assert.strictEqual(answer("warning: something\n12\n", "3*4"), "12")
    assert.strictEqual(answer("error: Unknown\n", "3*"), "")
    assert.strictEqual(answer("", "x"), "")
    assert.strictEqual(answer("\n  \n", "x"), "")
    assert.strictEqual(answer("warning: only\n", "x"), "")
    assert.strictEqual(answer("Hello\n", " hello "), "")
})

process.exitCode = failures ? 1 : 0
