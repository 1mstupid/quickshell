import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import "../../services"
import "../notch"
import "../focus_notch"

// Power menu. A row of round glyph buttons that morphs out of the bar pill like the
// other panels, with the uptime above and the selected action's name below. Reboot
// and power off take a hold (Enter, or a press on the button), so a stray key cannot
// switch the machine off. Toggled by `qs ipc call powermenu toggle`.
PanelWindow {
    id: root

    screen: PillState.originScreen
    visible: false

    // full screen, so a click anywhere outside the notch can close the menu
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.visible && PillState.owner === "powermenu" ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "qs-powermenu-noanim"

    // 4 × 40 buttons, 3 gaps of 10, side margins; the uptime above and the name below
    readonly property int panelW: 236
    readonly property int panelH: 104

    // where the card grows from: the pill, or the card of the panel that gave way to this one
    property real startW: PillState.pillWidth
    property real startH: PillState.pillHeight
    // 1 while shown; fades to 0 when another panel takes the pill
    property real fadeOut: 1
    // taking over another card, so the outline fades in with the morph
    property bool taken: false

    // 0 = the bar pill, 1 = the full menu
    property real t: 0
    // a card closed back to the pill is hidden there: the elastic close reaches the pill early, and
    // a card left over it hid the bar's content until the morph finished
    onTChanged: if (morph.running && morph.to === 0 && t <= 0) visible = false

    // ── Actions ──────────────────────────────────────────────────────────────
    readonly property var actions: [
        { label: "Suspend", icon: "󰒲", hold: true },
        { label: "Lock", icon: "󰌾", hold: false },
        { label: "Reboot", icon: "󰜉", hold: true },
        { label: "Power off", icon: "󰐥", hold: true }
    ]
    property int selectedIndex: 0
    readonly property int buttonCount: actions.length

    // a hold on Reboot or Power off: the button held, and how far the hold has got (0 to 1)
    property int holdIndex: -1
    property real holdProgress: 0
    readonly property int holdMs: 1000

    function activate(i) {
        switch (i) {
            case 0: runAndClose(procSuspend); break;
            case 1: runAndClose(procLock); break;
            case 2: runAndClose(procReboot); break;
            case 3: runAndClose(procShutdown); break;
        }
    }

    // a hold action starts counting; the others run at once
    function startHold(i) {
        if (!actions[i].hold) {
            activate(i)
            return
        }
        holdIndex = i
        holdAnim.restart()
    }

    // letting go early cancels the hold
    function cancelHold() {
        holdAnim.stop()
        holdIndex = -1
        holdProgress = 0
    }

    NumberAnimation {
        id: holdAnim
        target: root
        property: "holdProgress"
        from: 0
        to: 1
        duration: root.holdMs
        onFinished: {
            const i = root.holdIndex
            root.cancelHold()
            root.activate(i)
        }
    }

    IpcHandler {
        target: "powermenu"
        function toggle(): void { PowerMenuState.toggle() }
    }

    // ── Open / close ─────────────────────────────────────────────────────────
    // another panel took the pill: hand this card over and step aside at once
    function giveWay() {
        PillState.takeoverW = card.width
        PillState.takeoverH = card.height
        morph.stop()
        fadeOutAnim.restart()
    }

    function openMenu() {
        if (!PillState.claim("powermenu"))
            return
        const from = PillState.takeOver()
        startW = from.w
        startH = from.h
        taken = from.taken
        fadeOutAnim.stop()
        fadeOut = 1
        visible = true
        uptimeProc.running = true
        morph.stop()
        morph.from = root.t
        morph.to = 1
        morph.start()
    }

    function closeMenu() {
        if (root.visible)
            Sounds.play("close")
        if (PillState.owner === "powermenu")
            PillState.returning = true
        startW = PillState.pillWidth
        startH = PillState.pillHeight
        taken = false
        selectedIndex = 0
        cancelHold()
        morph.stop()
        morph.from = root.t
        morph.to = 0
        morph.start()
    }

    // the card that gave way fades out while the one taking over fades in, so the two cross
    NumberAnimation {
        id: fadeOutAnim
        target: root
        property: "fadeOut"
        to: 0
        duration: PillState.morphMs
        easing.type: Easing.InOutCubic
        onFinished: {
            if (root.fadeOut <= 0) {
                root.visible = false
                root.t = 0
            }
        }
    }

    NumberAnimation {
        id: morph
        target: root
        property: "t"
        duration: PillState.morphMs
        easing.type: PillState.openEase
        easing.period: PillState.easePeriod
        onFinished: {
            if (root.t < 0.5) {
                root.visible = false
                if (PillState.owner === "powermenu")
                    PillState.owner = ""
            }
        }
    }

    Connections {
        target: PowerMenuState
        function onPowerVisibleChanged() {
            if (PowerMenuState.powerVisible)
                root.openMenu()
            else
                root.closeMenu()
        }
    }

    // another panel took the pill, so the menu gives way
    Connections {
        target: PillState
        function onOwnerChanged() {
            if (PillState.owner !== "powermenu" && root.visible) {
                // a panel took the pill: hand our card over; the flag then runs the usual close
                if (PillState.owner !== "") root.giveWay()
                PowerMenuState.hide()
            }
        }
    }

    onVisibleChanged: {
        if (visible)
            keyHost.forceActiveFocus()
    }

    // ── Uptime, read each time the menu opens ───────────────────────────────
    property string uptimeText: ""

    Process {
        id: uptimeProc
        command: ["cat", "/proc/uptime"]
        stdout: StdioCollector {
            onStreamFinished: {
                const s = Math.floor(parseFloat(text) || 0)
                const h = Math.floor(s / 3600)
                const m = Math.floor((s % 3600) / 60)
                root.uptimeText = (h > 0 ? h + " h " : "") + m + " min"
            }
        }
    }

    // ── Process runners ──────────────────────────────────────────────────────
    Process {
        id: procSuspend
        command: ["systemctl", "suspend"]
    }
    // the lock screen is its own shell component, reached over its IPC target
    Process {
        id: procLock
        command: ["quickshell", "-p", Quickshell.shellDir, "ipc", "call", "lock", "lock"]
    }
    Process {
        id: procReboot
        command: ["systemctl", "reboot"]
    }
    Process {
        id: procShutdown
        command: ["systemctl", "poweroff"]
    }

    function runAndClose(proc) {
        PowerMenuState.hide()
        proc.running = true
    }

    // a click outside the notch closes the menu
    MouseArea {
        anchors.fill: parent
        onClicked: PowerMenuState.hide()
    }

    Notch {
        id: outline
        opacity: root.fadeOut * (root.taken ? root.t : 1)
        bodyWidth: card.width
        bodyHeight: card.height
        x: card.x - bodyX
        y: card.y
    }

    Rectangle {
        id: card
        opacity: root.fadeOut

        readonly property real fromW: root.startW
        readonly property real fromH: root.startH

        width: fromW + (root.panelW - fromW) * Math.max(0, root.t)
        height: fromH + (root.panelH - fromH) * Math.max(0, root.t)
        x: (root.width - width) / 2
        y: PillState.pillTop
        color: "transparent"
        clip: true

        // clicks on the notch stay on the notch, not the catcher behind it
        MouseArea { anchors.fill: parent }

        Item {
            id: keyHost
            anchors.fill: parent
            focus: true

            Keys.onPressed: function (event) {
                if (event.key === Qt.Key_Left) {
                    root.cancelHold()
                    root.selectedIndex = (root.selectedIndex - 1 + root.buttonCount) % root.buttonCount
                    event.accepted = true
                } else if (event.key === Qt.Key_Right) {
                    root.cancelHold()
                    root.selectedIndex = (root.selectedIndex + 1) % root.buttonCount
                    event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    // auto-repeat is ignored, so holding the key does not fire twice
                    if (!event.isAutoRepeat && root.holdIndex < 0)
                        root.startHold(root.selectedIndex)
                    event.accepted = true
                }
            }
            Keys.onReleased: function (event) {
                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !event.isAutoRepeat)
                    root.cancelHold()
            }
            Keys.onEscapePressed: PowerMenuState.hide()
        }

        // content fades in during the second half of the morph
        Column {
            anchors.centerIn: parent
            spacing: 8
            opacity: Math.max(0, (root.t - 0.5) * 2)

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Up " + root.uptimeText
                color: Qt.alpha(Theme.fg, 0.5)
                font.pixelSize: 11
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10

                Repeater {
                    model: root.actions

                    PowerButton {
                        required property var modelData
                        required property int index
                        label: modelData.label
                        icon: modelData.icon
                        hold: modelData.hold
                        selected: root.selectedIndex === index
                        progress: root.holdIndex === index ? root.holdProgress : 0
                        onPressStarted: {
                            root.selectedIndex = index
                            root.startHold(index)
                        }
                        onPressEnded: if (hold) root.cancelHold()
                    }
                }
            }

            // the selected action's name, or what a hold is for
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.holdIndex >= 0
                    ? "Hold to " + root.actions[root.holdIndex].label.toLowerCase()
                    : root.actions[root.selectedIndex].label
                color: Theme.fg
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }
        }
    }

    // ── Inner component: one round button ────────────────────────────────────
    component PowerButton: Item {
        id: btn
        required property string label
        required property string icon
        required property bool hold
        property bool selected: false
        // how far a hold on this button has got, 0 to 1; the ring shows it
        property real progress: 0

        // a press runs the action (or starts its hold); letting go cancels a hold
        signal pressStarted()
        signal pressEnded()

        width: 40
        height: 40

        Rectangle {
            anchors.fill: parent
            radius: 20
            color: btn.selected ? Theme.primary
                 : ma.containsMouse ? Qt.alpha(Theme.fg, 0.16)
                 : Qt.alpha(Theme.fg, 0.1)
            Behavior on color { ColorAnimation { duration: 140 } }

            Text {
                anchors.centerIn: parent
                text: btn.icon
                color: btn.selected ? Theme.bg : Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: 17
            }
        }

        // the hold's ring, round the button, in the alert colour
        Ring {
            anchors.centerIn: parent
            size: 46
            fraction: btn.progress
            tint: Theme.alert
            visible: btn.progress > 0
        }

        Accessible.role: Accessible.Button
        Accessible.name: btn.label

        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: btn.pressStarted()
            onReleased: btn.pressEnded()
        }

        scale: ma.pressed ? 0.96 : 1.0
        Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
    }
}
