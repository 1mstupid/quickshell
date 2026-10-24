import QtQuick
import Quickshell.Io
import "../../services"
import "../../services/menu"

// VPN tab: the saved VPN and WireGuard profiles with a switch each, and the
// external tunnels, which are shown but not controlled here. Polls while open,
// and shows throughput for the active ones.
Item {
    id: panel

    // the Loader in the menu sizes this panel
    anchors.fill: parent

    property var vpns: []
    property var _vpns: []

    Component.onCompleted: {
        Net.users += 1
        refresh()
    }
    Component.onDestruction: Net.users -= 1

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
        savedProc.running = true
    }

    Process {
        id: savedProc

        command: ["nmcli", "-t", "-f", "NAME,TYPE,ACTIVE", "c", "show"]

        stdout: SplitParser {
            onRead: line => {
                const p = line.split(":")
                if (p.length < 3)
                    return
                const active = p[p.length - 1] === "yes"
                const type = p[p.length - 2]
                const name = p.slice(0, p.length - 2).join(":")

                if (type === "vpn" || type === "wireguard")
                    panel._vpns.push({ name: name, active: active, external: false })
                else if (type === "tun")
                    panel._vpns.push({ name: name, active: active, external: true })
            }
        }

        onRunningChanged: {
            if (running)
                panel._vpns = []
            else
                panel.vpns = panel._vpns
        }
    }

    Text {
        id: title
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: 10
        text: "VPN"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: 12
        font.bold: true
    }

    Text {
        anchors.centerIn: parent
        visible: panel.vpns.length === 0
        text: "no VPN profiles"
        color: Theme.disabled
        font.family: Theme.fontFamily
        font.pixelSize: 11
    }

    ListView {
        anchors.top: title.bottom
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
        model: panel.vpns

        delegate: Item {
            id: vpnRow
            required property var modelData
            width: ListView.view.width
            height: 30

            Text {
                id: vpnName
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "󰦝  " + vpnRow.modelData.name
                color: vpnRow.modelData.active ? Theme.green : Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: 12
            }

            Text {
                visible: vpnRow.modelData.active
                anchors.left: vpnName.right
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: Net.rateText(vpnRow.modelData.name)
                color: Theme.disabled
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }

            Text {
                visible: vpnRow.modelData.external
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: vpnRow.modelData.active ? "on · external" : "external"
                color: vpnRow.modelData.active ? Theme.green : Theme.disabled
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }

            Rectangle {
                visible: !vpnRow.modelData.external
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 34
                height: 18
                radius: 9
                color: vpnRow.modelData.active ? Theme.green : Qt.alpha(Theme.fg, 0.15)
                Behavior on color { ColorAnimation { duration: 150 } }

                Rectangle {
                    x: vpnRow.modelData.active ? parent.width - width - 2 : 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: 14
                    height: 14
                    radius: 7
                    color: vpnRow.modelData.active ? Theme.bg : Qt.alpha(Theme.fg, 0.7)
                    Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: Net.run(["nmcli", "c", vpnRow.modelData.active ? "down" : "up",
                        "id", vpnRow.modelData.name],
                        (vpnRow.modelData.active ? "disconnecting " : "connecting ") + vpnRow.modelData.name + "…")
                }
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
