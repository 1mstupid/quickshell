pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Where the corner widgets sit, how big they are and whether they show, kept in
// ~/.local/state/lumin/layout.json:
//   {"todo": {"anchor": "top-left", "x": 0, "y": 0, "visible": true}}
// anchor is one of top-left, top-right, bottom-left, bottom-right, or
// bottom-center (centred, with no side margin); x and y are grid cells
// (20 px at scale 1), fractional where a smart guide lined the widget up, further
// in from that corner, on top of the usual edge
// inset. scale (1 when missing) sizes the widgets listed in `scalable` and the
// image frames. A frame is an entry named frame-N, as many as were added, with a
// shape (one of `shapes`, square when missing) and the path of its image:
//   {"frame-1": {"anchor": "top-left", "x": 20, "y": 4, "shape": "wide", "image": "/…"}}
// A missing file, entry or key keeps the default place,
// so with no file the widgets sit where they always did. `visible` wins over
// the widget keys in config.toml's [settings] table once it is set. The edit mode writes this
// file; it can also be edited by hand.
Singleton {
    id: root

    readonly property string path: Quickshell.env("HOME") + "/.local/state/lumin/layout.json"

    readonly property int cell: Math.round(20 * Theme.autoScale)
    readonly property var corners: ["top-left", "top-right", "bottom-left", "bottom-right", "bottom-center"]
    readonly property var defaults: ({
        todo: "top-left",
        habits: "top-right",
        focus: "bottom-left",
        usage: "bottom-right",
        study: "bottom-right",
        clock: "top-left",
        media: "bottom-center",
        lyrics: "bottom-center"
    })
    // the glyph each widget is listed under in the layout bar
    readonly property var glyphs: ({
        todo: "󰄬",
        habits: "󰄳",
        focus: "󰔟",
        usage: "󰄪",
        study: "󰑴",
        clock: "󰅐",
        media: "󰝚",
        lyrics: "󰎈"
    })

    property var entries: ({})

    // the widgets that draw themselves at their scale, and the range it is held to
    readonly property var scalable: ["clock", "lyrics"]
    readonly property real minScale: 0.75
    readonly property real maxScale: 3
    readonly property real scaleStep: 0.25

    // the image frames in the file, and every id there is to place
    property var frames: []
    readonly property var ids: Object.keys(defaults).concat(frames)
    // a frame's width and height at scale 1. Wide spans two 240 px widgets set side by side
    // as close as the grid allows.
    readonly property var shapes: ({
        square: [240, 240],
        wide: [(Math.ceil(240 / cell) + 1) * cell + 240, 240],
        tall: [240, 360]
    })

    // the widget windows by id, so the edit mode can see which are showing
    property var windows: ({})

    // what config.toml says, for a widget with no `visible` of its own
    readonly property var legacy: ({
        todo: UserSettings.todoWidget,
        habits: UserSettings.habitsWidget,
        focus: UserSettings.focusWidget,
        usage: UserSettings.usageRing,
        study: UserSettings.studyWidget,
        clock: UserSettings.clockWidget,
        media: UserSettings.mediaWidget,
        lyrics: false
    })

    function parse(t) {
        let d = null
        try {
            d = JSON.parse(t)
        } catch (e) {
            d = null
        }
        entries = typeof d === "object" && d !== null && !Array.isArray(d) ? d : {}
    }

    function isFrame(id) { return /^frame-[0-9]+$/.test(id) }

    // `frames` only changes when one is added or removed, so that moving or
    // resizing a widget does not build the frame windows and outlines again
    onEntriesChanged: {
        const next = Object.keys(entries)
            .filter(id => isFrame(id) && typeof entries[id] === "object" && entries[id] !== null)
            .sort((a, b) => Number(a.slice(6)) - Number(b.slice(6)))
        if (next.join() === frames.join())
            return
        // a removed frame's window goes with it
        for (const id of frames.filter(id => !next.includes(id)))
            unregister(id)
        frames = next
    }

    // the functions read `entries`, so bindings on them follow the file
    function anchor(id) {
        const e = entries[id]
        return e && corners.includes(e.anchor) ? e.anchor : defaults[id] ?? "top-left"
    }

    function cells(id, key) {
        const e = entries[id]
        if (e && typeof e[key] === "number" && isFinite(e[key]) && e[key] >= 0)
            return e[key]
        // the study widget shares the usage ring's corner and the clock the todo widget's, so
        // until placed each starts one cell in from that neighbour, which is 240 px wide
        if ((id === "study" || id === "clock") && key === "x" && !(e && e.anchor))
            return Math.ceil(240 / cell) + 1
        return 0
    }

    function clampScale(v) { return Math.min(maxScale, Math.max(minScale, v)) }

    function scaleOf(id) {
        const e = entries[id]
        return e && typeof e.scale === "number" && isFinite(e.scale) ? clampScale(e.scale) : 1
    }

    function canScale(id) { return isFrame(id) || scalable.includes(id) }

    function shapeOf(id) {
        const e = entries[id]
        return e && Object.keys(shapes).includes(e.shape) ? e.shape : "square"
    }

    function imageOf(id) {
        const e = entries[id]
        return e && typeof e.image === "string" ? e.image : ""
    }

    // a frame shows for as long as it has an entry
    function shown(id) {
        const e = entries[id]
        if (e && typeof e.visible === "boolean")
            return e.visible
        return isFrame(id) ? e !== undefined : legacy[id]
    }

    function register(id, win) {
        const next = Object.assign({}, windows)
        next[id] = win
        windows = next
    }

    function unregister(id) {
        const next = Object.assign({}, windows)
        delete next[id]
        windows = next
    }

    // the lowest frame-N not in use
    function nextFrameId() {
        let n = 1
        while (entries["frame-" + n] !== undefined)
            n++
        return "frame-" + n
    }

    // the watcher reloads the same content afterwards, which changes nothing
    function write(next) {
        entries = next
        file.setText(JSON.stringify(next, null, 2) + "\n")
    }

    // merge into one widget's entry and write the file
    function save(id, patch) {
        const next = Object.assign({}, entries)
        next[id] = Object.assign({}, next[id], patch)
        write(next)
    }

    // drops a frame; its image file is left alone
    function remove(id) {
        const next = Object.assign({}, entries)
        delete next[id]
        write(next)
    }

    function place(id, anchor, x, y) { save(id, { anchor: anchor, x: x, y: y }) }
    function toggle(id) { save(id, { visible: !shown(id) }) }
    function resize(id, scale) { save(id, { scale: clampScale(scale) }) }

    function hasLeft(id) { return anchor(id).endsWith("left") }
    function hasRight(id) { return anchor(id).endsWith("right") }
    function hasCenter(id) { return anchor(id) === "bottom-center" }
    function hasTop(id) { return anchor(id).startsWith("top") }
    function hasBottom(id) { return anchor(id).startsWith("bottom") }

    // margin from the anchored edges (the other two are ignored by the compositor)
    function insetX(id) { return Theme.edgeInset + cells(id, "x") * cell }
    function insetY(id) { return Theme.edgeInset + cells(id, "y") * cell }

    FileView {
        id: file
        path: root.path
        atomicWrites: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.parse(text())
        onLoadFailed: root.parse("")
    }
}
