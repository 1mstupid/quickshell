// Run: node test_notification_meta.js
// Loads NotificationMeta.js (stripping the QML-only .pragma line) and checks
// the toast and history bookkeeping on small inputs.
const fs = require("fs")
const path = require("path")
const assert = require("assert")

const src = fs.readFileSync(path.join(__dirname, "NotificationMeta.js"), "utf8")
    .replace(/^\.pragma library\s*$/m, "")
const M = new Function(src + "\nreturn { arrived, expired, isToast, timeOf };")()

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

test("a new notification is a toast with its time", () => {
    const m = M.arrived({}, [], 7, "14:32", false)
    assert.strictEqual(M.isToast(m, 7), true)
    assert.strictEqual(M.timeOf(m, 7), "14:32")
})

test("a muted arrival never shows as a toast", () => {
    const m = M.arrived({}, [], 7, "14:32", true)
    assert.strictEqual(M.isToast(m, 7), false)
    assert.strictEqual(M.timeOf(m, 7), "14:32")
})

test("expiring ends the toast and keeps the time", () => {
    const m = M.expired(M.arrived({}, [], 7, "14:32", false), 7)
    assert.strictEqual(M.isToast(m, 7), false)
    assert.strictEqual(M.timeOf(m, 7), "14:32")
})

test("expiring one toast leaves the others", () => {
    let m = M.arrived({}, [], 1, "10:00", false)
    m = M.arrived(m, [1], 2, "10:01", false)
    m = M.expired(m, 1)
    assert.strictEqual(M.isToast(m, 1), false)
    assert.strictEqual(M.isToast(m, 2), true)
})

test("expiring twice returns the same object, so nothing notifies", () => {
    const m = M.expired(M.arrived({}, [], 7, "14:32", false), 7)
    assert.strictEqual(M.expired(m, 7), m)
})

test("changes return a new object and leave the old one alone", () => {
    const a = M.arrived({}, [], 7, "14:32", false)
    const b = M.expired(a, 7)
    assert.notStrictEqual(a, b)
    assert.strictEqual(M.isToast(a, 7), true)
})

test("an arrival drops entries for dismissed notifications", () => {
    let m = M.arrived({}, [], 1, "10:00", false)
    m = M.arrived(m, [1], 2, "10:01", false)
    // 1 was dismissed, so only 2 is still kept when 3 arrives
    m = M.arrived(m, [2], 3, "10:02", false)
    assert.deepStrictEqual(Object.keys(m).sort(), ["2", "3"])
})

test("a repeated id (an updated notification) is a toast again", () => {
    let m = M.expired(M.arrived({}, [], 7, "14:32", false), 7)
    m = M.arrived(m, [7], 7, "14:40", false)
    assert.strictEqual(M.isToast(m, 7), true)
    assert.strictEqual(M.timeOf(m, 7), "14:40")
})

test("an unknown id is a toast with no time, and can still expire", () => {
    assert.strictEqual(M.isToast({}, 99), true)
    assert.strictEqual(M.timeOf({}, 99), "")
    const m = M.expired({}, 99)
    assert.strictEqual(M.isToast(m, 99), false)
    assert.strictEqual(M.timeOf(m, 99), "")
})

process.exitCode = failures ? 1 : 0
