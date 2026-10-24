import QtQuick
import Quickshell.Io
import "../../services"
import "../../services/menu"

// Bluetooth tab: the power switch, the paired devices (click to connect or
// disconnect) and, after a scan, the nearby devices to pair. Without an
// adapter the tab says so. Polls while open, and refreshes after each action.
Item {
    id: panel

    // the Loader in the menu sizes this panel
    anchors.fill: parent

    property bool btPresent: false
    property bool btOn: false
    property var btDevices: []
    property var btFound: []
    property bool btScanning: false

    // one list: paired devices, then the new ones found by a scan
    readonly property var rows: btOn
        ? btDevices.map(d => ({ kind: "paired", mac: d.mac, name: d.name, connected: d.connected }))
            .concat(btFound.map(d => ({ kind: "new", mac: d.mac, name: d.name, connected: false })))
        : []

    property var _btPaired: []
    property var _btConn: []
    property bool _btPastMark: false
    property var _btAll: []
    property bool _sawController: false

    Component.onCompleted: refresh()

    Connections {
        target: Net
        function onFinished() { panel.refresh() }
    }

    Timer {
        interval: 5000
        repeat: true
        running: true
        onTriggered: panel.refresh()
    }

    function refresh() {
        btShowProc.running = true
        btDevsProc.running = true
    }

    function btScan() {
        if (btScanning)
            return
        btScanning = true
        btFound = []
        btScanProc.running = true
    }

    function btToggleDevice(d) {
        Net.run(["bluetoothctl", d.connected ? "disconnect" : "connect", d.mac],
            (d.connected ? "disconnecting " : "connecting ") + d.name + "…")
    }

    function btPairNew(d) {
        Net.run(["sh", "-c",
            "bluetoothctl pair " + d.mac + " && bluetoothctl trust " + d.mac
            + " && bluetoothctl connect " + d.mac],
            "pairing " + d.name + "…")
        btFound = btFound.filter(f => f.mac !== d.mac)
    }

    Process {
        id: btShowProc

        command: ["sh", "-c", "bluetoothctl show 2>/dev/null"]

        stdout: SplitParser {
            onRead: line => {
                if (line.indexOf("Controller ") === 0)
                    panel._sawController = true
                if (line.trim().indexOf("Powered:") === 0)
                    panel.btOn = line.indexOf("yes") !== -1
            }
        }

        onRunningChanged: {
            if (running)
                panel._sawController = false
            else
                panel.btPresent = panel._sawController
        }
    }

    Process {
        id: btDevsProc

        command: ["sh", "-c",
            "bluetoothctl devices Paired 2>/dev/null; echo ===; bluetoothctl devices Connected 2>/dev/null"]

        stdout: SplitParser {
            onRead: line => {
                if (line.trim() === "===") {
                    panel._btPastMark = true
                    return
                }
                const p = line.trim().split(" ")
                if (p[0] !== "Device" || p.length < 3)
                    return
                const d = { mac: p[1], name: p.slice(2).join(" ") }
                if (panel._btPastMark)
                    panel._btConn.push(d.mac)
                else
                    panel._btPaired.push(d)
            }
        }

        onRunningChanged: {
            if (running) {
                panel._btPaired = []
                panel._btConn = []
                panel._btPastMark = false
            } else {
                panel.btDevices = panel._btPaired.map(d => ({
                    mac: d.mac,
                    name: d.name,
                    connected: panel._btConn.indexOf(d.mac) !== -1
                }))
            }
        }
    }

    Process {
        id: btScanProc

        command: ["sh", "-c",
            "bluetoothctl --timeout 8 scan on >/dev/null 2>&1; bluetoothctl devices 2>/dev/null"]

        stdout: SplitParser {
            onRead: line => {
                const p = line.trim().split(" ")
                if (p[0] === "Device" && p.length >= 3)
                    panel._btAll.push({ mac: p[1], name: p.slice(2).join(" ") })
            }
        }

        onRunningChanged: {
            if (running) {
                panel._btAll = []
            } else {
                const paired = panel.btDevices.map(d => d.mac)
                panel.btFound = panel._btAll.filter(d =>
                    paired.indexOf(d.mac) === -1
                    && !/^([0-9A-F]{2}-){5}[0-9A-F]{2}$/i.test(d.name))
                panel.btScanning = false
            }
        }
    }

    // header: title, then pair new and the power switch
    Item {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 10
        height: 24

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Bluetooth"
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: 12
            font.bold: true
        }

        Rectangle {
            id: powerPill
            visible: panel.btPresent
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 34
            height: 18
            radius: 9
            color: panel.btOn ? Theme.accent : Qt.alpha(Theme.fg, 0.15)
            Behavior on color { ColorAnimation { duration: 150 } }

            Rectangle {
                x: panel.btOn ? parent.width - width - 2 : 2
                anchors.verticalCenter: parent.verticalCenter
                width: 14
                height: 14
                radius: 7
                color: panel.btOn ? Theme.bg : Qt.alpha(Theme.fg, 0.7)
                Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: Net.run(["bluetoothctl", "power", panel.btOn ? "off" : "on"],
                    panel.btOn ? "bluetooth off" : "bluetooth on")
            }
        }

        Rectangle {
            visible: panel.btPresent && panel.btOn
            anchors.right: powerPill.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            width: 74
            height: 22
            radius: 7
            color: Qt.alpha(Theme.fg, pairMa.containsMouse ? 0.18 : 0.1)

            Text {
                anchors.centerIn: parent
                text: panel.btScanning ? "scanning…" : "pair new"
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }
            MouseArea {
                id: pairMa
                anchors.fill: parent
                hoverEnabled: true
                onClicked: panel.btScan()
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: !panel.btPresent
        text: "no bluetooth adapter"
        color: Theme.disabled
        font.family: Theme.fontFamily
        font.pixelSize: 11
    }

    ListView {
        anchors.top: header.bottom
        anchors.topMargin: 6
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 22
        clip: true
        spacing: 2
        boundsBehavior: Flickable.StopAtBounds
        model: panel.rows

        delegate: Rectangle {
            id: btRow
            required property var modelData
            width: ListView.view.width
            height: 30
            radius: 8
            color: btRow.modelData.connected ? Qt.alpha(Theme.accent, 0.25)
                 : btMa.containsMouse ? Qt.alpha(Theme.fg, 0.1)
                 : "transparent"
            Behavior on color { ColorAnimation { duration: 120 } }

            readonly property bool isNew: modelData.kind === "new"

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.right: btTag.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: (btRow.isNew ? "󰂱  " : "󰂯  ") + btRow.modelData.name
                color: btRow.isNew ? Qt.alpha(Theme.fg, 0.7)
                     : btRow.modelData.connected ? Theme.accent : Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: 12
                font.bold: btRow.modelData.connected
                elide: Text.ElideRight
            }

            Text {
                id: btTag
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: btRow.isNew ? "pair" : btRow.modelData.connected ? "connected" : "paired"
                color: btRow.modelData.connected ? Theme.green : Theme.disabled
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }

            MouseArea {
                id: btMa
                anchors.fill: parent
                hoverEnabled: true
                onClicked: btRow.isNew ? panel.btPairNew(btRow.modelData) : panel.btToggleDevice(btRow.modelData)
            }
        }
    }

    Text {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        anchors.bottomMargin: 4
        visible: Net.status !== ""
        elide: Text.ElideRight
        text: Net.status
        color: Net.status.indexOf("fail") !== -1 || Net.status.indexOf("Error") !== -1
            ? Theme.alert : Theme.disabled
        font.family: Theme.fontFamily
        font.pixelSize: 11
    }
}
