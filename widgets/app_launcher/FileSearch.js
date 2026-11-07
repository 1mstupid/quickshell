.pragma library

// The file mode's logic: what a typed line means, and how the output of the
// two tools becomes rows. No QML types, so it can be tested with plain node.
//   browse: the line is a path ("/etc/ng", "~/Doc"), listed with ls
//   search: anything else, fuzzy-matched against the files under $HOME that fd lists
const FILE_GLYPH = "󰈔"
const FOLDER_GLYPH = "󰉋"
const MAX_BROWSE = 100

function tilde(path, home) {
    if (home !== "" && path === home)
        return "~"
    if (home !== "" && path.indexOf(home + "/") === 0)
        return "~" + path.slice(home.length)
    return path
}

function parentOf(path) {
    const i = path.lastIndexOf("/")
    return i <= 0 ? "/" : path.slice(0, i)
}

// -> { kind: "none" } | { kind: "browse", dir, frag } | { kind: "search", pattern }
// browse: dir is the folder to list (with a trailing "/"), frag what is typed after it
function classify(text, home) {
    let t = text.trim()
    if (t === "")
        return { kind: "none" }
    if (t === "~")
        t = "~/"
    if (t.indexOf("~/") === 0)
        t = home + t.slice(1)
    if (t.charAt(0) === "/") {
        const i = t.lastIndexOf("/")
        return { kind: "browse", dir: t.slice(0, i + 1), frag: t.slice(i + 1) }
    }
    return { kind: "search", pattern: t }
}

function entry(path, dir, sub, next) {
    return {
        path: path,
        name: path.slice(path.lastIndexOf("/") + 1),
        dir: dir,
        glyph: dir ? FOLDER_GLYPH : FILE_GLYPH,
        sub: sub,
        next: next
    }
}

// Output of `ls -1ApL DIR`: one name per line, folders with a trailing "/".
// Keeps the names containing frag (hidden ones only when frag starts with a dot),
// folders first. A folder's `next` is the text that opens it in the line.
function parseLs(out, dir, frag, home) {
    const f = frag.toLowerCase()
    const rows = []
    for (const line of out.split("\n")) {
        if (line === "")
            continue
        const isDir = line.charAt(line.length - 1) === "/"
        const name = isDir ? line.slice(0, -1) : line
        if (name === "")
            continue
        if (name.charAt(0) === "." && frag.charAt(0) !== ".")
            continue
        if (f !== "" && name.toLowerCase().indexOf(f) === -1)
            continue
        rows.push({ name: name, dir: isDir })
    }
    rows.sort((a, b) => (a.dir === b.dir ? 0 : a.dir ? -1 : 1) || a.name.localeCompare(b.name))
    return rows.slice(0, MAX_BROWSE).map(r => {
        const path = dir + r.name
        return entry(path, r.dir, "", r.dir ? tilde(path, home) + "/" : "")
    })
}

// Output of `fd --absolute-path`, read once into the list the search runs on:
// one item per path, with its lower-cased path under $HOME to match against.
// A folder may come with a trailing "/".
function prepare(out, home) {
    const items = []
    for (const line of out.split("\n")) {
        if (line === "")
            continue
        const dir = line.length > 1 && line.charAt(line.length - 1) === "/"
        const path = dir ? line.slice(0, -1) : line
        const rel = home !== "" && path.indexOf(home + "/") === 0 ? path.slice(home.length + 1) : path
        items.push({ path: path, dir: dir, low: rel.toLowerCase() })
    }
    return items
}

// How well the letters of q appear in order in s (both lower case): -1 if they
// do not, else a score. Letters that follow each other, and letters that start
// a word, count extra.
function subseq(s, q) {
    let score = 0
    let from = 0
    let prev = -2
    for (let i = 0; i < q.length; i++) {
        const j = s.indexOf(q.charAt(i), from)
        if (j < 0)
            return -1
        if (j === prev + 1)
            score += 5
        const b = j === 0 ? "/" : s.charAt(j - 1)
        if (b === "/" || b === "." || b === "-" || b === "_" || b === " ")
            score += 8
        prev = j
        from = j + 1
    }
    return score
}

// null when qn is not in the path. A match in the file name beats one spread
// over the folders, an exact piece of the name beats scattered letters, and a
// shorter path breaks ties.
function scoreOf(low, qn) {
    const base = low.slice(low.lastIndexOf("/") + 1)
    let total
    const s = subseq(base, qn)
    if (s >= 0) {
        const k = base.indexOf(qn)
        total = 100 + s + (k >= 0 ? 40 : 0) + (k === 0 ? 20 : 0)
    } else {
        const p = subseq(low, qn)
        if (p < 0)
            return null
        total = p
    }
    return total - low.length * 0.2
}

// Fuzzy search over prepared items; spaces in q are ignored. -> { pool, top }:
// every item that matches, best first, and the best `limit` of them as rows.
// Any longer query that starts with q can only match what is in pool, so the
// next keystroke can search that instead of the whole list.
function fuzzy(items, q, limit, home) {
    const qn = q.replace(/\s+/g, "").toLowerCase()
    if (qn === "")
        return { pool: [], top: [] }
    const hits = []
    for (const it of items) {
        const s = scoreOf(it.low, qn)
        if (s !== null)
            hits.push({ it: it, s: s })
    }
    hits.sort((a, b) => b.s - a.s || a.it.low.length - b.it.low.length || (a.it.low < b.it.low ? -1 : 1))
    return {
        pool: hits.map(h => h.it),
        top: hits.slice(0, limit).map(h => entry(h.it.path, h.it.dir, tilde(parentOf(h.it.path), home), ""))
    }
}
