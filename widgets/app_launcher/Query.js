.pragma library

// What the launcher makes of the typed text: which apps and emoji match and in what
// order, whether it is a calculation, and what qalc answered. Kept free of QML types
// so it can be tested with plain node.

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

// --- Emoji ---

// the lines of EmojiData.js
function parseEmoji(lines) {
    return lines.trim().split("\n").map(l => {
        const f = l.split("\t")
        return { emoji: f[0], names: f[1].split(" "), tags: f[2] ? f[2].split(" ") : [] }
    })
}

// what a shortcode asks for: ":cry", ":cry:" and ":crying face" are all taken
function emojiTerm(text) {
    return text.slice(1).replace(/:$/, "").trim().toLowerCase().replace(/\s+/g, "_")
}

// The matching emoji: the name itself, then names that start with the term, then words
// that do, then anything holding it. Within each, the list's own order, faces first.
function rankEmoji(list, term, limit) {
    if (term === "")
        return list.slice(0, limit)
    const tier = e => {
        if (e.names.indexOf(term) >= 0)
            return 0
        if (e.names.some(n => n.startsWith(term)))
            return 1
        const words = e.names.concat(e.tags)
        if (words.some(w => w.startsWith(term) || w.indexOf("_" + term) >= 0))
            return 2
        return words.some(w => w.indexOf(term) >= 0) ? 3 : -1
    }
    // buckets, not a sort: the order within one has to survive
    const found = [[], [], [], []]
    for (const e of list) {
        const t = tier(e)
        if (t >= 0)
            found[t].push(e)
    }
    return found[0].concat(found[1], found[2], found[3]).slice(0, limit)
}

// --- Hyprland Window Management ---


function windowMatches(win, q) {
    const query = q.trim().toLowerCase()
    if (!query) return true

    const fields = [
        win.title,
        win.class,
        win.initialClass,
        win.initialTitle,
        win.wayland?.appId,
        win.lastIpcObject?.class,
        win.lastIpcObject?.initialClass,
        win.lastIpcObject?.title
    ]

    return fields.some(value =>
        typeof value === "string" &&
        value.toLowerCase().includes(query)
    )
}

// Rank windows: matches query, sorts by most recently used first, 
// but keeps the currently focused window last and utilizes smart scoring.
function rankWindows(windows, q, recentWindowAddresses, focusedAddress) {
    const query = q.trim().toLowerCase()

    const score = win => {
        const fields = [
            win.class,
            win.initialClass,
            win.wayland?.appId,
            win.lastIpcObject?.class,
            win.lastIpcObject?.initialClass
        ]

        // Stable app identity gets priority over arbitrary window titles.
        if (fields.some(v =>
            typeof v === "string" && v.toLowerCase() === query
        )) return 0

        if (fields.some(v =>
            typeof v === "string" && v.toLowerCase().startsWith(query)
        )) return 1

        if (fields.some(v =>
            typeof v === "string" && v.toLowerCase().includes(query)
        )) return 2

        if ([win.title, win.initialTitle].some(v =>
            typeof v === "string" && v.toLowerCase().includes(query)
        )) return 3

        return 4
    }
    
    return windows.filter(w => windowMatches(w, query)).sort((a, b) => {
        const aIsFocused = (a.address === focusedAddress) ? 1 : 0
        const bIsFocused = (b.address === focusedAddress) ? 1 : 0

        // Focused window always goes last (0 before 1)
        if (aIsFocused !== bIsFocused) {
            return aIsFocused - bIsFocused
        }

        const scoreDiff = score(a) - score(b)
        if (scoreDiff !== 0) {
            return scoreDiff
        }

        // Recency: index in recentWindowAddresses (smaller index = more recent)
        const aAge = recentWindowAddresses.indexOf(a.address)
        const bAge = recentWindowAddresses.indexOf(b.address)
        const aIndex = aAge === -1 ? Infinity : aAge
        const bIndex = bAge === -1 ? Infinity : bAge

        if (aIndex !== bIndex) {
            return aIndex - bIndex
        }

        return (a.title || "").localeCompare(b.title || "")
    })
}

// Format workspace subtitle string
function formatWorkspaceSubtitle(win, focusedAddress) {
    let sub = `Workspace ${win.workspace ? win.workspace.name : "unknown"}`
    if (win.address === focusedAddress) {
        sub += " · current"
    }
    return sub
}
