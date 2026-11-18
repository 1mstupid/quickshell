
.pragma library

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
    const clean = path.replace(/\/+$/, "")
    const i = clean.lastIndexOf("/")
    return i <= 0 ? "/" : clean.slice(0, i)
}

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
        return {
            kind: "browse",
            dir: t.slice(0, i + 1) || "/",
            frag: t.slice(i + 1)
        }
    }

    return { kind: "search", pattern: t }
}

function entry(path, dir, sub, next) {
    return {
        path: path,
        name: path.slice(path.lastIndexOf("/") + 1),
        dir: dir,
        kind: dir ? "folder" : "file",
        glyph: dir ? FOLDER_GLYPH : FILE_GLYPH,
        sub: sub,
        next: next,
        action: dir ? "Navigate into folder" : "Open file"
    }
}

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

    rows.sort((a, b) =>
        (a.dir === b.dir ? 0 : a.dir ? -1 : 1)
        || a.name.localeCompare(b.name)
    )

    return rows.slice(0, MAX_BROWSE).map(r => {
        const path = dir + r.name
        return entry(
            path,
            r.dir,
            r.dir ? "Folder" : "File",
            r.dir ? tilde(path, home) + "/" : ""
        )
    })
}

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

    return rows.map(r => {
        const path = r.path
        return entry(
            path,
            r.dir,
            r.dir ? "Folder" : tilde(parentOf(path), home),
            r.dir ? tilde(path, home) + "/" : ""
        )
    })
}
