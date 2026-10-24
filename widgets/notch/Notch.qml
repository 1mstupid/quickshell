import QtQuick
import "../../services"

// Notch outline: flat top flush with the screen edge, rounded bottom corners,
// and optional concave shoulders that flare out to the sides. The body is
// bodyWidth x bodyHeight. A shoulder adds to the width on its side, so the
// body starts at x = bodyX. Content should be placed inside the body.
Canvas {
    id: notch

    property real bodyWidth: 0
    property real bodyHeight: 0
    property real shoulder: 10
    property real corner: 12
    property bool leftShoulder: true
    property bool rightShoulder: true
    property color fillColor: Theme.bg

    readonly property real bodyX: leftShoulder ? shoulder : 0

    width: bodyWidth + bodyX + (rightShoulder ? shoulder : 0)
    height: bodyHeight

    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onFillColorChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d")
        const w = bodyWidth, h = bodyHeight
        const s = shoulder, r = corner
        ctx.reset()
        ctx.translate(bodyX, 0)
        ctx.beginPath()
        ctx.moveTo(leftShoulder ? -s : 0, 0)
        ctx.lineTo(rightShoulder ? w + s : w, 0)
        if (rightShoulder)
            ctx.quadraticCurveTo(w, 0, w, s)
        ctx.lineTo(w, h - r)
        ctx.quadraticCurveTo(w, h, w - r, h)
        ctx.lineTo(r, h)
        ctx.quadraticCurveTo(0, h, 0, h - r)
        if (leftShoulder) {
            ctx.lineTo(0, s)
            ctx.quadraticCurveTo(0, 0, -s, 0)
        }
        ctx.closePath()
        ctx.fillStyle = String(fillColor)
        ctx.fill()
    }
}
