import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "../../services"
import "../notch"

// Clipboard history. Morphs out of the bar pill like the app launcher and
// toggles with `qs ipc call clipboard toggle`. Enter copies the entry and
// closes; Ctrl+Delete forgets it. Plain Delete still edits the search text.
PanelWindow {
    id: root

    screen: PillState.originScreen
    visible: false

    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: PillState.pillTop + maxPanelH + 12

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "quickshell-clipboard"

    IpcHandler {
        target: "clipboard"
        function toggle(): void { ClipboardHistory.toggle() }
    }

    // ── Geometry ───────────────────────────────────────────────────────────
    readonly property int maxVisible: 8
    // one row slot is a row plus the gap under it
    readonly property int itemH: 38
    readonly property int panelW: 380
    // 12 top + 34 search + 8 gap + 12 bottom, plus the rows
    readonly property int chromeH: 66
    readonly property int maxPanelH: chromeH + maxVisible * itemH

    // 0 = the bar pill, 1 = the full panel
    property real t: 0

    property real panelH: chromeH + Math.max(1, Math.min(shown.length, maxVisible)) * itemH
    Behavior on panelH {
        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
    }

    // ── State ──────────────────────────────────────────────────────────────
    property string searchQuery: ""
    property int selectedIndex: 0

    readonly property var shown: {
        const q = searchQuery.trim().toLowerCase()
        const all = ClipboardHistory.entries
        return q === "" ? all : all.filter(e => e.preview.toLowerCase().indexOf(q) !== -1)
    }

    onShownChanged: selectedIndex = 0

    readonly property color accentFill: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18)

    // ── Open / close ───────────────────────────────────────────────────────
    function openPanel() {
        PillState.owner = "clipboard"
        searchInput.text = ""
        ClipboardHistory.reload()
        visible = true
        morph.stop()
        morph.from = root.t
        morph.to = 1
        morph.start()
    }

    function closePanel() {
        morph.stop()
        morph.from = root.t
        morph.to = 0
        morph.start()
    }

    NumberAnimation {
        id: morph
        target: root
        property: "t"
        duration: 480
        easing.type: Easing.InOutCubic
        onFinished: {
            if (root.t < 0.5) {
                root.visible = false
                if (PillState.owner === "clipboard")
                    PillState.owner = ""
            }
        }
    }

    Connections {
        target: ClipboardHistory
        function onOpenChanged() {
            if (ClipboardHistory.open)
                root.openPanel()
            else
                root.closePanel()
        }
    }

    // another panel took the pill, so this one gives way
    Connections {
        target: PillState
        function onOwnerChanged() {
            if (PillState.owner !== "clipboard" && root.visible)
                ClipboardHistory.hide()
        }
    }

    onVisibleChanged: {
        if (visible)
            searchInput.forceActiveFocus()
    }

    // ── Actions ────────────────────────────────────────────────────────────
    function copyEntry(entry) {
        if (!entry)
            return
        ClipboardHistory.copy(entry)
        ClipboardHistory.hide()
    }

    function forgetEntry(entry) {
        if (!entry)
            return
        ClipboardHistory.remove(entry)
    }

    function navigate(delta) {
        if (shown.length === 0)
            return
        selectedIndex = (selectedIndex + delta + shown.length) % shown.length
        listView.positionViewAtIndex(selectedIndex, ListView.Contain)
    }

    // only the card takes clicks; everything around it passes through
    mask: Region { item: outline }

    // ── Card ───────────────────────────────────────────────────────────────
    // the outline is a notch, drawn behind the card and sized to it
    Notch {
        id: outline
        bodyWidth: card.width
        bodyHeight: card.height
        x: card.x - bodyX
        y: card.y
    }

    Rectangle {
        id: card

        readonly property real fromW: PillState.pillWidth
        readonly property real fromH: PillState.pillHeight

        width: fromW + (root.panelW - fromW) * root.t
        height: fromH + (root.panelH - fromH) * root.t
        x: (root.width - width) / 2
        y: PillState.pillTop
        color: "transparent"
        clip: true

        // content fades in during the second half of the morph
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

            // ── Search line, with the match count on the right ─────────────
            Item {
                width: parent.width
                height: 34

                Text {
                    anchors.left: parent.left
                    anchors.right: countText.left
                    anchors.leftMargin: 14
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Search clipboard"
                    color: Theme.fg
                    opacity: 0.28
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    elide: Text.ElideRight
                    visible: searchInput.text === ""
                }

                TextInput {
                    id: searchInput
                    anchors.left: parent.left
                    anchors.right: countText.left
                    anchors.leftMargin: 14
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.fg
                    selectionColor: root.accentFill
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    clip: true

                    onTextChanged: root.searchQuery = text

                    Keys.onPressed: function (event) {
                        if (event.key === Qt.Key_Up) {
                            root.navigate(-1)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Down) {
                            root.navigate(1)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Tab) {
                            root.navigate(1)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Backtab) {
                            root.navigate(-1)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            root.copyEntry(root.shown[root.selectedIndex])
                            event.accepted = true
                        } else if (event.key === Qt.Key_Delete && (event.modifiers & Qt.ControlModifier)) {
                            root.forgetEntry(root.shown[root.selectedIndex])
                            event.accepted = true
                        } else if (event.key === Qt.Key_Escape) {
                            ClipboardHistory.hide()
                            event.accepted = true
                        }
                    }
                }

                Text {
                    id: countText
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.shown.length + " / " + ClipboardHistory.entries.length
                    color: Theme.fg
                    opacity: 0.35
                    font.family: Theme.fontFamilyAlt
                    font.pixelSize: 11
                }
            }

            // ── History rows ───────────────────────────────────────────────
            ListView {
                id: listView
                width: parent.width
                height: Math.max(1, Math.min(root.shown.length, root.maxVisible)) * root.itemH
                model: root.shown
                clip: true
                spacing: 4
                boundsBehavior: Flickable.StopAtBounds

                Text {
                    anchors.centerIn: parent
                    visible: root.shown.length === 0
                    text: ClipboardHistory.entries.length === 0 ? "Nothing copied yet" : "No matches"
                    color: Theme.fg
                    opacity: 0.28
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                }

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    width: listView.width
                    height: root.itemH - 4
                    radius: 8
                    color: Theme.bg

                    // selection highlight, a separate layer so the row base stays solid
                    Rectangle {
                        anchors.fill: parent
                        radius: 8
                        visible: root.selectedIndex === index
                        color: Qt.alpha(Theme.fg, 0.2)
                    }

                    Text {
                        id: preview
                        anchors.left: parent.left
                        anchors.right: hint.left
                        anchors.leftMargin: 12
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.preview
                        elide: Text.ElideRight
                        color: Theme.fg
                        // unselected entries are faded so the highlighted one reads first
                        opacity: root.selectedIndex === index ? 1 : 0.5
                        Behavior on opacity { NumberAnimation { duration: 120 } }
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }

                    // return hint on the selected row
                    Text {
                        id: hint
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: "↵"
                        visible: root.selectedIndex === index
                        color: Theme.fg
                        opacity: 0.5
                        font.family: Theme.fontFamilyAlt
                        font.pixelSize: 12
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: root.selectedIndex = index
                        onClicked: root.copyEntry(row.modelData)
                    }
                }
            }
        }
    }
}
