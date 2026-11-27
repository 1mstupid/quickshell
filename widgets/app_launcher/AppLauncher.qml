import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import "../../services"
import "../notch"
import "Query.js" as Query
import "FileSearch.js" as FileSearch

// The launcher grows out of the bar pill, the same way the wallpaper picker does. It is an
// item of the origin bar's window (Bar.qml), so it drops from the pill with no seam.
Item {
    id: root

    visible: false
    anchors.fill: parent

    IpcHandler {
        target: "applauncher"
        function toggle(): void { AppLauncherState.toggle() }
    }

    // ── Geometry ───────────────────────────────────────────────────────────
    readonly property int maxVisible: 7
    readonly property int itemH: 44
    readonly property int panelW: 400
    // the panel around the rows, and the panel with only the search box
    readonly property int chromeH: 90
    readonly property int emptyH: 58

    property real startW: PillState.pillWidth
    property real startH: PillState.pillHeight
    property real t: 0
    // a card closed back to the pill is hidden there: the elastic close reaches the pill early, and
    // a card left over it hid the bar's content until the morph finished
    onTChanged: if (morph.running && morph.to === 0 && t <= 0) visible = false

    property real panelH: hasQuery
        ? chromeH + Math.max(1, Math.min(results.length, maxVisible)) * itemH : emptyH
    // not while hidden, so a launcher reopened starts at the box's height
    Behavior on panelH {
        enabled: root.visible
        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
    }

    // ── State ──────────────────────────────────────────────────────────────
    property string searchQuery: ""
    readonly property string query: searchQuery.trim()
    readonly property bool hasQuery: query !== ""
    readonly property bool isMath: Query.looksLikeMath(query)

    // The calculator's answer, then windows, then apps, then files. Nothing until something is typed.
    readonly property var results: hasQuery
        ? calcResults(query).concat(windowResults(query.toLowerCase()), appResults(query.toLowerCase()), fileResults(query)) : []

    // The selection is the row picked, not its place: rows that arrive late (the answer, the
    // files) never move it. With nothing picked it is the top row, and new text picks nothing.
    property string selectedKey: ""
    readonly property int selectedIndex: Math.max(0, results.findIndex(r => r.key === selectedKey))
    readonly property var current: results[selectedIndex] ?? null
    onQueryChanged: selectedKey = ""
    onResultsChanged: Qt.callLater(reveal)

    // where the pointer was last seen: rows that appear under a still pointer do not take the
    // selection, only a pointer that moves does
    property var pointer: null

    // Track window focus recency for ranking
    property var recentWindowAddresses: []

    Connections {
        target: Hyprland
        function onFocusedWindowChanged() {
            if (Hyprland.focusedWindow) {
                const addr = Hyprland.focusedWindow.address;
                let list = recentWindowAddresses.slice();
                const idx = list.indexOf(addr);
                if (idx >= 0) list.splice(idx, 1);
                list.unshift(addr);
                recentWindowAddresses = list;
            }
        }
    }

    // the answer row holds its place with "…" while qalc works, so the rows below do not jump
    function calcResults(q) {
        if (!isMath) return []
        const ready = Calc.resultFor === q
        if (ready ? Calc.result === "" : !Calc.busy) return []
        return [{ kind: "calc", key: "calc", title: ready ? Calc.result : "…", subtitle: q,
                  icon: "", glyph: "󰃬", value: ready ? Calc.result : "" }]
    }

    function appResults(q) {
        const toplevels = Hyprland.toplevels ? (Hyprland.toplevels.values || []) : []
        const runningAppIds = new Set()
        for (const t of toplevels) {
            const appId = (t.wayland?.appId || t.lastIpcObject?.class || "").toLowerCase()
            if (appId) runningAppIds.add(appId)
        }

        // an entry is hidden if it's blocked OR if an open window already exists for it
        const vals = DesktopEntries.applications.values.filter(function (e) {
            if (AppUsage.blockedNow(e.startupClass) || AppUsage.blockedNow(e.id))
                return false
            const eId = (e.id || "").toLowerCase()
            const eClass = (e.startupClass || "").toLowerCase()
            if (runningAppIds.has(eId) || (eClass && runningAppIds.has(eClass)))
                return false
            return true
        })
        return Query.rankApps(vals, q, AppLauncherState.recentIds).map(function (e) {
            return { kind: "app", key: "app:" + e.id, title: e.name, subtitle: subtitleOf(e), icon: e.icon, glyph: "", entry: e }
        })
    }

    function windowResults(q) {
        if (typeof Hyprland === "undefined" || !Hyprland.toplevels) return []
        const toplevels = Hyprland.toplevels.values || []
        const desktopEntries = DesktopEntries.applications.values || []
        const focusedAddress = Hyprland.focusedWindow ? Hyprland.focusedWindow.address : ""

        const ranked = Query.rankWindows(toplevels, q, recentWindowAddresses, focusedAddress)

        return ranked.map(t => {
            const title = t.title || "Untitled Window"
            const appId = t.wayland?.appId || t.lastIpcObject?.class || ""
            const matchedApp = desktopEntries.find(e => e.id.toLowerCase() === appId.toLowerCase() || e.startupClass?.toLowerCase() === appId.toLowerCase())

            return {
                kind: "window",
                key: "window:" + t.address,
                title: title,
                subtitle: Query.formatWorkspaceSubtitle(t, focusedAddress),
                icon: matchedApp ? matchedApp.icon : "",
                glyph: "󰖯",
                window: t,
                matchedApp: matchedApp
            }
        })
    }

    // one letter finds too much to be worth listing. While fd is still looking, its last
    // answer is narrowed to what still matches, so rows do not blink out between keys.
    function fileResults(q) {
        if (q.length < 2) return []
        const f = q.toLowerCase()
        return Files.entries.filter(e => e.name.toLowerCase().indexOf(f) !== -1).map(function (e) {
            return { kind: "file", key: "file:" + e.path, title: e.name, subtitle: FileSearch.describe(e, Files.meta[e.path], Date.now()), icon: "", glyph: e.glyph, value: e.path }
        })
    }

    readonly property string emptyText: Files.busy || Calc.busy ? "" : "Nothing found"

    readonly property string hintText: {
        if (!current) return "esc close"
        if (current.kind === "calc") return "↵ copy    esc close"
        if (current.kind === "app") return "↑↓ move    ↵ launch    esc close"
        if (current.kind === "window") {
            const canShift = current.matchedApp !== null
            return "↵ focus window" + (canShift ? "    ⇧↵ open new instance" : "") + "    esc close"
        }
        const kept = ShareService.favorites.indexOf(current.value) >= 0
        return "↵ open    " + (kept ? "✓ in tray" : "^↵ add to tray") + "    esc close"
    }

    function subtitleOf(entry) {
        if (entry.genericName && entry.genericName !== "") return entry.genericName;
        if (entry.categories && entry.categories.length > 0) return entry.categories[0];
        return "";
    }

    function openLauncher() {
        if (!PillState.claim("applauncher")) return;
        Sounds.play("open");
        const from = PillState.takeOver();
        startW = from.w;
        startH = from.h;
        searchInput.text = "";
        selectedKey = "";
        pointer = null;
        visible = true;
        morph.stop();
        morph.from = root.t;
        morph.to = 1;
        morph.start();
    }

    function giveWay() {
        PillState.takeoverW = card.width;
        PillState.takeoverH = card.height;
        morph.stop();
        visible = false;
        t = 0;
    }

    function close() {
        if (!visible) return;
        Sounds.play("close");
        if (PillState.owner === "applauncher")
            PillState.returning = true;
        startW = PillState.pillWidth;
        startH = PillState.pillHeight;
        morph.stop();
        morph.from = root.t;
        morph.to = 0;
        morph.start();
    }

    NumberAnimation {
        id: morph
        target: root
        property: "t"
        duration: PillState.morphMs
        easing.type: PillState.openEase
        easing.period: PillState.easePeriod
        onFinished: {
            if (root.t < 0.5) {
                root.visible = false;
                if (PillState.owner === "applauncher") PillState.owner = "";
            }
        }
    }

    Connections {
        target: AppLauncherState
        function onLauncherVisibleChanged() {
            if (AppLauncherState.launcherVisible) root.openLauncher();
            else root.close();
        }
    }

    Connections {
        target: PillState
        function onOwnerChanged() {
            if (PillState.owner !== "applauncher" && root.visible) {
                if (PillState.owner !== "") root.giveWay();
                AppLauncherState.launcherVisible = false;
            }
        }
    }

    onVisibleChanged: {
        if (visible) searchInput.forceActiveFocus();
    }

    function activate(r, shiftPressed) {
        if (!r) return;

        if (r.kind === "app") {
            Sounds.play("launch");
            AppLauncherState.recordLaunch(r.entry.id);
            r.entry.execute();
        } else if (r.kind === "window") {
            Sounds.play("launch");
            if (shiftPressed && r.matchedApp) {
                AppLauncherState.recordLaunch(r.matchedApp.id);
                r.matchedApp.execute();
            } else if (r.window) {
                const ipc = r.window.lastIpcObject ?? {};
                const pid = ipc.pid ?? r.window.pid;
                if (pid) {
                    Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({ window = \"pid:" + pid + "\" })"]);
                } else {
                    const addr = String(r.window.address ?? "").replace(/^0x/, "");
                    Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({ window = \"address:" + addr + "\" })"]);
                }
            }
        } else if (r.kind === "calc") {
            if (r.value === "") return;
            Quickshell.execDetached(["wl-copy", "--", r.value]);
        } else {
            Sounds.play("launch");
            Quickshell.execDetached(["xdg-open", r.value]);
        }
        AppLauncherState.hide();
    }

    // keeps a found file or folder in the strip's tray
    function addToTray(r) {
        if (!r || r.kind !== "file" || ShareService.favorites.indexOf(r.value) >= 0) return;
        ShareService.addFavorites([ShareService.fileUrl(r.value)]);
        Sounds.play("done");
    }

    function reveal() {
        listView.positionViewAtIndex(selectedIndex, ListView.Contain);
    }

    function navigate(delta) {
        const next = Math.max(0, Math.min(results.length - 1, selectedIndex + delta));
        if (results.length === 0 || next === selectedIndex) return;

        selectedKey = results[next].key;
        Sounds.play("slide");
        reveal();
    }

    readonly property color accentFill: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18)

    Binding {
        target: Calc
        property: "expression"
        value: root.isMath ? root.query : ""
    }

    Binding {
        target: Files
        property: "query"
        value: root.query.length >= 2 ? root.query : ""
    }

    // only the card takes clicks: the bar's window masks its input to this while the launcher is open
    readonly property Item maskItem: outline

    Notch {
        id: outline
        bodyWidth: card.width
        bodyHeight: card.height
        x: card.x - bodyX
        y: card.y
    }

    Rectangle {
        id: card

        readonly property real fromW: root.startW
        readonly property real fromH: root.startH

        width: fromW + (root.panelW - fromW) * Math.max(0, root.t)
        height: fromH + (root.panelH - fromH) * Math.max(0, root.t)
        x: (root.width - width) / 2
        y: PillState.pillTop
        color: "transparent"
        clip: true

        Column {
            anchors {
                top: parent.top
                topMargin: 12
                left: parent.left
                leftMargin: 12
                right: parent.right
                rightMargin: 12
            }
            spacing: 8
            opacity: Math.max(0, (root.t - 0.5) * 2)

            Item {
                width: parent.width
                height: 34

                Text {
                    id: searchGlyph
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰍉"
                    color: Qt.alpha(Theme.fg, 0.45)
                    font.family: Theme.fontFamily
                    font.pixelSize: 15
                }

                TextInput {
                    id: searchInput
                    anchors.left: searchGlyph.right
                    anchors.leftMargin: 10
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.fg
                    selectionColor: root.accentFill
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    clip: true

                    onTextChanged: root.searchQuery = text

                    Keys.onPressed: function (event) {
                        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
                        const shift = (event.modifiers & Qt.ShiftModifier) !== 0;

                        if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) {
                            root.navigate(-1);
                        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
                            root.navigate(1);
                        } else if (ctrl && event.key === Qt.Key_D) {
                            root.navigate(root.maxVisible);
                        } else if (ctrl && event.key === Qt.Key_U) {
                            root.navigate(-root.maxVisible);
                        } else if (event.key === Qt.Key_Home) {
                            root.navigate(-root.results.length);
                        } else if (event.key === Qt.Key_End) {
                            root.navigate(root.results.length);
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            if (ctrl) root.addToTray(root.current);
                            else root.activate(root.current, shift);
                        } else if (event.key === Qt.Key_Escape) {
                            AppLauncherState.hide();
                        } else {
                            return;
                        }
                        event.accepted = true;
                    }
                }
            }

            ListView {
                id: listView
                visible: root.hasQuery
                width: parent.width
                height: Math.max(1, Math.min(root.results.length, root.maxVisible)) * root.itemH
                model: root.results
                clip: true
                interactive: false

                Text {
                    anchors.centerIn: parent
                    visible: root.results.length === 0
                    text: root.emptyText
                    color: Theme.fg
                    opacity: 0.28
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                }

                MouseArea {
                    anchors.fill: parent
                    onWheel: wheel => root.navigate(wheel.angleDelta.y < 0 ? 1 : -1)
                }

                delegate: Rectangle {
                    id: appRow
                    required property var modelData
                    required property int index

                    width: listView.width
                    height: root.itemH
                    radius: 10
                    readonly property bool sel: root.selectedIndex === index
                    color: sel ? root.accentFill : "transparent"
                    Behavior on color { ColorAnimation { duration: 100 } }
                    opacity: dragHandler.active ? 0.4 : 1
                    Behavior on opacity { NumberAnimation { duration: 100 } }

                    Row {
                        anchors {
                            left: parent.left
                            right: returnHint.left
                            verticalCenter: parent.verticalCenter
                            leftMargin: 10
                            rightMargin: 8
                        }
                        spacing: 12

                        Item {
                            width: 26
                            height: 26
                            anchors.verticalCenter: parent.verticalCenter

                            Image {
                                id: appIcon
                                anchors.fill: parent
                                source: appRow.modelData.icon && appRow.modelData.icon !== "" ? "image://icon/" + appRow.modelData.icon : ""
                                smooth: true
                                mipmap: true
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: appIcon.status !== Image.Ready
                                text: appRow.modelData.glyph !== "" ? appRow.modelData.glyph : appRow.modelData.title.charAt(0).toUpperCase()
                                font.family: Theme.fontFamily
                                font.pixelSize: appRow.modelData.glyph !== "" ? 17 : 14
                                font.weight: appRow.modelData.glyph !== "" ? Font.Normal : Font.Bold
                                color: appRow.sel ? Theme.primary : Theme.fg
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 26 - parent.spacing
                            spacing: 2

                            Text {
                                width: parent.width
                                text: appRow.modelData.title
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.weight: appRow.sel ? Font.Medium : Font.Normal
                                color: Theme.fg
                                opacity: appRow.sel ? 1 : 0.8
                            }

                            Text {
                                width: parent.width
                                visible: text !== ""
                                text: appRow.modelData.subtitle
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                color: Theme.fg
                                opacity: 0.35
                            }
                        }
                    }

                    Text {
                        id: returnHint
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: "↵"
                        visible: appRow.sel
                        color: Theme.fg
                        opacity: 0.7
                        font.family: Theme.fontFamilyAlt
                        font.pixelSize: 12
                    }

                    DragHandler {
                        id: dragHandler
                        enabled: appRow.modelData.kind === "file"
                        target: null
                    }

                    Drag.active: dragHandler.active
                    Drag.dragType: Drag.Automatic
                    Drag.supportedActions: Qt.CopyAction
                    Drag.mimeData: appRow.modelData.kind === "file"
                        ? ({ "text/uri-list": ShareService.fileUrl(appRow.modelData.value) + "\r\n" })
                        : ({})
                    Drag.hotSpot.x: dragHandler.centroid.position.x
                    Drag.hotSpot.y: dragHandler.centroid.position.y

                    HoverHandler {
                        onPointChanged: {
                            if (!hovered) return;
                            const p = point.scenePosition;
                            const last = root.pointer;
                            root.pointer = Qt.point(p.x, p.y);
                            if (last !== null && (last.x !== p.x || last.y !== p.y))
                                root.selectedKey = appRow.modelData.key;
                        }
                    }

                    TapHandler {
                        onTapped: root.activate(appRow.modelData, false)
                    }
                }
            }

            Text {
                visible: root.hasQuery
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.hintText
                color: Theme.fg
                opacity: 0.25
                font.family: Theme.fontFamilyAlt
                font.pixelSize: 10
            }
        }
    }
}
