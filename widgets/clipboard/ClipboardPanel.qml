import QtQuick
import Quickshell.Io
import "../../services"
import "../notch"

// Clipboard history. It grows out of the bar pill like the app launcher, as an item of the
// origin bar's window (Bar.qml), and toggles with `qs ipc call clipboard toggle`. Enter copies
// the entry and closes; Ctrl+Delete forgets it. Plain Delete still edits the search text.
Item {
    id: root

    visible: false
    anchors.fill: parent

    IpcHandler {
        target: "clipboard"
        function toggle(): void { ClipboardHistory.toggle() }
    }

    // ── Geometry ───────────────────────────────────────────────────────────
    readonly property int maxVisible: 8
    readonly property int itemH: 38
    readonly property int panelW: 400
    // 12 top + 34 search + 8 gap + 8 gap + 14 hint + 14 bottom, plus the rows
    readonly property int chromeH: 90

    property real startW: PillState.pillWidth
    property real startH: PillState.pillHeight
    property real t: 0
    // a card closed back to the pill is hidden there: the elastic close reaches the pill early, and
    // a card left over it hid the bar's content until the morph finished
    onTChanged: if (morph.running && morph.to === 0 && t <= 0) visible = false

    property real panelH: chromeH + Math.max(1, Math.min(shown.length, maxVisible)) * itemH
    Behavior on panelH {
        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
    }

    // ── State ──────────────────────────────────────────────────────────────
    property string searchQuery: ""
    property int selectedIndex: 0
    // where the pointer was last seen: rows that appear under a still pointer do not take the
    // selection, only a pointer that moves does
    property var pointer: null

    readonly property var shown: {
        const q = searchQuery.trim().toLowerCase()
        const all = ClipboardHistory.entries
        return q === "" ? all : all.filter(e => e.preview.toLowerCase().indexOf(q) !== -1)
    }

    // a new search starts at the top; a forgotten or newly read entry keeps the place
    onSearchQueryChanged: selectedIndex = 0
    onShownChanged: {
        selectedIndex = Math.max(0, Math.min(selectedIndex, shown.length - 1))
        Qt.callLater(reveal)
    }

    readonly property color accentFill: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18)

    // ── Open / close ───────────────────────────────────────────────────────
    function openPanel() {
        if (!PillState.claim("clipboard")) return
        Sounds.play("open")
        const from = PillState.takeOver()
        startW = from.w
        startH = from.h
        searchInput.text = ""
        selectedIndex = 0
        pointer = null
        ClipboardHistory.reload()
        visible = true
        morph.stop()
        morph.from = root.t
        morph.to = 1
        morph.start()
    }

    function giveWay() {
        PillState.takeoverW = card.width
        PillState.takeoverH = card.height
        morph.stop()
        visible = false
        t = 0
    }

    function close() {
        if (!visible) return
        Sounds.play("close")
        if (PillState.owner === "clipboard")
            PillState.returning = true
        startW = PillState.pillWidth
        startH = PillState.pillHeight
        morph.stop()
        morph.from = root.t
        morph.to = 0
        morph.start()
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
                root.visible = false
                if (PillState.owner === "clipboard") PillState.owner = ""
            }
        }
    }

    Connections {
        target: ClipboardHistory
        function onOpenChanged() {
            if (ClipboardHistory.open) root.openPanel()
            else root.close()
        }
    }

    // another panel took the pill, so this one gives way
    Connections {
        target: PillState
        function onOwnerChanged() {
            if (PillState.owner !== "clipboard" && root.visible) {
                if (PillState.owner !== "") root.giveWay()
                ClipboardHistory.hide()
            }
        }
    }

    onVisibleChanged: {
        if (visible) searchInput.forceActiveFocus()
    }

    // ── Actions ────────────────────────────────────────────────────────────
    function copyEntry(entry) {
        if (!entry) return
        ClipboardHistory.copy(entry)
        ClipboardHistory.hide()
    }

    function forgetEntry(entry) {
        if (entry) ClipboardHistory.remove(entry)
    }

    function reveal() {
        listView.positionViewAtIndex(selectedIndex, ListView.Contain)
    }

    function navigate(delta) {
        const next = Math.max(0, Math.min(shown.length - 1, selectedIndex + delta))
        if (shown.length === 0 || next === selectedIndex) return
        selectedIndex = next
        Sounds.play("slide")
        reveal()
    }

    // only the card takes clicks: the bar's window masks its input to this while the panel is open
    readonly property Item maskItem: outline

    // ── Card ───────────────────────────────────────────────────────────────
    Notch {
        id: outline
        bodyWidth: card.width
        bodyHeight: card.height
        x: card.x - bodyX
        y: card.y
    }

    Rectangle {
        id: card

        width: root.startW + (root.panelW - root.startW) * Math.max(0, root.t)
        height: root.startH + (root.panelH - root.startH) * Math.max(0, root.t)
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
                    id: searchGlyph
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰅍"
                    color: Theme.primary
                    font.family: Theme.fontFamily
                    font.pixelSize: 15
                }

                TextInput {
                    id: searchInput
                    anchors.left: searchGlyph.right
                    anchors.leftMargin: 10
                    anchors.right: countText.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.fg
                    selectionColor: root.accentFill
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    clip: true

                    onTextChanged: root.searchQuery = text

                    Keys.onPressed: function (event) {
                        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0

                        if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) {
                            root.navigate(-1)
                        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
                            root.navigate(1)
                        } else if (ctrl && event.key === Qt.Key_U) {
                            root.navigate(-root.maxVisible)
                        } else if (ctrl && event.key === Qt.Key_D) {
                            root.navigate(root.maxVisible)
                        } else if (event.key === Qt.Key_Home) {
                            root.navigate(-root.shown.length)
                        } else if (event.key === Qt.Key_End) {
                            root.navigate(root.shown.length)
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            root.copyEntry(root.shown[root.selectedIndex])
                        } else if (ctrl && event.key === Qt.Key_Delete) {
                            root.forgetEntry(root.shown[root.selectedIndex])
                        } else if (event.key === Qt.Key_Escape) {
                            ClipboardHistory.hide()
                        } else {
                            return
                        }
                        event.accepted = true
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
                interactive: false

                Text {
                    anchors.centerIn: parent
                    visible: root.shown.length === 0
                    text: ClipboardHistory.entries.length === 0 ? "Nothing copied yet" : "No matches"
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
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool sel: root.selectedIndex === row.index

                    width: listView.width
                    height: root.itemH
                    radius: 10
                    color: sel ? root.accentFill : "transparent"
                    Behavior on color { ColorAnimation { duration: 100 } }

                    Text {
                        anchors.left: parent.left
                        anchors.right: hint.left
                        anchors.leftMargin: 12
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.preview
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        color: Theme.fg
                        opacity: row.sel ? 1 : 0.8
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                    }

                    Text {
                        id: hint
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: "↵"
                        visible: row.sel
                        color: Theme.fg
                        opacity: 0.7
                        font.family: Theme.fontFamilyAlt
                        font.pixelSize: 12
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onPositionChanged: mouse => {
                            const p = mapToItem(null, mouse.x, mouse.y)
                            const last = root.pointer
                            root.pointer = p
                            if (last !== null && (last.x !== p.x || last.y !== p.y))
                                root.selectedIndex = row.index
                        }
                        onClicked: root.copyEntry(row.modelData)
                    }
                }
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: "↵ copy    ^⌫ delete    esc close"
                color: Theme.fg
                opacity: 0.25
                font.family: Theme.fontFamilyAlt
                font.pixelSize: 10
            }
        }
    }
}
