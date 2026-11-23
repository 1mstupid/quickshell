.pragma library

// the tray's sort modes, cycled with S. Folders always come first; the mode orders the rest.
const MODES = [
    { key: "name", label: "name" },
    { key: "modified", label: "modified" },
    { key: "size", label: "size" },
    { key: "kind", label: "kind" }
]

// the lower-case extension of a file, or "" when it has none
function extOf(path) {
    const slash = path.lastIndexOf("/")
    const dot = path.lastIndexOf(".")
    if (dot <= slash + 1)
        return ""
    return path.slice(dot + 1).toLowerCase()
}

// a sorted copy of `paths`. infoOf(path) gives { dir, size, mtime } for a path, or nothing.
function sort(paths, mode, infoOf, nameOf) {
    return paths.slice().sort((a, b) => {
        const ia = infoOf(a)
        const ib = infoOf(b)
        const da = ia.dir === true
        const db = ib.dir === true
        if (da !== db)
            return da ? -1 : 1
        let c = 0
        if (mode === "modified")
            c = (ib.mtime || 0) - (ia.mtime || 0)
        else if (mode === "size")
            c = (ib.size || 0) - (ia.size || 0)
        else if (mode === "kind")
            c = extOf(a).localeCompare(extOf(b))
        if (c !== 0)
            return c
        return nameOf(a).localeCompare(nameOf(b))
    })
}
