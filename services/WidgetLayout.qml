pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Where the corner widgets sit, read from ~/.local/xdg/config/layout.json:
//   {"todo": {"anchor": "top-left", "x": 0, "y": 0}, "habits": {"anchor": "top-right"}}
// anchor is one of top-left, top-right, bottom-left, bottom-right; x and y are
// whole grid cells (20 px at scale 1) further in from that corner, on top of
// the usual edge inset. A missing file, entry or key keeps the default place,
// so with no file the widgets sit where they always did.
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

    function hasLeft(id) { return anchor(id).endsWith("left") }
    function hasRight(id) { return anchor(id).endsWith("right") }
    function hasTop(id) { return anchor(id).startsWith("top") }
    function hasBottom(id) { return anchor(id).startsWith("bottom") }

    // margin from the anchored edges (the other two are ignored by the compositor)
    function insetX(id) { return Theme.edgeInset + cells(id, "x") * cell }
    function insetY(id) { return Theme.edgeInset + cells(id, "y") * cell }

    FileView {
        path: root.path
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.parse(text())
        onLoadFailed: root.parse("")
    }
}
