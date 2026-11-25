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
// choice is written to layout.json. Another shown widget acts as a barrier: the
// outline stops at its edge and can still slide along it. A drop that would
// still cover one is refused: the preview turns red and the widget goes back. A
// dot grid marks the cell edges a widget can land on. Nothing is
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

        // a dot where each cell edge can fall: a box's left or top edge in the
        // left or top half of the screen, its right or bottom edge in the other
        // half. The same positions the snap uses, so the dots show where a widget
        // can land.
        Canvas {
            id: gridDots
            anchors.fill: parent
            visible: root.editing

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onVisibleChanged: if (visible) requestPaint()

            onPaint: {
                const ctx = getContext("2d")
                const cell = WidgetLayout.cell
                const inset = Theme.edgeInset
                const xs = [], ys = []
                for (let x = inset; x < width / 2; x += cell) xs.push(x)
                for (let x = width - inset; x >= width / 2; x -= cell) xs.push(x)
                for (let y = inset; y < height / 2; y += cell) ys.push(y)
                for (let y = height - inset; y >= height / 2; y -= cell) ys.push(y)
                ctx.reset()
                ctx.fillStyle = String(Qt.alpha(Theme.fg, 0.3))
                for (const x of xs)
                    for (const y of ys)
                        ctx.fillRect(x - 1, y - 1, 2, 2)
            }
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
                // from it, never past the opposite edge. Where the nearest cell
                // would cover a widget, the nearest free cell around it is used
                function snap(px, py) {
                    const cell = WidgetLayout.cell
                    const inset = Theme.edgeInset
                    const left = px + w / 2 < root.width / 2
                    const top = py + h / 2 < root.height / 2
                    const maxX = Math.max(0, Math.floor((root.width - w - 2 * inset) / cell))
                    const maxY = Math.max(0, Math.floor((root.height - h - 2 * inset) / cell))
                    const gx = left ? px - inset : root.width - px - w - inset
                    const gy = top ? py - inset : root.height - py - h - inset
                    const anchorName = (top ? "top" : "bottom") + "-" + (left ? "left" : "right")
                    const clampX = v => Math.min(maxX, Math.max(0, v))
                    const clampY = v => Math.min(maxY, Math.max(0, v))
                    // the four whole cells around the drop point, nearest first
                    const cands = []
                    for (const cx of [clampX(Math.floor(gx / cell)), clampX(Math.ceil(gx / cell))])
                        for (const cy of [clampY(Math.floor(gy / cell)), clampY(Math.ceil(gy / cell))])
                            cands.push({ x: cx, y: cy, d: Math.abs(cx * cell - gx) + Math.abs(cy * cell - gy) })
                    cands.sort((a, b) => a.d - b.d)
                    const fits = c => {
                        const b = root.boxAt(anchorName, c.x, c.y, w, h)
                        return !root.overlapsOther(modelData, b.x, b.y, w, h)
                    }
                    const c = cands.find(fits) ?? { x: clampX(Math.round(gx / cell)), y: clampY(Math.round(gy / cell)) }
                    const b = root.boxAt(anchorName, c.x, c.y, w, h)
                    return { anchor: anchorName, x: c.x, y: c.y, px: b.x, py: b.y }
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
                            const nx = Math.max(-slot.homeX, Math.min(root.width - slot.w - slot.homeX, p.x - startX))
                            const ny = Math.max(-slot.homeY, Math.min(root.height - slot.h - slot.homeY, p.y - startY))
                            const id = slot.modelData
                            // a widget that already covers another is free to move out of it
                            if (root.overlapsOther(id, slot.homeX + slot.dx, slot.homeY + slot.dy, slot.w, slot.h)) {
                                slot.dx = nx
                                slot.dy = ny
                                return
                            }
                            // barrier: an axis that would cover a widget stops where it was, so
                            // the other axis can still slide along the edge
                            slot.dx = root.overlapsOther(id, slot.homeX + nx, slot.homeY + slot.dy, slot.w, slot.h) ? slot.dx : nx
                            slot.dy = root.overlapsOther(id, slot.homeX + slot.dx, slot.homeY + ny, slot.w, slot.h) ? slot.dy : ny
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
