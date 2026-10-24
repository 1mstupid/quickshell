import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../services"

// Rounded frame around one screen, in the bar's background colour. The
// corners outside the rounded inner edge are filled too, so the frame reads
// as one bezel. Hidden while the overview is open. Clicks pass through.
PanelWindow {
    id: root

    property var modelData
    screen: modelData

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-border"
    visible: !Overview.open
    mask: Region {}

    Canvas {
        id: frame
        anchors.fill: parent

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Connections {
            target: Theme
            function onBgChanged() { frame.requestPaint() }
        }

        onPaint: {
            const ctx = getContext("2d")
            const inset = 2, r = 12
            const x = inset, y = inset
            const W = width - 2 * inset, H = height - 2 * inset
            ctx.reset()
            ctx.fillStyle = String(Theme.bg)
            ctx.fillRect(0, 0, width, height)
            // cut the inner rounded window out of the fill
            ctx.globalCompositeOperation = "destination-out"
            ctx.beginPath()
            ctx.moveTo(x + r, y)
            ctx.lineTo(x + W - r, y)
            ctx.arcTo(x + W, y, x + W, y + r, r)
            ctx.lineTo(x + W, y + H - r)
            ctx.arcTo(x + W, y + H, x + W - r, y + H, r)
            ctx.lineTo(x + r, y + H)
            ctx.arcTo(x, y + H, x, y + H - r, r)
            ctx.lineTo(x, y + r)
            ctx.arcTo(x, y, x + r, y, r)
            ctx.closePath()
            ctx.fill()
            ctx.globalCompositeOperation = "source-over"
        }
    }
}
