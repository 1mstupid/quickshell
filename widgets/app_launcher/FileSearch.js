.pragma library

const FILE_GLYPH = "󰈔"
const FOLDER_GLYPH = "󰉋"

function tilde(path, home) {
    if (home !== "" && path === home)
        return "~"
    if (home !== "" && path.indexOf(home + "/") === 0)
        return "~" + path.slice(home.length)
    return path
}

function parentOf(path) {
    const clean = path.replace(/\/+$/, "")
    const i = clean.lastIndexOf("/")
    return i <= 0 ? "/" : clean.slice(0, i)
}

// "4.2 MB": whole numbers from 10 up, one decimal below
function fmtSize(bytes) {
    const units = ["B", "KB", "MB", "GB", "TB"]
    let v = bytes
    let i = 0
    while (v >= 1024 && i < units.length - 1) {
        v /= 1024
        i++
    }
    if (i === 0)
        return v + " B"
    return (v < 10 ? v.toFixed(1) : Math.round(v)) + " " + units[i]
}

// the time of today's files, the date of older ones; seconds since the epoch in, text out
function fmtDate(epochSec, nowMs) {
    const d = new Date(epochSec * 1000)
    const n = new Date(nowMs)
    if (d.toDateString() === n.toDateString())
        return String(d.getHours()).padStart(2, "0") + ":" + String(d.getMinutes()).padStart(2, "0")
    const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    return d.getDate() + " " + months[d.getMonth()] + " " + d.getFullYear()
}

// the row's second line: where it lives, then a file's size and when it changed.
// meta is the stat of the path, or undefined while it is still being read.
function describe(e, meta, nowMs) {
    const parts = e.dir ? ["Folder", e.sub] : [e.sub]
    if (meta) {
        if (!e.dir)
            parts.push(fmtSize(meta.size))
        parts.push(fmtDate(meta.mtime, nowMs))
    }
    return parts.join("  ·  ")
}

// fd's lines as rows, the shallowest first; a folder's line ends in "/"
function parseFd(out, home) {
    const rows = []

    for (const line of out.split("\n")) {
        if (line === "")
            continue

        const isDir = line.length > 1 && line.charAt(line.length - 1) === "/"
        rows.push({
            path: isDir ? line.slice(0, -1) : line,
            dir: isDir
        })
    }

    const depth = p => p.split("/").length

    rows.sort((a, b) =>
        depth(a.path) - depth(b.path)
        || a.path.localeCompare(b.path)
    )

    return rows.map(r => ({
        path: r.path,
        name: r.path.slice(r.path.lastIndexOf("/") + 1),
        dir: r.dir,
        glyph: r.dir ? FOLDER_GLYPH : FILE_GLYPH,
        sub: tilde(parentOf(r.path), home)
    }))
}
