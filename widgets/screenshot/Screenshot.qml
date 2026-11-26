pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Screenshots: `qs ipc call screenshot capture` freezes every screen with grim,
// then shows an overlay to pick a region, a window or a whole screen.
// screenshot.sh (ported from lyne-dots, GPL-3.0) crops the frozen screen and
// saves or copies it.
Scope {
    id: root

    property bool active: false
    // "region" (drag), "window" (hover, click to pick) or "screen" (the whole screen)
    property string mode: "region"
    // a window picked by a click stops following the pointer
    property bool pinned: false

    // Hyprland's view of the screens and windows, read when a capture starts
    property var monitorsFromIpc: []
    property var windowsFromIpc: []
    // the screen the selection is on, by name
    property string activeName: ""
    // the selection, in that screen's logical pixels
    property real selX: 0
    property real selY: 0
    property real selW: 0
    property real selH: 0
    readonly property bool hasSelection: selW >= 5 && selH >= 5

    // names the frozen captures of this shot, so a stale one is never reused
    property string stamp: ""
    readonly property string finishScript: Quickshell.shellDir + "/widgets/screenshot/screenshot.sh"

    function tempPath(name: string): string {
        return Quickshell.cachePath(`screenshot-${root.stamp}-${name}.png`);
    }

    // The scale a screen's pixels are in: a region is cropped from the frozen capture in those
    function scaleFor(name: string): real {
        const screen = Quickshell.screens.find(s => s.name === name);
        return (screen ? Hyprland.monitorFor(screen)?.scale : 0) || 1;
    }

    function resetSelection() {
        setRegion(0, 0, 0, 0);
    }

    // Corners in any order; the overlay keeps them on its screen
    function setRegion(x1: real, y1: real, x2: real, y2: real) {
        root.selX = Math.min(x1, x2);
        root.selY = Math.min(y1, y2);
        root.selW = Math.abs(x2 - x1);
        root.selH = Math.abs(y2 - y1);
    }

    function setMode(m: string) {
        root.mode = m;
        root.pinned = false;
        // the overlay of the active screen fills in the selection for "screen"
        if (m !== "screen")
            resetSelection();
    }

    // The window under (x, y) on a screen, in that screen's pixels, or null. Only the
    // windows on the screen's active workspace count; floating ones are on top, then the
    // most recently focused (Hyprland's focusHistoryID is 0 for the focused one)
    function windowAt(screenName: string, x: real, y: real): var {
        const monitor = root.monitorsFromIpc.find(m => m.name === screenName);
        if (!monitor)
            return null;
        const hits = root.windowsFromIpc.filter(w => w.at && w.size && !w.hidden && w.mapped !== false && w.workspace?.id === monitor.activeWorkspace?.id).sort((a, b) => (a.floating ? 0 : 1) - (b.floating ? 0 : 1) || (a.focusHistoryID ?? 0) - (b.focusHistoryID ?? 0));
        const win = hits.find(w => {
            const wx = w.at[0] - monitor.x;
            const wy = w.at[1] - monitor.y;
            return x >= wx && x <= wx + w.size[0] && y >= wy && y <= wy + w.size[1];
        });
        if (!win)
            return null;
        return {
            x: win.at[0] - monitor.x,
            y: win.at[1] - monitor.y,
            w: win.size[0],
            h: win.size[1]
        };
    }

    // one hyprctl call; --batch separates the replies with two blank lines
    Process {
        id: hyprctlInfo
        command: ["hyprctl", "-j", "--batch", "monitors; clients"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.split("\n\n\n").map(part => {
                    try {
                        return JSON.parse(part);
                    } catch (e) {
                        return null;
                    }
                });
                root.monitorsFromIpc = parts[0] ?? [];
                root.windowsFromIpc = parts[1] ?? [];
            }
        }
    }

    function capture() {
        if (root.active || grim.running)
            return;
        root.stamp = String(Date.now());
        root.mode = "region";
        root.pinned = false;
        root.activeName = Hyprland.focusedMonitor?.name || Quickshell.screens[0]?.name || "";
        resetSelection();
        hyprctlInfo.running = true;
        const args = [];
        for (const s of Quickshell.screens)
            args.push(s.name, root.tempPath(s.name));
        // grim runs per screen at once; -l 0 skips compression, which costs far more than the capture
        grim.command = ["sh", "-c", 'while [ $# -gt 0 ]; do grim -l 0 -o "$1" "$2" & shift 2; done; wait', "sh", ...args];
        grim.running = true;
    }

    // Crops the selection and hands it to screenshot.sh: save | copy | edit
    function finish(action: string) {
        if (!root.hasSelection)
            return;
        const scale = root.scaleFor(root.activeName);
        const geometry = Math.round(root.selW * scale) + "x" + Math.round(root.selH * scale) + "+" + Math.round(root.selX * scale) + "+" + Math.round(root.selY * scale);
        const temps = Quickshell.screens.map(s => root.tempPath(s.name));
        root.active = false;
        // empty folder and name: the script's defaults (Pictures/Screenshots, date-based)
        Quickshell.execDetached([root.finishScript, action, root.tempPath(root.activeName), geometry, "", "", ...temps]);
    }

    function cancel() {
        if (!root.active)
            return;
        root.active = false;
        Quickshell.execDetached(["rm", "-f", ...Quickshell.screens.map(s => root.tempPath(s.name))]);
    }

    // qs ipc call screenshot capture
    IpcHandler {
        target: "screenshot"
        function capture(): void { root.capture() }
    }

    Process {
        id: grim
        onExited: exitCode => {
            if (exitCode === 0)
                root.active = true;
            else
                Quickshell.execDetached(["notify-send", "-a", "Screenshot", "Capture failed"]);
        }
    }

    Loader {
        active: root.active
        sourceComponent: Component {
            Variants {
                model: Quickshell.screens

                delegate: ScreenshotOverlay {
                    screenshot: root
                }
            }
        }
    }
}
