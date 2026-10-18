pragma Singleton
import Quickshell
import Quickshell.Io

// Power and session controls: power profile, keep-awake, night light,
// brightness. State is read on demand via refresh(), not polled.
Singleton {
    id: root

    readonly property var profileOrder: ["performance", "balanced", "power-saver"]

    property string profile: "balanced"
    property bool caffeine: false
    property bool nightLight: false
    property bool hasBacklight: false
    property int brightness: 50

    function refresh() { stateProc.running = true }

    Process {
        id: stateProc
        // one printf, one guaranteed line per field
        command: ["sh", "-c",
            "printf '%s\\n' " +
            "\"$(powerprofilesctl get 2>/dev/null)\" " +
            "\"$(brightnessctl -m -c backlight 2>/dev/null | head -n1)\" " +
            "\"$(pgrep -f '[w]hy=quickshell-caffeine' >/dev/null && echo awake)\" " +
            "\"$(pgrep -x wlsunset >/dev/null && echo night)\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n")
                if (root.profileOrder.indexOf(lines[0]) >= 0)
                    root.profile = lines[0]
                const bl = (lines[1] ?? "").split(",")
                root.hasBacklight = bl.length >= 4
                if (root.hasBacklight)
                    root.brightness = parseInt(bl[3]) || root.brightness
                root.caffeine = lines[2] === "awake"
                root.nightLight = lines[3] === "night"
            }
        }
    }

    function cycleProfile() {
        const next = profileOrder[(profileOrder.indexOf(profile) + 1) % profileOrder.length]
        Quickshell.execDetached(["powerprofilesctl", "set", next])
        profile = next
    }

    function setCaffeine(on) {
        caffeine = on
        Quickshell.execDetached(["sh", "-c", on
            ? "systemd-inhibit --what=idle --who=quickshell --why=quickshell-caffeine sleep infinity >/dev/null 2>&1 &"
            : "pkill -f '[w]hy=quickshell-caffeine'"])
    }

    function setNightLight(on) {
        nightLight = on
        Quickshell.execDetached(["sh", "-c", on
            ? "command -v wlsunset >/dev/null && (wlsunset -t 4500 -T 6500 >/dev/null 2>&1 &) || notify-send -a quickshell 'Night light' 'Install wlsunset: sudo apt install wlsunset'"
            : "pkill -x wlsunset"])
    }

    function setBrightness(v) {
        brightness = v
        Quickshell.execDetached(["brightnessctl", "-c", "backlight", "set", v + "%"])
    }
}
