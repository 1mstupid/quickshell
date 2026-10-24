import Quickshell
import Quickshell.Wayland
import QtQuick
import "../../services"
import "../../services/menu"
import "../notch"

// The menu. It morphs out of the bar pill like the launcher, the wallpaper
// picker and the media widget: a notch with a row of icon tabs on top and the
// active tab's panel below. A click outside the notch closes it, and Escape
// does too.
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
    WlrLayershell.namespace: "quickshell-menu"

    readonly property int barH: Theme.effectiveBarHeight
    readonly property int targetW: MenuState.menuW
    readonly property int targetH: barH + MenuState.panelH

    // 0 = the bar pill, 1 = the full menu
    property real t: 0

    function openMenu() {
        PillState.owner = "menu"
        visible = true
        morph.stop()
        morph.from = root.t
        morph.to = 1
        morph.start()
    }

    function closeMenu() {
        morph.stop()
        morph.from = root.t
        morph.to = 0
        morph.start()
    }

    onVisibleChanged: {
        if (visible)
            keyHost.forceActiveFocus()
    }

    Connections {
        target: MenuState
        function onOpenChanged() {
            if (MenuState.open)
                root.openMenu()
            else
                root.closeMenu()
        }
    }

    // another panel took the pill, so the menu gives way
    Connections {
        target: PillState
        function onOwnerChanged() {
            if (PillState.owner !== "menu" && root.visible)
                MenuState.hide()
        }
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
                if (PillState.owner === "menu")
                    PillState.owner = ""
            }
        }
    }

    // a click outside the notch closes the menu
    MouseArea {
        anchors.fill: parent
        onClicked: MenuState.hide()
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

        width: fromW + (root.targetW - fromW) * root.t
        height: fromH + (root.targetH - fromH) * root.t
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
            Keys.onEscapePressed: MenuState.hide()
        }

        // content fades in during the second half of the morph
        Row {
            id: tabRow
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            height: root.barH
            spacing: Math.round(4 * Theme.barScale)
            opacity: Math.max(0, (root.t - 0.5) * 2)

            Repeater {
                model: MenuState.tabs

                Item {
                    id: tabButton
                    required property var modelData
                    required property int index
                    readonly property bool selected: MenuState.tab === index

                    width: Math.round(30 * Theme.barScale)
                    height: tabRow.height

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width
                        height: root.barH - 6
                        radius: height / 2
                        color: tabButton.selected ? Qt.alpha(Theme.accent, 0.25)
                             : tabMouse.containsMouse ? Qt.alpha(Theme.fg, 0.1)
                             : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                    Text {
                        anchors.centerIn: parent
                        text: tabButton.modelData.icon
                        color: tabButton.selected ? Theme.accent : Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.iconSize
                    }
                    MouseArea {
                        id: tabMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: MenuState.select(tabButton.index)
                    }
                }
            }
        }

        // the active tab's panel, below the tab row
        Item {
            x: 0
            y: root.barH
            width: parent.width
            height: parent.height - root.barH
            opacity: Math.max(0, (root.t - 0.5) * 2)

            Loader {
                anchors.fill: parent
                active: MenuState.tab === 0
                source: "TodoPanel.qml"
            }

            Loader {
                anchors.fill: parent
                active: MenuState.tab === 1
                source: "HabitsPanel.qml"
            }

            Loader {
                anchors.fill: parent
                active: MenuState.tab === 2
                source: "PomodoroPanel.qml"
            }

            Loader {
                anchors.fill: parent
                active: MenuState.tab === 3
                source: "WifiPanel.qml"
            }

            Loader {
                anchors.fill: parent
                active: MenuState.tab === 4
                source: "BluetoothPanel.qml"
            }

            Loader {
                anchors.fill: parent
                active: MenuState.tab === 5
                source: "VpnPanel.qml"
            }
        }
    }
}
