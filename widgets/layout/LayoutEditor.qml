import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../services"

// Edit mode for the corner widgets: `qs ipc call layout toggle`. The screen
// dims, each showing widget gets an outline to drag, and a small bar at the
// bottom holds a glyph button per widget to switch it on or off. While you
// drag, only the outline moves and a second one shows the cell it will land
// in; on release the widget goes to the nearest corner at that offset, and the
// choice is written to layout.json. A drop that would cover another shown
// widget is refused: the preview turns red and the widget goes back. Nothing is
// written until a drop or a button press. Done or Escape (after a click, since
// the panel takes keyboard focus on demand) leaves.
PanelWindow {
    id: root

    property bool editing: false

    screen: PillState.originScreen
    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-layout"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    visible: editing

    IpcHandler {
        target: "layout"
        function toggle(): void { root.editing = !root.editing }
    }

    // where a w x h box sits for an anchor and cell offset, as the compositor
    // places it. The outlines and the overlap check both use it, so they agree.
    function boxAt(anchorName, cx, cy, w, h) {
        const inset = Theme.edgeInset
        const cell = WidgetLayout.cell
        const left = anchorName.endsWith("left")
        const top = anchorName.startsWith("top")
        const center = anchorName === "bottom-center"
        return {
            x: left ? inset + cx * cell : center ? (root.width - w) / 2 : root.width - w - inset - cx * cell,
            y: top ? inset + cy * cell : root.height - h - inset - cy * cell
        }
    }

    // whether a box at (x, y) would cover a shown widget other than `id`
    function overlapsOther(id, x, y, w, h) {
        for (const other of Object.keys(WidgetLayout.defaults)) {
            const win = WidgetLayout.windows[other]
            if (other === id || !win || !WidgetLayout.shown(other))
                continue
            const b = boxAt(WidgetLayout.anchor(other), WidgetLayout.cells(other, "x"),
                WidgetLayout.cells(other, "y"), win.implicitWidth, win.implicitHeight)
            if (x < b.x + win.implicitWidth && b.x < x + w && y < b.y + win.implicitHeight && b.y < y + h)
                return true
        }
        return false
    }

    Item {
        id: scene
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: root.editing = false

        Rectangle {
            anchors.fill: parent
            color: Qt.alpha(Theme.bg, 0.55)

            // swallows clicks, so nothing underneath is hit while editing
            MouseArea { anchors.fill: parent }
        }

        Repeater {
            model: Object.keys(WidgetLayout.defaults)

            Item {
                id: slot

                required property string modelData

                readonly property var win: WidgetLayout.windows[modelData] ? WidgetLayout.windows[modelData] : null
                // a widget with nothing to show (no apps yet) has no outline
                readonly property bool present: win !== null && win.visible
                readonly property real w: win ? win.implicitWidth : 0
                readonly property real h: win ? win.implicitHeight : 0

                readonly property var home: root.boxAt(WidgetLayout.anchor(modelData),
                    WidgetLayout.cells(modelData, "x"), WidgetLayout.cells(modelData, "y"), w, h)
                readonly property real homeX: home.x
                readonly property real homeY: home.y

                // how far the outline is dragged from home
                property real dx: 0
                property real dy: 0

                readonly property bool dragging: pointer.pressed
                readonly property var landing: dragging ? snap(frame.x, frame.y) : null
                readonly property bool blocked: landing !== null
                    && root.overlapsOther(modelData, landing.px, landing.py, w, h)

                // nearest corner for a top-left position, then whole cells in
                // from it, never past the opposite edge
                function snap(px, py) {
                    const cell = WidgetLayout.cell
                    const inset = Theme.edgeInset
                    const left = px + w / 2 < root.width / 2
                    const top = py + h / 2 < root.height / 2
                    const maxX = Math.max(0, Math.floor((root.width - w - 2 * inset) / cell))
                    const maxY = Math.max(0, Math.floor((root.height - h - 2 * inset) / cell))
                    const gx = left ? px - inset : root.width - px - w - inset
                    const gy = top ? py - inset : root.height - py - h - inset
                    const cx = Math.min(maxX, Math.max(0, Math.round(gx / cell)))
                    const cy = Math.min(maxY, Math.max(0, Math.round(gy / cell)))
                    return {
                        anchor: (top ? "top" : "bottom") + "-" + (left ? "left" : "right"),
                        x: cx,
                        y: cy,
                        px: left ? inset + cx * cell : root.width - w - inset - cx * cell,
                        py: top ? inset + cy * cell : root.height - h - inset - cy * cell
                    }
                }

                Rectangle {
                    visible: slot.present && slot.dragging
                    x: slot.landing ? slot.landing.px : 0
                    y: slot.landing ? slot.landing.py : 0
                    width: slot.w
                    height: slot.h
                    radius: 12
                    color: "transparent"
                    border.width: 1
                    border.color: slot.blocked ? Theme.alert : Qt.alpha(Theme.fg, 0.35)
                }

                Rectangle {
                    id: frame

                    visible: slot.present
                    x: slot.homeX + slot.dx
                    y: slot.homeY + slot.dy
                    width: slot.w
                    height: slot.h
                    radius: 12
                    color: Qt.alpha(Theme.accent, slot.dragging ? 0.14 : 0.05)
                    border.width: 1
                    border.color: Theme.accent

                    MouseArea {
                        id: pointer

                        property real startX
                        property real startY

                        anchors.fill: parent
                        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor

                        onPressed: m => {
                            const p = mapToItem(scene, m.x, m.y)
                            startX = p.x
                            startY = p.y
                        }
                        onPositionChanged: m => {
                            if (!pressed)
                                return
                            const p = mapToItem(scene, m.x, m.y)
                            slot.dx = Math.max(-slot.homeX, Math.min(root.width - slot.w - slot.homeX, p.x - startX))
                            slot.dy = Math.max(-slot.homeY, Math.min(root.height - slot.h - slot.homeY, p.y - startY))
                        }
                        onReleased: {
                            const t = slot.snap(frame.x, frame.y)
                            slot.dx = 0
                            slot.dy = 0
                            const id = slot.modelData
                            // a drop onto another widget is refused, so it goes back home
                            if (root.overlapsOther(id, t.px, t.py, slot.w, slot.h))
                                return
                            // a click that moved nothing writes nothing
                            if (t.anchor !== WidgetLayout.anchor(id)
                                    || t.x !== WidgetLayout.cells(id, "x")
                                    || t.y !== WidgetLayout.cells(id, "y"))
                                WidgetLayout.place(id, t.anchor, t.x, t.y)
                        }
                        onCanceled: {
                            slot.dx = 0
                            slot.dy = 0
                        }
                    }
                }
            }
        }

        Rectangle {
            id: bar

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 24
            width: row.implicitWidth + 2 * 16
            height: 44
            radius: 12
            color: Qt.alpha(Theme.bg, 0.92)
            border.width: 1
            border.color: Qt.alpha(Theme.border, 0.6)

            Row {
                id: row
                anchors.centerIn: parent
                spacing: 8

                Repeater {
                    model: Object.keys(WidgetLayout.defaults)

                    WidgetGlyph {
                        required property string modelData

                        anchors.verticalCenter: parent.verticalCenter
                        glyph: WidgetLayout.glyphs[modelData] ?? ""
                        label: modelData
                        checked: WidgetLayout.shown(modelData)
                        onToggled: WidgetLayout.toggle(modelData)
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "done"
                    color: doneArea.containsMouse ? Theme.accent : Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.bold: true

                    MouseArea {
                        id: doneArea
                        anchors.fill: parent
                        anchors.margins: -8
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.editing = false
                    }
                }
            }
        }
    }
}
