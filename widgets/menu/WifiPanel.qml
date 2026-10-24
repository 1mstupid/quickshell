import QtQuick
import Quickshell.Io
import "../../services"
import "../../services/menu"

// Wi-Fi tab: the wireless device with its radio switch and throughput, the
// wired devices, then the scan list. A secured network that isn't saved asks
// for its password inline. Polls while open, and refreshes after each action.
Item {
    id: panel

    // the Loader in the menu sizes this panel
    anchors.fill: parent

    property var devices: []
    property bool wifiOn: false
    property var nets: []
    property var savedWifi: []
    property bool scanning: false
    property string pwFor: ""

    readonly property string wifiDev: {
        for (const d of devices)
            if (d.type === "wifi")
                return d.dev
        return ""
    }

    property var _devs: []
    property var _saved: []
    property var _nets: []

    Component.onCompleted: {
        Net.users += 1
        refresh(false)
    }
    Component.onDestruction: Net.users -= 1

    Connections {
        target: Net
        function onFinished() { panel.refresh(false) }
    }

    Timer {
        interval: 5000
        repeat: true
        running: true
        onTriggered: panel.refresh(false)
    }

    function refresh(rescan) {
        devProc.running = true
        radioProc.running = true
        savedProc.running = true
        scanning = true
        scanProc.command = [
            "sh", "-c",
            "nmcli -t -f IN-USE,SIGNAL,SECURITY,SSID dev wifi list --rescan "
            + (rescan ? "yes" : "no")
        ]
        scanProc.running = true
    }

    function connectTo(net) {
        if (net.inUse) {
            Net.run(["nmcli", "d", "disconnect", wifiDev], "disconnecting…")
        } else if (savedWifi.indexOf(net.ssid) !== -1) {
            Net.run(["nmcli", "c", "up", "id", net.ssid], "connecting to " + net.ssid + "…")
        } else if (net.security === "" || net.security === "--") {
            Net.run(["nmcli", "dev", "wifi", "connect", net.ssid], "connecting to " + net.ssid + "…")
        } else {
            pwFor = net.ssid
        }
    }

    function connectPw(ssid, pw) {
        pwFor = ""
        Net.run(["nmcli", "dev", "wifi", "connect", ssid, "password", pw], "connecting to " + ssid + "…")
    }

    function sigGlyph(s) {
        return s < 20 ? "󰤯"
             : s < 45 ? "󰤟"
             : s < 70 ? "󰤢"
             : s < 88 ? "󰤥"
             : "󰤨"
    }

    Process {
        id: devProc

        command: ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "d"]

        stdout: SplitParser {
            onRead: line => {
                const p = line.split(":")
                if (p.length >= 3 && (p[1] === "ethernet" || p[1] === "wifi"))
                    panel._devs.push({
                        dev: p[0],
                        type: p[1],
                        state: p[2],
                        conn: p.slice(3).join(":")
                    })
            }
        }

        onRunningChanged: {
            if (running)
                panel._devs = []
            else
                panel.devices = panel._devs
        }
    }

    Process {
        id: radioProc

        command: ["nmcli", "radio", "wifi"]

        stdout: SplitParser {
            onRead: line => { panel.wifiOn = line.trim() === "enabled" }
        }
    }

    Process {
        id: savedProc

        command: ["nmcli", "-t", "-f", "NAME,TYPE", "c", "show"]

        stdout: SplitParser {
            onRead: line => {
                const p = line.split(":")
                if (p.length < 2)
                    return
                const type = p[p.length - 1]
                const name = p.slice(0, p.length - 1).join(":")
                if (type.indexOf("wireless") !== -1)
                    panel._saved.push(name)
            }
        }

        onRunningChanged: {
            if (running)
                panel._saved = []
            else
                panel.savedWifi = panel._saved
        }
    }

    Process {
        id: scanProc

        stdout: SplitParser {
            onRead: line => {
                const p = line.split(":")
                if (p.length < 4)
                    return
                const ssid = p.slice(3).join(":").replace(/\\:/g, ":")
                if (ssid === "")
                    return
                panel._nets.push({
                    inUse: p[0] === "*",
                    signal: parseInt(p[1]) || 0,
                    security: p[2],
                    ssid: ssid
                })
            }
        }

        onRunningChanged: {
            if (running) {
                panel._nets = []
            } else {
                const best = {}
                for (const n of panel._nets)
                    if (!best[n.ssid] || n.signal > best[n.ssid].signal || n.inUse)
                        best[n.ssid] = n

                panel.nets = Object.values(best).sort((a, b) =>
                    (b.inUse - a.inUse) || (b.signal - a.signal))
                panel.scanning = false
            }
        }
    }

    // header: title and rescan
    Column {
        id: top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 10
        spacing: 6

        Item {
            width: parent.width
            height: 24

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Wi-Fi"
                color: Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: 12
                font.bold: true
            }

            Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 74
                height: 22
                radius: 7
                color: Qt.alpha(Theme.fg, rescanMa.containsMouse ? 0.18 : 0.1)

                Text {
                    anchors.centerIn: parent
                    text: panel.scanning ? "scanning…" : "rescan"
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }
                MouseArea {
                    id: rescanMa
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: panel.refresh(true)
                }
            }
        }

        Repeater {
            model: panel.devices

            Item {
                id: devRow
                required property var modelData
                width: parent.width
                height: 24

                Text {
                    id: devName
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: (devRow.modelData.type === "wifi" ? "󰖩  " : "󰈀  ") + devRow.modelData.dev
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                }

                Text {
                    visible: devRow.modelData.state === "connected"
                    anchors.left: devName.right
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: Net.rateText(devRow.modelData.dev)
                    color: Theme.disabled
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }

                Text {
                    anchors.right: devRow.modelData.type === "wifi" ? radioPill.left : parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: devRow.modelData.state === "connected" ? devRow.modelData.conn : devRow.modelData.state
                    color: devRow.modelData.state === "connected" ? Theme.green : Theme.disabled
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }

                Rectangle {
                    id: radioPill
                    visible: devRow.modelData.type === "wifi"
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 34
                    height: 18
                    radius: 9
                    color: panel.wifiOn ? Theme.accent : Qt.alpha(Theme.fg, 0.15)
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Rectangle {
                        x: panel.wifiOn ? parent.width - width - 2 : 2
                        anchors.verticalCenter: parent.verticalCenter
                        width: 14
                        height: 14
                        radius: 7
                        color: panel.wifiOn ? Theme.bg : Qt.alpha(Theme.fg, 0.7)
                        Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: Net.run(["nmcli", "radio", "wifi", panel.wifiOn ? "off" : "on"],
                            panel.wifiOn ? "wifi off" : "wifi on")
                    }
                }
            }
        }
    }

    // the scan list: connected first, then by signal; the password prompt opens under a row
    ListView {
        id: list
        anchors.top: top.bottom
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
        model: panel.nets

        delegate: Column {
            id: netRow
            required property var modelData
            readonly property bool asking: panel.pwFor === modelData.ssid
            width: ListView.view.width

            Rectangle {
                width: parent.width
                height: 32
                radius: 8
                color: netRow.modelData.inUse ? Qt.alpha(Theme.accent, 0.25)
                     : netMa.containsMouse ? Qt.alpha(Theme.fg, 0.1)
                     : "transparent"
                Behavior on color { ColorAnimation { duration: 120 } }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.right: lockT.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: panel.sigGlyph(netRow.modelData.signal) + "  " + netRow.modelData.ssid
                        + (netRow.modelData.inUse ? "  󰄬" : "")
                    color: netRow.modelData.inUse ? Theme.accent : Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.bold: netRow.modelData.inUse
                    elide: Text.ElideRight
                }

                Text {
                    id: lockT
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: (panel.savedWifi.indexOf(netRow.modelData.ssid) !== -1 ? "saved  " : "")
                        + (netRow.modelData.security !== "" && netRow.modelData.security !== "--" ? "󰌾" : "")
                    color: Theme.disabled
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }

                MouseArea {
                    id: netMa
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: panel.connectTo(netRow.modelData)
                }
            }

            // inline password entry; Escape cancels the prompt and stays in the menu
            Item {
                visible: netRow.asking
                width: parent.width
                height: visible ? 36 : 0

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 3
                    radius: 8
                    color: Qt.alpha(Theme.fg, 0.08)

                    TextInput {
                        id: pwInput
                        anchors.left: parent.left
                        anchors.right: goBtn.left
                        anchors.leftMargin: 10
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        echoMode: TextInput.Password
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        focus: netRow.asking
                        onAccepted: panel.connectPw(netRow.modelData.ssid, text)
                        Keys.onEscapePressed: event => {
                            panel.pwFor = ""
                            event.accepted = true
                        }

                        Text {
                            visible: pwInput.text === ""
                            text: "password"
                            color: Theme.disabled
                            font: pwInput.font
                        }
                    }

                    Rectangle {
                        id: goBtn
                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        width: 52
                        height: 22
                        radius: 7
                        color: Theme.accent

                        Text {
                            anchors.centerIn: parent
                            text: "join"
                            color: Theme.bg
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.bold: true
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: panel.connectPw(netRow.modelData.ssid, pwInput.text)
                        }
                    }
                }
            }
        }
    }

    Text {
        anchors.left: list.left
        anchors.top: list.top
        anchors.topMargin: 6
        visible: panel.nets.length === 0
        text: panel.scanning ? "scanning…" : panel.wifiOn ? "no networks found" : "wifi is off"
        color: Theme.disabled
        font.family: Theme.fontFamily
        font.pixelSize: 11
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
