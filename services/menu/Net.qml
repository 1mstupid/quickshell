pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "NetState.js" as NetState

// Shared plumbing for the Wi-Fi, Bluetooth and VPN lists and the drawer's
// network tiles. One command runs at a time and `finished` tells the open list
// to refresh. Throughput is sampled from /proc/net/dev only while a list that
// shows it is open (`users` above zero). The tiles' state is read on demand by
// refreshState(), and again after every command.
Singleton {
    id: root

    property bool busy: false
    property string status: ""
    property var rates: ({})
    property int users: 0

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
    property var _prev: ({})
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

    function fmtRate(b) {
        return b < 1024
            ? Math.round(b) + " B/s"
            : b < 1048576
                ? (b / 1024).toFixed(b < 102400 ? 1 : 0) + " K/s"
                : (b / 1048576).toFixed(1) + " M/s"
    }

    function rateText(dev) {
        const r = rates[dev]
        return r ? "↓ " + fmtRate(r.down) + "  ↑ " + fmtRate(r.up) : ""
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

    Timer {
        interval: 1000
        repeat: true
        running: root.users > 0
        onTriggered: speedProc.running = true
    }

    Process {
        id: speedProc

        command: ["cat", "/proc/net/dev"]

        stdout: StdioCollector {
            onStreamFinished: {
                const now = Date.now()
                const prev = root._prev
                const next = {}
                const out = {}

                for (const line of text.split("\n")) {
                    const m = line.trim().match(/^(\S+):\s*(.*)$/)
                    if (!m || m[1] === "lo")
                        continue

                    const f = m[2].trim().split(/\s+/)
                    const rx = parseInt(f[0]) || 0
                    const tx = parseInt(f[8]) || 0
                    next[m[1]] = { rx: rx, tx: tx, t: now }

                    if (prev[m[1]]) {
                        const dt = (now - prev[m[1]].t) / 1000
                        if (dt > 0)
                            out[m[1]] = {
                                down: Math.max(0, (rx - prev[m[1]].rx) / dt),
                                up: Math.max(0, (tx - prev[m[1]].tx) / dt)
                            }
                    }
                }

                root._prev = next
                root.rates = out
            }
        }
    }
}
