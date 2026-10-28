import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../services"

// Today's app time on the wallpaper layer: above the wallpaper, below every
// window. A ring shows each app's share of today's total, with the four most
// used apps and "other" for the rest. Hovering an arc or a legend row
// highlights both and shows that share in the centre.
PanelWindow {
    id: root

    screen: PillState.originScreen
    anchors {
        right: true
        bottom: true
    }
    margins {
        right: Theme.edgeInset
        bottom: Theme.edgeInset
    }
    implicitWidth: 240
    implicitHeight: card.height

    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "quickshell-usage"
    // only the card takes pointer events, so the ring can be hovered;
    // the rest of the wallpaper stays clickable
    mask: Region { item: card }

    // passing AppUsage.revision makes this re-evaluate when the numbers change
    readonly property var allRows: AppUsage.totals(AppUsage.dayKey(), AppUsage.revision)
    readonly property real totalSec: allRows.reduce((s, r) => s + r.sec, 0)

    // the ring's segments: top four apps, then "other" for the rest
    readonly property var segs: {
        const out = allRows.slice(0, 4).map(r => ({ name: r.app, sec: r.sec }))
        const rest = allRows.slice(4).reduce((s, r) => s + r.sec, 0)
        if (rest > 0)
            out.push({ name: "other", sec: rest })
        return out
    }

    readonly property int ringSize: 150
    readonly property int ringLw: 12
    readonly property real ringR: ringSize / 2 - ringLw / 2 - 2

    // index of the hovered segment, or -1
    property int hovered: -1

    // hidden while the overview is open, or when switched off
    visible: AppUsage.widgetShown && !Overview.open && allRows.length > 0

    function sweepOf(i) {
        return segs[i].sec / Math.max(totalSec, 1) * 2 * Math.PI
    }

    function colorOf(i) {
        if (segs[i].name === "other")
            return Qt.alpha(Theme.fg, 0.25)
        return Qt.alpha(Theme.accent, Math.max(0.35, 1 - i * 0.2))
    }

    // the segment under a point in the ring box, or -1 off the arc
    function arcAt(x, y) {
        const dx = x - ring.width / 2
        const dy = y - ring.height / 2
        const d = Math.sqrt(dx * dx + dy * dy)
        if (Math.abs(d - ringR) > ringLw / 2 + 3)
            return -1
        // angles start at 12 o'clock and run clockwise, as the canvas draws them
        let t = Math.atan2(dy, dx) + Math.PI / 2
        if (t < 0)
            t += 2 * Math.PI
        let acc = 0
        for (let i = 0; i < segs.length; i++) {
            acc += sweepOf(i)
            if (t <= acc)
                return i
        }
        return segs.length - 1
    }

    onSegsChanged: ring.requestPaint()
    onHoveredChanged: ring.requestPaint()

    Rectangle {
        id: card

        readonly property int pad: 14

        width: root.width
        height: col.implicitHeight + 2 * pad
        radius: 12
        color: Qt.alpha(Theme.bg, 0.92)
        border.width: 1
        border.color: Qt.alpha(Theme.border, 0.6)

        Column {
            id: col
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: card.pad
            spacing: 12

            // the ring, with the centre label: the total, or the hovered share
            Item {
                width: col.width
                height: root.ringSize

                Canvas {
                    id: ring
                    anchors.centerIn: parent
                    width: root.ringSize
                    height: root.ringSize

                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        const cx = width / 2
                        const cy = height / 2
                        ctx.lineCap = "butt"

                        ctx.beginPath()
                        ctx.arc(cx, cy, root.ringR, 0, 2 * Math.PI)
                        ctx.lineWidth = root.ringLw
                        ctx.strokeStyle = String(Qt.alpha(Theme.fg, 0.08))
                        ctx.stroke()

                        let a = -Math.PI / 2
                        for (let i = 0; i < root.segs.length; i++) {
                            const sweep = root.sweepOf(i)
                            ctx.beginPath()
                            ctx.arc(cx, cy, root.ringR, a, a + sweep)
                            ctx.lineWidth = i === root.hovered ? root.ringLw + 4 : root.ringLw
                            ctx.strokeStyle = String(root.colorOf(i))
                            ctx.stroke()
                            a += sweep
                        }
                    }
                }

                Column {
                    anchors.centerIn: ring
                    spacing: 2

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.hovered >= 0 ? root.segs[root.hovered].name : "today"
                        color: Qt.alpha(Theme.fg, 0.6)
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: AppUsage.fmt(root.hovered >= 0 ? root.segs[root.hovered].sec : root.totalSec)
                        color: Theme.fg
                        font.family: Theme.fontFamilyAlt
                        font.pixelSize: Theme.fontSize + 5
                        font.bold: true
                    }
                }

                MouseArea {
                    anchors.fill: ring
                    hoverEnabled: true
                    onPositionChanged: m => root.hovered = root.arcAt(m.x, m.y)
                    onExited: root.hovered = -1
                }
            }

            // legend: one row per segment, the same highlight as the arc
            Repeater {
                model: root.segs

                Rectangle {
                    id: legend
                    required property var modelData
                    required property int index
                    readonly property bool hot: root.hovered === index
                    readonly property int limit: AppUsage.limits[modelData.name] ?? 0
                    readonly property bool over: limit > 0 && modelData.sec >= limit * 60

                    width: col.width
                    height: 24
                    radius: 6
                    color: hot ? Qt.alpha(Theme.fg, 0.08) : "transparent"

                    Rectangle {
                        id: dot
                        anchors.left: parent.left
                        anchors.leftMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        width: 8
                        height: 8
                        radius: 4
                        color: root.colorOf(legend.index)
                    }
                    Text {
                        id: name
                        anchors.left: dot.right
                        anchors.leftMargin: 8
                        anchors.right: time.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: legend.modelData.name
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        elide: Text.ElideRight
                    }
                    Text {
                        id: time
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        text: AppUsage.fmt(legend.modelData.sec)
                            + (legend.limit > 0 ? " / " + AppUsage.fmt(legend.limit * 60) : "")
                        color: legend.over ? Theme.alert : Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: root.hovered = legend.index
                        onExited: root.hovered = -1
                    }
                }
            }
        }
    }
}
