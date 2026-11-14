import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import "../../services"

// The lock screen. `qs ipc call lock lock` locks the session: the compositor covers every
// screen with a LockScreen (ext-session-lock-v1, so it stays locked if the shell dies), the
// password is checked by PAM, and a right password unlocks. State shared by the screens
// (what is typed, whether it failed) lives here; each screen only draws it.
//
// PAM service: needs `security.pam.services.quickshell = {};` in the NixOS config. Without
// it nothing could unlock the session, so locking is refused when the service file is missing.
Scope {
    id: root

    // what is typed, and the password on its way to PAM
    property string buffer: ""
    property string pending: ""
    property bool busy: false
    property bool failed: false
    // the wallpaper in use, read as the pickers do; the screens show it dimmed
    property string wallpaperPath: ""

    signal authFailed()

    readonly property string pamService: "quickshell"

    FileView {
        path: Quickshell.env("HOME") + "/.local/xdg/config/wallpaper-current"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.wallpaperPath = text().trim()
    }

    // qs ipc call lock lock
    IpcHandler {
        target: "lock"
        function lock(): void { root.lockNow() }
    }

    // the service file is checked first: a lock that cannot be opened is worse than none
    Process {
        id: guard
        command: ["test", "-r", "/etc/pam.d/" + root.pamService]
        onExited: exitCode => {
            if (exitCode === 0) {
                root.buffer = ""
                root.pending = ""
                root.busy = false
                root.failed = false
                session.locked = true
            } else {
                console.warn("lock: /etc/pam.d/" + root.pamService + " is missing, not locking")
                Quickshell.execDetached(["notify-send", "-u", "critical", "Lock",
                    "Not locked: /etc/pam.d/" + root.pamService + " is missing. Add "
                    + "security.pam.services." + root.pamService + " = {}; to the NixOS config."])
            }
        }
    }

    function lockNow() {
        if (!session.locked && !guard.running)
            guard.running = true
    }

    function type(text) {
        if (busy)
            return
        failed = false
        buffer += text
    }

    function backspace() {
        if (busy)
            return
        failed = false
        // by characters, not UTF-16 units, so an emoji or accent is removed whole
        buffer = Array.from(buffer).slice(0, -1).join("")
    }

    function clear() {
        if (!busy)
            buffer = ""
    }

    function submit() {
        if (busy || buffer === "")
            return
        pending = buffer
        buffer = ""
        failed = false
        busy = true
        if (!pam.start()) {
            pending = ""
            busy = false
            failed = true
            authFailed()
        }
    }

    PamContext {
        id: pam
        config: root.pamService

        // PAM asks for the password: hand it over, and forget it
        onPamMessage: {
            if (responseRequired) {
                respond(root.pending)
                root.pending = ""
            }
        }

        onCompleted: result => {
            root.busy = false
            root.pending = ""
            if (result === PamResult.Success) {
                root.buffer = ""
                session.locked = false
            } else {
                root.failed = true
                root.authFailed()
            }
        }

        onError: error => console.warn("lock: PAM error", error)
    }

    WlSessionLock {
        id: session

        surface: Component {
            WlSessionLockSurface {
                id: surface
                color: Theme.bg

                LockScreen {
                    anchors.fill: parent
                    lock: root
                    screenName: surface.screen ? surface.screen.name : ""
                }
            }
        }
    }
}
