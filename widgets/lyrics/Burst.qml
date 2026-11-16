import QtQuick
import "../../services"

// A few diamonds that fly outwards from a point and fade, fired once with fire().
// Place it at the point; the children are drawn around (0, 0).
Item {
    id: burst

    property int count: 6
    property real radius: 24
    property real size: 6
    property var colors: [Theme.primary]

    // 0 at rest, 1 when the diamonds have finished flying
    property real p: 0

    function fire() { flight.restart() }

    width: 0
    height: 0

    NumberAnimation {
        id: flight
        target: burst
        property: "p"
        from: 0
        to: 1
        duration: 600
        easing.type: Easing.OutCubic
    }

    Repeater {
        model: burst.count

        DiamondDot {
            required property int index

            readonly property real angle: index * 2 * Math.PI / burst.count
            readonly property real dist: burst.radius * burst.p

            x: Math.cos(angle) * dist - width / 2
            y: Math.sin(angle) * dist - height / 2
            size: burst.size * (1 - burst.p * 0.6)
            lit: true
            litColor: burst.colors[index % burst.colors.length]
            opacity: 1 - burst.p
            visible: burst.p > 0 && burst.p < 1
        }
    }
}
