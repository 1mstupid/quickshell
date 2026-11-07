.pragma library

// The file mode's logic: what a typed line means, and how the output of the
// two tools becomes rows. No QML types, so it can be tested with plain node.
//   browse: the line is a path ("/etc/ng", "~/Doc"), listed with ls
//   search: anything else, looked up under $HOME with fd
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

// Output of `fd --absolute-path`: one path per line, folders possibly with a
// trailing "/". Shallower paths first, since fd's own order is arbitrary.
function parseFd(out, home) {
    const rows = []
    for (const line of out.split("\n")) {
        if (line === "")
            continue
        const isDir = line.length > 1 && line.charAt(line.length - 1) === "/"
        rows.push({ path: isDir ? line.slice(0, -1) : line, dir: isDir })
    }
    const depth = p => p.split("/").length
    rows.sort((a, b) => depth(a.path) - depth(b.path) || a.path.localeCompare(b.path))
    return rows.map(r => entry(r.path, r.dir, tilde(parentOf(r.path), home), ""))
}
