pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Galaxy Buds battery and wear state, read from GalaxyBudsClient. The client has no
// events, so it runs only while something shows the Buds page: it sets `watching`, and
// the answer refreshes every few seconds until it is cleared. Nothing runs in the meantime.
Singleton {
    id: root

    property bool watching: false
    // false until the first answer, so "not connected" is not shown before the client has run
    property bool loaded: false
    // false when the client is missing or reports no device
    property bool connected: false
    property string name: ""
    // percentages; -1 when the client does not report one (the case is 0 when the buds are out of it)
    property int left: -1
    property int right: -1
    property int caseLevel: -1
    property string wearLeft: ""
    property string wearRight: ""

    onWatchingChanged: if (watching) refresh()

    function refresh() {
        if (probe.running)
            return
        probe.running = true
    }

    Timer {
        interval: 5000
        repeat: true
        running: root.watching
        onTriggered: root.refresh()
    }

    // a missing field keeps -1, and anything that is not JSON counts as not connected
    function apply(out) {
        let d = null
        try {
            d = JSON.parse(out)
        } catch (e) {
            d = null
        }
        if (typeof d !== "object" || d === null || typeof d.Name !== "string") {
            connected = false
            loaded = true
            return
        }
        const num = v => typeof v === "number" ? v : -1
        name = d.Name
        left = num(d.BatteryLeft)
        right = num(d.BatteryRight)
        caseLevel = num(d.BatteryCase)
        wearLeft = d.WearStateLeft ?? ""
        wearRight = d.WearStateRight ?? ""
        connected = true
        loaded = true
    }

    // a client that cannot run leaves no output, which apply() reads as not connected
    Process {
        id: probe
        command: ["timeout", "4", "GalaxyBudsClient", "device", "--get-all", "--json"]
        stdout: StdioCollector {
            onStreamFinished: root.apply(text)
        }
    }
}
