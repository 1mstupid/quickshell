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
// choice is written to layout.json. Nothing is written until a drop or a
// button press. Done or Escape (after a click, since the panel takes keyboard
// focus on demand) leaves.
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

                readonly property real homeX: WidgetLayout.hasLeft(modelData)
                    ? WidgetLayout.insetX(modelData)
                    : WidgetLayout.hasCenter(modelData)
                        ? (root.width - w) / 2
                        : root.width - w - WidgetLayout.insetX(modelData)
                readonly property real homeY: WidgetLayout.hasTop(modelData)
                    ? WidgetLayout.insetY(modelData)
                    : root.height - h - WidgetLayout.insetY(modelData)

                // how far the outline is dragged from home
                property real dx: 0
                property real dy: 0

                readonly property bool dragging: pointer.pressed
                readonly property var landing: dragging ? snap(frame.x, frame.y) : null

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
                    border.color: Qt.alpha(Theme.fg, 0.35)
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
                            // a click that moved nothing writes nothing
                            const id = slot.modelData
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
