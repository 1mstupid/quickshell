// Run: node test_palette.js
// Loads WallpaperPalette.js (stripping the QML-only .pragma line) and checks
// its output on synthetic 32x32 RGBA images.
const fs = require("fs")
const path = require("path")

const src = fs.readFileSync(path.join(__dirname, "WallpaperPalette.js"), "utf8")
    .replace(/^\.pragma library\s*$/m, "")
const { derive } = new Function(src + "\nreturn { derive };")()

function image(fn) {
    const d = new Uint8ClampedArray(32 * 32 * 4)
    for (let y = 0; y < 32; y++)
        for (let x = 0; x < 32; x++) {
            const [r, g, b] = fn(x, y)
            const i = (y * 32 + x) * 4
            d[i] = r; d[i + 1] = g; d[i + 2] = b; d[i + 3] = 255
        }
    return d
}

const cases = {
    gradient: image((x, y) => [x * 8, 60 + y * 4, 200 - x * 4]),
    red:      image((x, y) => [200 + (x % 3), 30, 30]),
    gray:     image((x, y) => [120, 120, 120]),
}

let failures = 0
for (const [name, px] of Object.entries(cases)) {
    const out = derive(px)
    const ok = out
        && out.palette.length === 8
        && out.ansi.length === 16
        && [...out.palette, ...out.ansi].every(h => /^#[0-9a-f]{6}$/.test(h))
    console.log(name.padEnd(9), ok ? "ok  " : "FAIL", out ? JSON.stringify(out) : "null")
    if (!ok) failures++
}

const transparent = new Uint8ClampedArray(32 * 32 * 4)
const empty = derive(transparent)
console.log("transparent", empty === null ? "ok   (null, as before)" : "FAIL")
if (empty !== null) failures++

process.exitCode = failures ? 1 : 0
