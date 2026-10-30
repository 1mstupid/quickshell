pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Widget visibility, read from ~/.local/xdg/config/settings.json:
//   {"usageRing": true, "focusWidget": true}
// A missing file, a bad file or a missing key keeps the default (shown). The
// file is read on start and whenever it changes. The IPC toggles change the
// running value only, so the file stays the source of truth.
Singleton {
    id: root

    readonly property string path: Quickshell.env("HOME") + "/.local/xdg/config/settings.json"

    property bool usageRing: true
    property bool focusWidget: true

    function parse(t) {
        let d = null
        try {
            d = JSON.parse(t)
        } catch (e) {
            d = null
        }
        if (typeof d !== "object" || d === null)
            d = {}
        usageRing = typeof d.usageRing === "boolean" ? d.usageRing : true
        focusWidget = typeof d.focusWidget === "boolean" ? d.focusWidget : true
    }

    FileView {
        path: root.path
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.parse(text())
        onLoadFailed: root.parse("")
    }
}
