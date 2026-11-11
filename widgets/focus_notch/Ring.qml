import QtQuick
import "../../services"

// A small round progress ring with a label in the middle. Used by the strip and the panel's cards.
Item {
    id: ring

    property real fraction: 0
    property string label: ""
    property color tint: Theme.accent
    property int size: 48

    implicitWidth: size
    implicitHeight: size

    onFractionChanged: canvas.requestPaint()
    onTintChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d")
            const c = width / 2
            const r = c - 2.5
            ctx.reset()
            ctx.lineWidth = 3
            ctx.lineCap = "round"

            ctx.strokeStyle = String(Qt.alpha(Theme.fg, 0.15))
            ctx.beginPath()
            ctx.arc(c, c, r, 0, 2 * Math.PI)
            ctx.stroke()

            if (ring.fraction > 0) {
                ctx.strokeStyle = String(ring.tint)
                ctx.beginPath()
                ctx.arc(c, c, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * ring.fraction)
                ctx.stroke()
            }
        }
    }

    Text {
        anchors.centerIn: parent
        text: ring.label
        color: Theme.fg
        font.family: Theme.fontFamilyNum
        font.pixelSize: Math.round(ring.size * 0.34)
        font.bold: true
    }
}
