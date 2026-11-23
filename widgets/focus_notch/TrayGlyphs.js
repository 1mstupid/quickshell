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

const VIDEO = ["mp4", "mkv", "webm", "mov", "avi", "m4v"]

const AUDIO = ["mp3", "m4a", "flac", "ogg", "opus", "wav"]

function isAudio(path) {
    const slash = path.lastIndexOf("/")
    const dot = path.lastIndexOf(".")
    if (dot <= slash + 1)
        return false
    return AUDIO.indexOf(path.slice(dot + 1).toLowerCase()) >= 0
}

// a clip has a frame to show: a video's, or an audio file's cover art
function isMedia(path) {
    return isVideo(path) || isAudio(path)
}

function isVideo(path) {
    const slash = path.lastIndexOf("/")
    const dot = path.lastIndexOf(".")
    if (dot <= slash + 1)
        return false
    return VIDEO.indexOf(path.slice(dot + 1).toLowerCase()) >= 0
}

// the cached thumbnail's file name: a 32-bit FNV-1a hash of the path, so it is the same each time
function thumbName(path) {
    let h = 0x811c9dc5
    for (let i = 0; i < path.length; i++) {
        h ^= path.charCodeAt(i)
        h = Math.imul(h, 0x01000193)
    }
    return (h >>> 0).toString(16) + ".png"
}
