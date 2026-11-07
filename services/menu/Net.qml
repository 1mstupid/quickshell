pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "NetState.js" as NetState

// Shared plumbing for the Wi-Fi, Bluetooth and VPN lists and the drawer's
// network tiles. One command runs at a time and `finished` tells the open list
// to refresh. The tiles' state is read on demand by refreshState(), and again
// after every command.
Singleton {
    id: root

    property bool busy: false
    property string status: ""

    signal finished()

    // what the network tiles show, see NetState.js
    property bool hasWifi: false
    property bool wifiOn: false
    property string wifiConn: ""
    property bool wiredUp: false
    property bool btPresent: false
    property bool btOn: false
    property int vpnCount: 0
    property var vpnActive: []

    property var _err: []
    property var _stateLines: []

    // one tagged line per fact
    readonly property string stateScript:
        "echo \"wifi:$(nmcli radio wifi 2>/dev/null)\"; "
        + "nmcli -t -f DEVICE,TYPE,STATE,CONNECTION d 2>/dev/null | sed 's/^/dev:/'; "
        + "bluetoothctl show 2>/dev/null | awk '/^Controller/ { c = 1 } /Powered:/ { p = $2 } "
        + "END { print \"bt:\" (c ? (p == \"yes\" ? \"on\" : \"off\") : \"absent\") }'; "
        + "nmcli -t -f NAME,TYPE,ACTIVE c show 2>/dev/null | sed 's/^/con:/'"

    function refreshState() { stateProc.running = true }

    function toggleWifi() {
        run(["nmcli", "radio", "wifi", wifiOn ? "off" : "on"], wifiOn ? "wifi off" : "wifi on")
    }

    function toggleBluetooth() {
        run(["bluetoothctl", "power", btOn ? "off" : "on"], btOn ? "bluetooth off" : "bluetooth on")
    }

    onFinished: refreshState()

    function run(cmd, msg) {
        if (busy)
            return
        busy = true
        status = msg
        _err = []
        actProc.command = cmd
        actProc.running = true
    }

    Process {
        id: actProc

        stderr: SplitParser {
            onRead: line => {
                if (line.trim() !== "")
                    root._err.push(line.trim())
            }
        }

        onExited: (code, st) => {
            root.busy = false
            root.status = code === 0
                ? "done"
                : (root._err.length ? root._err[root._err.length - 1] : "failed")
            root.finished()
        }
    }

    Process {
        id: stateProc

        command: ["sh", "-c", root.stateScript]

        stdout: SplitParser {
            onRead: line => root._stateLines.push(line)
        }

        onRunningChanged: {
            if (running) {
                root._stateLines = []
            } else {
                const s = NetState.parse(root._stateLines)
                root.hasWifi = s.hasWifi
                root.wifiOn = s.wifiOn
                root.wifiConn = s.wifiConn
                root.wiredUp = s.wiredUp
                root.btPresent = s.btPresent
                root.btOn = s.btOn
                root.vpnCount = s.vpnCount
                root.vpnActive = s.vpnActive
            }
        }
    }
}
