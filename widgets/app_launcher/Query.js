.pragma library

// What the launcher makes of the typed text: which apps match and in what order,
// whether it is a calculation, and what qalc answered. Kept free of QML types so
// it can be tested with plain node.

// a calculation starts with a number, a sign, a bracket or a function call
const MATH_START = /^(?:[\d(.+\-]|(?:sqrt|cbrt|sin|cos|tan|ln|log|exp|abs)\s*\()/i

// and does something with it, so "7zip" and "1password" stay searches
const OPERATIONS = [
    /[\d)]\s*[+\-*\/^×÷]\s*[\d(.\-]/,   // 12*7, 2^-3
    /\s[+\-*\/^×÷]\s+\S/,               // 5 km + 3 m
    /[\d)]\s*[*\/^×]\s*[a-z(]/i,        // 2*pi
    /\d\s*(?:!|%$|%\s*of\s)/i,          // 5!, 15% of 80
    /\sto\s+\S/i,                       // 10 km to mi
    /^[a-z]+\s*\(.*\d.*\)/i             // sqrt(16)
]

function looksLikeMath(text) {
    const t = text.trim()
    if (!/\d/.test(t) || !MATH_START.test(t))
        return false
    // a date is not a subtraction
    if (/^\d{4}-\d{2}(?:-\d{2})?$/.test(t))
        return false
    return OPERATIONS.some(re => re.test(t))
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

// `q` is in lower case
function appMatches(e, q) {
    if (e.name.toLowerCase().indexOf(q) !== -1)
        return true
    if (e.genericName && e.genericName.toLowerCase().indexOf(q) !== -1)
        return true
    for (let i = 0; i < e.keywords.length; i++)
        if (e.keywords[i].toLowerCase().indexOf(q) !== -1)
            return true
    return false
}

// The matching desktop entries: names that start with the text first, then the
// most recently launched, then by name. `recent` is entry ids, newest first.
function rankApps(entries, q, recent) {
    const later = e => e.name.toLowerCase().indexOf(q) === 0 ? 0 : 1
    const age = e => {
        const i = recent.indexOf(e.id)
        return i < 0 ? recent.length : i
    }
    return entries.filter(e => appMatches(e, q)).sort((a, b) =>
        later(a) - later(b) || age(a) - age(b) || a.name.localeCompare(b.name))
}
