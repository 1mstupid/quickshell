.pragma library

// Launcher modes, entered by typing a bang and a space ("!calc 2+2"). Kept free
// of QML types so it can be tested with plain node.
const MODES = [
    { name: "calc", title: "Calculator", subtitle: "!calc  evaluate with qalc", glyph: "󰃬", placeholder: "Calculate" },
    { name: "file", title: "Files", subtitle: "!file  find, or / ~ to browse", glyph: "󰈔", placeholder: "Find files, or / ~ to browse" }
]

function find(name) {
    for (const m of MODES)
        if (m.name === name)
            return m
    return null
}

// "!calc 2+2" -> { mode: "calc", text: "2+2" }. The bang only counts once the
// space is typed, so "!calc" alone stays text and shows as a hint.
function parse(text) {
    const m = /^!(\S+) ([\s\S]*)$/.exec(text)
    if (m) {
        const info = find(m[1].toLowerCase())
        if (info)
            return { mode: info.name, text: m[2] }
    }
    return { mode: "", text: text }
}

// the modes a half-typed bang could still become ("!ca" -> calc, "!" -> all)
function hints(text) {
    if (text.charAt(0) !== "!" || /\s/.test(text))
        return []
    const frag = text.slice(1).toLowerCase()
    return MODES.filter(m => m.name.indexOf(frag) === 0)
}

// The answer line of `qalc -t`, or "" when there is no usable one: an error, no
// output, or the expression echoed back unchanged (qalc does that for text it
// cannot read as maths).
function answer(out, expr) {
    const lines = out.split("\n").map(s => s.trim()).filter(s => s !== "")
    for (const l of lines)
        if (/^error/i.test(l))
            return ""
    const ok = lines.filter(l => !/^warning/i.test(l))
    if (ok.length === 0)
        return ""
    const last = ok[ok.length - 1]
    return last.toLowerCase() === expr.trim().toLowerCase() ? "" : last
}
