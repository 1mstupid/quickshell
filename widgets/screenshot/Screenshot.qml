pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Screenshots: `qs ipc call screenshot capture` freezes every screen with grim,
// then shows an overlay to pick a region or a whole screen. screenshot.sh
// (ported from lyne-dots, GPL-3.0) crops the frozen screen and saves or copies it.
Scope {
    id: root

    property bool active: false
    // "region" (drag) or "screen" (the whole screen the selection is on)
    property string mode: "region"
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
        // the overlay of the active screen fills in the selection for "screen"
        if (m === "region")
            resetSelection();
    }

    function capture() {
        if (root.active || grim.running)
            return;
        root.stamp = String(Date.now());
        root.mode = "region";
        root.activeName = Hyprland.focusedMonitor?.name || Quickshell.screens[0]?.name || "";
        resetSelection();
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
