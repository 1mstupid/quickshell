pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Where the corner widgets sit and whether they show, kept in
// ~/.local/xdg/config/layout.json:
//   {"todo": {"anchor": "top-left", "x": 0, "y": 0, "visible": true}}
// anchor is one of top-left, top-right, bottom-left, bottom-right; x and y are
// whole grid cells (20 px at scale 1) further in from that corner, on top of
// the usual edge inset. A missing file, entry or key keeps the default place,
// so with no file the widgets sit where they always did. `visible` wins over
// the widget keys in settings.json once it is set. The edit mode writes this
// file; it can also be edited by hand.
Singleton {
    id: root

    readonly property string path: Quickshell.env("HOME") + "/.local/xdg/config/layout.json"

    readonly property int cell: Math.round(20 * Theme.autoScale)
    readonly property var corners: ["top-left", "top-right", "bottom-left", "bottom-right"]
    readonly property var defaults: ({
        todo: "top-left",
        habits: "top-right",
        focus: "bottom-left",
        usage: "bottom-right"
    })

    property var entries: ({})

    // the widget windows by id, so the edit mode can see which are showing
    property var windows: ({})

    // what settings.json says, for a widget with no `visible` of its own
    readonly property var legacy: ({
        todo: UserSettings.todoWidget,
        habits: UserSettings.habitsWidget,
        focus: UserSettings.focusWidget,
        usage: UserSettings.usageRing
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

    // the functions read `entries`, so bindings on them follow the file
    function anchor(id) {
        const e = entries[id]
        return e && corners.includes(e.anchor) ? e.anchor : defaults[id]
    }

    function cells(id, key) {
        const e = entries[id]
        return e && Number.isInteger(e[key]) && e[key] >= 0 ? e[key] : 0
    }

    function shown(id) {
        const e = entries[id]
        return e && typeof e.visible === "boolean" ? e.visible : legacy[id]
    }

    function register(id, win) {
        const next = Object.assign({}, windows)
        next[id] = win
        windows = next
    }

    // merge into one widget's entry and write the file; the watcher reloads
    // the same content afterwards, which changes nothing
    function save(id, patch) {
        const next = Object.assign({}, entries)
        next[id] = Object.assign({}, next[id], patch)
        entries = next
        file.setText(JSON.stringify(next, null, 2) + "\n")
    }

    function place(id, anchor, x, y) { save(id, { anchor: anchor, x: x, y: y }) }
    function toggle(id) { save(id, { visible: !shown(id) }) }

    function hasLeft(id) { return anchor(id).endsWith("left") }
    function hasRight(id) { return anchor(id).endsWith("right") }
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
