pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool launcherVisible: false
    property var recentIds: []

    readonly property string recentsPath:
        Quickshell.env("HOME") + "/.local/xdg/config/app-launcher-recents"

    // one JSON array of desktop-entry ids, most recent first
    FileView {
        id: recentsFile
        path: root.recentsPath
        atomicWrites: true
        onLoaded: {
            try {
                root.recentIds = JSON.parse(text())
            } catch (e) {
                root.recentIds = []
            }
        }
        onLoadFailed: root.recentIds = []
    }

    Component.onCompleted: {
        // FileView won't create the directory on write
        Quickshell.execDetached(["mkdir", "-p",
            Quickshell.env("HOME") + "/.local/xdg/config"])
    }

    function toggle() { launcherVisible = !launcherVisible }
    function show()   { launcherVisible = true }
    function hide()   { launcherVisible = false }

    function recordLaunch(id) {
        var list = recentIds.slice()
        var idx  = list.indexOf(id)
        if (idx !== -1) list.splice(idx, 1)
        list.unshift(id)
        if (list.length > 12) list = list.slice(0, 12)
        recentIds = list
        recentsFile.setText(JSON.stringify(list))
    }

    function clearRecents() {
        recentIds = []
        recentsFile.setText("[]")
    }
}
