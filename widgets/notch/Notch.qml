import QtQuick
import "../../services"

// Notch outline: flat top flush with the screen edge, rounded bottom corners,
// and optional concave shoulders that flare out to the sides. The body is
// bodyWidth x bodyHeight. A shoulder adds to the width on its side, so the
// body starts at x = bodyX. Content should be placed inside the body.
// With the `pill` setting it is a pill instead: all four corners round and no
// shoulders, for a bar that floats clear of the screen edge (see Bar.topGap).
Canvas {
    id: notch

    property real bodyWidth: 0
    property real bodyHeight: 0
    property real shoulder: 10
    property real corner: 12
    property bool leftShoulder: true
    property bool rightShoulder: true
    // square bottom-right corner, for a notch flush with the right screen edge
    property bool bottomRightSquare: false
    property color fillColor: Theme.bg

    readonly property bool asPill: UserSettings.pill
    // a pill has no shoulders, so its body starts at x = 0
    readonly property real bodyX: leftShoulder && !asPill ? shoulder : 0

    width: bodyWidth + bodyX + (rightShoulder && !asPill ? shoulder : 0)
    height: bodyHeight

    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onFillColorChanged: requestPaint()
    onAsPillChanged: requestPaint()
    // a panel can animate its corner while it morphs
    onCornerChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d")
        const w = bodyWidth, h = bodyHeight
        const s = shoulder, r = corner
        ctx.reset()
        ctx.translate(bodyX, 0)
        ctx.beginPath()
        if (asPill) {
            // the radius cannot pass half the shorter side, or a small pill would fold over itself
            const q = Math.min(r, w / 2, h / 2)
            ctx.moveTo(q, 0)
            ctx.lineTo(w - q, 0)
            ctx.quadraticCurveTo(w, 0, w, q)
            ctx.lineTo(w, h - q)
            ctx.quadraticCurveTo(w, h, w - q, h)
            ctx.lineTo(q, h)
            ctx.quadraticCurveTo(0, h, 0, h - q)
            ctx.lineTo(0, q)
            ctx.quadraticCurveTo(0, 0, q, 0)
            ctx.closePath()
            ctx.fillStyle = String(fillColor)
            ctx.fill()
            return
        }
        ctx.moveTo(leftShoulder ? -s : 0, 0)
        ctx.lineTo(rightShoulder ? w + s : w, 0)
        if (rightShoulder)
            ctx.quadraticCurveTo(w, 0, w, s)
        ctx.lineTo(w, h - r)
        if (bottomRightSquare)
            ctx.lineTo(w, h)
        else
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
