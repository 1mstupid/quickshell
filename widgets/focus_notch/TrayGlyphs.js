.pragma library

// the glyph of a tray card: a folder, or a file by its extension. Unknown
// extensions, and a file with none, get the plain file glyph.
const FOLDER = "󰉋"
const FILE = "󰈔"
const BY_EXT = {
    png: "󰋩", jpg: "󰋩", jpeg: "󰋩", gif: "󰋩", webp: "󰋩", bmp: "󰋩", svg: "󰋩",
    mp4: "󰕧", mkv: "󰕧", webm: "󰕧", mov: "󰕧", avi: "󰕧",
    mp3: "󰎆", flac: "󰎆", ogg: "󰎆", wav: "󰎆", m4a: "󰎆", opus: "󰎆",
    pdf: "󰈦",
    zip: "󰗄", tar: "󰗄", gz: "󰗄", xz: "󰗄", bz2: "󰗄", "7z": "󰗄", rar: "󰗄", zst: "󰗄",
    js: "󰅩", ts: "󰅩", qml: "󰅩", py: "󰅩", sh: "󰅩", nix: "󰅩", rs: "󰅩", go: "󰅩",
    c: "󰅩", cpp: "󰅩", h: "󰅩", java: "󰅩", json: "󰅩", yaml: "󰅩", yml: "󰅩", toml: "󰅩",
    html: "󰅩", css: "󰅩",
    txt: "󰈙", md: "󰈙", log: "󰈙", rst: "󰈙", doc: "󰈙", docx: "󰈙", odt: "󰈙"
}

function glyphFor(path, isDir) {
    if (isDir)
        return FOLDER
    const slash = path.lastIndexOf("/")
    const dot = path.lastIndexOf(".")
    // a dot that starts the name ("." files) is not an extension
    if (dot <= slash + 1)
        return FILE
    return BY_EXT[path.slice(dot + 1).toLowerCase()] ?? FILE
}
