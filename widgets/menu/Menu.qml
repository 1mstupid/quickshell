import Quickshell
import Quickshell.Wayland
import QtQuick
import "../../services"
import "../../services/menu"
import "../notch"

// The menu. It morphs out of the bar pill like the launcher, the wallpaper
// picker and the media widget: a notch with a row of group icons on top, a
// row of page names under it for the chosen group, and the page below. A click
// outside the notch closes it, and Escape does too.
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
    // the row of page names under the group icons
    readonly property int subH: 22
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

        // the pages of the chosen group, under the group icons
        Row {
            id: pageRow
            x: (parent.width - width) / 2
            y: root.barH
            height: root.subH
            spacing: 14
            opacity: Math.max(0, (root.t - 0.5) * 2)

            Repeater {
                model: MenuState.tabs[MenuState.tab].pages

                Text {
                    id: pageLabel
                    required property string modelData
                    required property int index
                    readonly property bool selected: MenuState.page[MenuState.tab] === index

                    height: root.subH
                    verticalAlignment: Text.AlignVCenter
                    text: modelData
                    color: selected ? Theme.accent : pageMouse.containsMouse ? Theme.fg : Qt.alpha(Theme.fg, 0.5)
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.bold: selected
                    Behavior on color { ColorAnimation { duration: 120 } }

                    MouseArea {
                        id: pageMouse
                        anchors.fill: parent
                        anchors.margins: -4
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: MenuState.selectPage(MenuState.tab, pageLabel.index)
                    }
                }
            }
        }

        // the chosen page, below the group's page names
        Item {
            x: 0
            y: root.barH + root.subH
            width: parent.width
            height: parent.height - root.barH - root.subH
            opacity: Math.max(0, (root.t - 0.5) * 2)

            // group 0: tasks
            Loader {
                anchors.fill: parent
                active: MenuState.tab === 0 && MenuState.page[0] === 0
                source: "TodoPanel.qml"
            }

            Loader {
                anchors.fill: parent
                active: MenuState.tab === 0 && MenuState.page[0] === 1
                source: "HabitsPanel.qml"
            }

            // group 1: focus
            Loader {
                anchors.fill: parent
                active: MenuState.tab === 1 && MenuState.page[1] === 0
                source: "PomodoroPanel.qml"
            }

            Loader {
                anchors.fill: parent
                active: MenuState.tab === 1 && MenuState.page[1] === 1
                source: "UsagePanel.qml"
            }

            // group 2: network
            Loader {
                anchors.fill: parent
                active: MenuState.tab === 2 && MenuState.page[2] === 0
                source: "WifiPanel.qml"
            }

            Loader {
                anchors.fill: parent
                active: MenuState.tab === 2 && MenuState.page[2] === 1
                source: "BluetoothPanel.qml"
            }

            Loader {
                anchors.fill: parent
                active: MenuState.tab === 2 && MenuState.page[2] === 2
                source: "VpnPanel.qml"
            }
        }
    }
}
