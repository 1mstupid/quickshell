import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import "../../services"
import "../notch"

// Power menu. A row of glyph buttons that morphs out of the bar pill like the
// other panels. Toggled by `qs ipc call powermenu toggle`.
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
    WlrLayershell.keyboardFocus: root.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "qs-powermenu-noanim"

    // 3 × 36 buttons, 2 gaps of 6, 12 side margins; 10 top and bottom
    readonly property int panelW: 144
    readonly property int panelH: 56

    // 0 = the bar pill, 1 = the full menu
    property real t: 0

    // ── Selection state ──────────────────────────────────────────────────────
    property int selectedIndex: 0
    readonly property int buttonCount: 3

    function activateSelected() {
        switch (selectedIndex) {
            case 0: runAndClose(procSuspend); break;
            case 1: runAndClose(procReboot); break;
            case 2: runAndClose(procShutdown); break;
        }
    }

    IpcHandler {
        target: "powermenu"
        function toggle(): void { PowerMenuState.toggle() }
    }

    // ── Open / close ─────────────────────────────────────────────────────────
    function openMenu() {
        PillState.owner = "powermenu"
        visible = true
        morph.stop()
        morph.from = root.t
        morph.to = 1
        morph.start()
    }

    function closeMenu() {
        selectedIndex = 0
        morph.stop()
        morph.from = root.t
        morph.to = 0
        morph.start()
    }

    NumberAnimation {
        id: morph
        target: root
        property: "t"
        duration: 480
        easing.type: Easing.InOutCubic
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
            if (PillState.owner !== "powermenu" && root.visible)
                PowerMenuState.hide()
        }
    }

    onVisibleChanged: {
        if (visible)
            keyHost.forceActiveFocus()
    }

    // ── Process runners ──────────────────────────────────────────────────────
    Process {
        id: procSuspend
        command: ["systemctl", "suspend"]
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
        bodyWidth: card.width
        bodyHeight: card.height
        x: card.x - bodyX
        y: card.y
    }

    Rectangle {
        id: card

        readonly property real fromW: PillState.pillWidth
        readonly property real fromH: PillState.pillHeight

        width: fromW + (root.panelW - fromW) * root.t
        height: fromH + (root.panelH - fromH) * root.t
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
                    root.selectedIndex = (root.selectedIndex - 1 + root.buttonCount) % root.buttonCount
                    event.accepted = true
                } else if (event.key === Qt.Key_Right) {
                    root.selectedIndex = (root.selectedIndex + 1) % root.buttonCount
                    event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.activateSelected()
                    event.accepted = true
                }
            }
            Keys.onEscapePressed: PowerMenuState.hide()
        }

        // content fades in during the second half of the morph
        Row {
            anchors.centerIn: parent
            spacing: 6
            opacity: Math.max(0, (root.t - 0.5) * 2)

            PowerButton {
                label: "Suspend"
                icon: "󰒲"
                selected: root.selectedIndex === 0
                onActivated: root.runAndClose(procSuspend)
            }
            PowerButton {
                label: "Reboot"
                icon: "󰜉"
                selected: root.selectedIndex === 1
                onActivated: root.runAndClose(procReboot)
            }
            PowerButton {
                label: "Shutdown"
                icon: "󰐥"
                selected: root.selectedIndex === 2
                onActivated: root.runAndClose(procShutdown)
            }
        }
    }

    // ── Inner component: one glyph button ────────────────────────────────────
    component PowerButton: Rectangle {
        id: btn
        required property string label
        required property string icon
        property bool selected: false
        signal activated

        width: 36
        height: 36
        radius: 10

        color: (ma.containsMouse || selected)
               ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
               : "transparent"
        Behavior on color { ColorAnimation { duration: 140 } }

        Accessible.role: Accessible.Button
        Accessible.name: btn.label

        Text {
            anchors.centerIn: parent
            text: btn.icon
            color: Theme.primary
            font.pixelSize: 18
        }

        // short underline under the selected or hovered glyph
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 3
            width: (ma.containsMouse || btn.selected) ? 16 : 0
            height: 2
            radius: 1
            color: Theme.primary
            Behavior on width {
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
            }
        }

        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.activated()
        }

        scale: ma.pressed ? 0.96 : 1.0
        Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
    }
}
