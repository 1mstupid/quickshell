import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import "../../services"
import "../notch"

// The notification history: the toast notch, opened by the bar's bell, holding
// every notification that has not been dismissed, newest first. It grows out of
// the top-right corner the way the menu grows out of the pill. Mute stops toasts
// from popping up; Clear all dismisses everything. A click outside the notch
// closes it, and Escape does too.
PanelWindow {
    id: root

    screen: PillState.originScreen
    visible: false

    // full screen, so a click anywhere outside the notch can close it
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
    WlrLayershell.namespace: "quickshell-notifications"

    // the same width as a toast notch
    readonly property int cardWidth: 350
    readonly property int pad: 10
    readonly property int headerH: 34
    readonly property int gap: 8
    readonly property int maxListH: 420

    readonly property bool hasAny: Notifications.count > 0
    readonly property int listH: hasAny ? Math.min(stack.implicitHeight, maxListH) : 0
    readonly property int targetW: cardWidth + 2 * pad
    readonly property int targetH: 2 * pad + headerH + (hasAny ? gap + listH : 0)

    // newest first; the model is oldest first
    readonly property var newestFirst: Notifications.notifications.values.slice().reverse()

    // 0 = closed, 1 = fully open
    property real t: 0

    function openPanel() {
        // a panel on the pill gives way to this one
        if (PillState.owner !== "")
            PillState.owner = ""
        visible = true
        morph.stop()
        morph.from = root.t
        morph.to = 1
        morph.start()
    }

    function closePanel() {
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
        target: Notifications
        function onOpenChanged() {
            if (Notifications.open)
                root.openPanel()
            else
                root.closePanel()
        }
    }

    // a panel took the pill, so the history gives way
    Connections {
        target: PillState
        function onOwnerChanged() {
            if (PillState.owner !== "" && root.visible)
                Notifications.open = false
        }
    }

    NumberAnimation {
        id: morph
        target: root
        property: "t"
        duration: 360
        easing.type: Easing.InOutCubic
        onFinished: {
            if (root.t < 0.5)
                root.visible = false
        }
    }

    // a click outside the notch closes the history
    MouseArea {
        anchors.fill: parent
        onClicked: Notifications.open = false
    }

    // a small pill button for the header
    component PillButton: Rectangle {
        id: btn

        property string label
        property bool active: false
        signal clicked()

        implicitWidth: caption.implicitWidth + 20
        implicitHeight: 24
        radius: height / 2
        color: active ? Theme.accent : Qt.alpha(Theme.fg, hit.containsMouse ? 0.14 : 0.08)
        opacity: enabled ? 1 : 0.4

        Text {
            id: caption
            anchors.centerIn: parent
            text: btn.label
            color: btn.active ? Theme.bg : Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: 11
        }

        MouseArea {
            id: hit
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }

    // flush with the top and right screen edges, like the toast notch
    Notch {
        id: outline
        bodyWidth: card.width
        bodyHeight: card.height
        leftShoulder: true
        rightShoulder: false
        bottomRightSquare: true
        x: card.x - bodyX
        y: card.y
    }

    Rectangle {
        id: card

        width: root.targetW * root.t
        height: root.targetH * root.t
        x: root.width - width
        y: 0
        color: "transparent"
        clip: true

        // clicks on the notch stay on the notch, not the catcher behind it
        MouseArea { anchors.fill: parent }

        Item {
            id: keyHost
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: Notifications.open = false
        }

        // full size from the start and anchored to the corner, so the card
        // reveals it as it grows; it fades in during the second half
        Item {
            id: content
            width: root.targetW
            height: root.targetH
            anchors.top: parent.top
            anchors.right: parent.right
            opacity: Math.max(0, (root.t - 0.5) * 2)

            Item {
                id: header
                x: root.pad
                y: root.pad
                width: root.cardWidth
                height: root.headerH

                Column {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    Text {
                        text: "Notifications"
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        font.bold: true
                    }
                    Text {
                        text: root.hasAny
                            ? Notifications.count + (Notifications.count === 1 ? " notification" : " notifications")
                            : "Nothing new"
                        color: Qt.alpha(Theme.fg, 0.5)
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    PillButton {
                        label: Notifications.muted ? "Muted" : "Mute"
                        active: Notifications.muted
                        onClicked: Notifications.muted = !Notifications.muted
                    }
                    PillButton {
                        label: "Clear all"
                        enabled: root.hasAny
                        onClicked: Notifications.clearAll()
                    }
                }
            }

            Flickable {
                id: list
                visible: root.hasAny
                x: root.pad
                y: root.pad + root.headerH + root.gap
                width: root.cardWidth
                height: root.listH
                contentWidth: width
                contentHeight: stack.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: stack
                    width: list.width
                    spacing: 8

                    Repeater {
                        model: root.newestFirst

                        Rectangle {
                            id: entry

                            required property var modelData

                            width: stack.width
                            height: row.implicitHeight + 20
                            radius: 8
                            color: Qt.alpha(Theme.fg, 0.06)
                            border.width: modelData.urgency === NotificationUrgency.Critical ? 2 : 0
                            border.color: Theme.fg

                            HoverHandler { id: hover }

                            RowLayout {
                                id: row
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 10

                                Image {
                                    Layout.preferredHeight: 36
                                    Layout.preferredWidth: 36
                                    Layout.alignment: Qt.AlignTop
                                    fillMode: Image.PreserveAspectFit
                                    visible: source.toString() !== ""
                                    // image is a path or URL; appIcon is a theme name, so it needs image://icon/
                                    source: entry.modelData.image !== ""
                                        ? entry.modelData.image
                                        : (entry.modelData.appIcon !== "" ? "image://icon/" + entry.modelData.appIcon : "")
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6

                                        Text {
                                            Layout.fillWidth: true
                                            text: entry.modelData.summary
                                            color: Theme.fg
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSize + 2
                                            font.bold: true
                                            elide: Text.ElideRight
                                        }

                                        // the arrival time, swapped for a dismiss button under the pointer
                                        Item {
                                            Layout.preferredWidth: 34
                                            Layout.preferredHeight: 16

                                            Text {
                                                anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: Notifications.timeOf(entry.modelData)
                                                opacity: hover.hovered ? 0 : 1
                                                color: Qt.alpha(Theme.fg, 0.4)
                                                font.family: Theme.fontFamilyAlt
                                                font.pixelSize: 10
                                                Behavior on opacity { NumberAnimation { duration: 120 } }
                                            }

                                            Text {
                                                anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: "×"
                                                opacity: hover.hovered ? 1 : 0
                                                color: Qt.alpha(Theme.fg, 0.6)
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 15
                                                Behavior on opacity { NumberAnimation { duration: 120 } }

                                                // no hoverEnabled here: a hovering child would take the hover
                                                // from the entry's handler and hide the × under the pointer
                                                MouseArea {
                                                    anchors.fill: parent
                                                    anchors.margins: -4
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: entry.modelData.dismiss()
                                                }
                                            }
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        visible: text !== ""
                                        text: entry.modelData.body
                                        color: Theme.fg
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSize + 1
                                        elide: Text.ElideRight
                                        wrapMode: Text.WordWrap
                                        maximumLineCount: 4
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
