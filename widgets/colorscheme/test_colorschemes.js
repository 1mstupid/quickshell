// node widgets/colorscheme/test_colorschemes.js
const fs = require("fs")
const assert = require("assert")
const src = fs.readFileSync(__dirname + "/Colorschemes.js", "utf8").replace(/^\.pragma library\n/, "")
const M = new Function(src + "; return { SCHEMES, indexOfId }")()

const hex = /^#[0-9a-f]{6}$/
const lum = h => {
    const c = [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16) / 255)
        .map(v => v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4))
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
}
const contrast = (a, b) => (Math.max(lum(a), lum(b)) + 0.05) / (Math.min(lum(a), lum(b)) + 0.05)

let n = 0
const ok = (name, fn) => { fn(); n++; console.log("ok   " + name) }

ok("ids are unique and there is a wallpaper entry", () => {
    const ids = M.SCHEMES.map(s => s.id)
    assert.strictEqual(new Set(ids).size, ids.length)
    assert.ok(ids.includes("wallpaper"))
})
ok("presets have 8 palette and 16 ansi colours, all #rrggbb", () => {
    for (const s of M.SCHEMES) {
        if (s.id === "wallpaper") { assert.strictEqual(s.palette, undefined); continue }
        assert.strictEqual(s.palette.length, 8, s.id)
        assert.strictEqual(s.ansi.length, 16, s.id)
        for (const c of s.palette.concat(s.ansi))
            assert.ok(hex.test(c), s.id + " " + c)
    }
})
ok("text and accent are readable on the background", () => {
    for (const s of M.SCHEMES) {
        if (!s.palette) continue
        assert.ok(contrast(s.palette[2], s.palette[0]) >= 4.5, s.id + " fg")
        assert.ok(contrast(s.palette[4], s.palette[0]) >= 3, s.id + " primary")
        assert.ok(contrast(s.palette[6], s.palette[0]) >= 3, s.id + " alert")
    }
})
ok("indexOfId", () => {
    assert.strictEqual(M.indexOfId("nord"), 2)
    assert.strictEqual(M.indexOfId("nope"), -1)
    assert.strictEqual(M.indexOfId(""), -1)
})
console.log(n + " passed")
