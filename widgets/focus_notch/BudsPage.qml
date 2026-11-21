import QtQuick
import "../../services"

// The Buds page of the focus notch: the battery of the left and right bud and of the
// case, as three rings, under the device name and how the buds are worn. Reads
// Buds, which only runs the client while this page is on screen.
Item {
    id: page

    readonly property int pad: 18
    readonly property int ringSize: 72

    // one ring with its caption under it; a level of -1 is not reported and shows as a dash
    component Gauge: Column {
        id: gauge

        property string caption
        property int level: -1

        spacing: 8
        width: page.ringSize

        // a fixed box, so the ring is centred without anchoring inside the Column
        Item {
            width: page.ringSize
            height: page.ringSize

            Ring {
                anchors.centerIn: parent
                size: page.ringSize
                fraction: gauge.level >= 0 ? gauge.level / 100 : 0
                label: gauge.level >= 0 ? String(gauge.level) : "—"
                // low is the one colour that is not the accent, so it is seen at a glance
                tint: gauge.level >= 0 && gauge.level < 20 ? Theme.red : Theme.accent
            }
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: gauge.caption
            color: Qt.alpha(Theme.fg, 0.5)
            font.family: Theme.fontFamilyAlt
            font.pixelSize: 10
            font.letterSpacing: 1
        }
    }

    // the name and the status on one line, the wear state under it
    Column {
        x: page.pad
        y: 4
        width: page.width - 2 * page.pad
        spacing: 2
        visible: Buds.connected

        Item {
            width: parent.width
            height: 20

            Text {
                anchors.left: parent.left
                anchors.right: status.left
                anchors.rightMargin: 10
                text: Buds.name
                elide: Text.ElideRight
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: 14
                font.bold: true
            }
            Text {
                id: status
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "Connected"
                color: Theme.green
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }
        }
        Text {
            width: parent.width
            text: "Left " + Buds.wearLeft.toLowerCase() + "  ·  Right " + Buds.wearRight.toLowerCase()
            elide: Text.ElideRight
            color: Qt.alpha(Theme.fg, 0.5)
            font.family: Theme.fontFamily
            font.pixelSize: 11
        }
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 62
        spacing: 36
        visible: Buds.connected

        Gauge { caption: "LEFT"; level: Buds.left }
        Gauge { caption: "RIGHT"; level: Buds.right }
        Gauge { caption: "CASE"; level: Buds.caseLevel }
    }

    // the two states without a device: still asking, or asked and nothing is there
    Text {
        anchors.centerIn: parent
        visible: !Buds.connected
        text: Buds.loaded ? "No Galaxy Buds connected" : "looking…"
        color: Qt.alpha(Theme.fg, 0.5)
        font.family: Theme.fontFamily
        font.pixelSize: 12
    }
}
