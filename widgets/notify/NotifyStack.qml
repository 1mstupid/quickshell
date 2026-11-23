import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import QtQuick
import "../../services"

// The notification cards: the newest toasts as pill cards under the notch, three at most, and a
// count for the rest. A card shows the notification's summary and body, a glyph for its urgency,
// and its first action as a button. Click a card to end its toast; the notification stays on the
// Home list until it is dismissed there. The toasts end together after the toast lifetime, as
// they did with the bell, and a critical one stays until it is clicked.
PanelWindow {
    id: root

    readonly property int maxCards: 3
    readonly property var toasts: Notifications.notifications.values
        .filter(n => Notifications.isToast(n))
        .reverse()
    readonly property var shown: toasts.slice(0, maxCards)
    readonly property int hidden: toasts.length - shown.length

    screen: PillState.originScreen
    visible: toasts.length > 0
    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: stack.y + stack.height
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-notify"
    // only the cards take clicks; the rest of the strip passes them through
    mask: Region { item: stack }

    Column {
        id: stack
        y: PillState.pillTop + PillState.pillHeight + 8
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 8

        Repeater {
            model: root.shown

            Rectangle {
                id: card
                required property var modelData

                readonly property bool critical: modelData.urgency === NotificationUrgency.Critical
                readonly property var action: modelData.actions.length > 0 ? modelData.actions[0] : null

                width: 320
                height: 52
                radius: height / 2
                color: Qt.alpha(Theme.bg, 0.94)

                // the card's own click ends its toast; the button sits above it and takes its own
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Notifications.expire(card.modelData)
                }

                Text {
                    id: glyph
                    anchors.left: parent.left
                    anchors.leftMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    // nf-md-bell, as the bar used
                    text: "󰂚"
                    color: card.critical ? Theme.red : Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: 16
                }

                Column {
                    anchors.left: glyph.right
                    anchors.leftMargin: 12
                    anchors.right: action ? actionButton.left : parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        width: parent.width
                        text: card.modelData.summary
                        elide: Text.ElideRight
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }
                    Text {
                        width: parent.width
                        visible: text !== ""
                        text: card.modelData.body
                        elide: Text.ElideRight
                        color: Qt.alpha(Theme.fg, 0.5)
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                }

                // the first action the app offered, as a button; it runs the action and ends the toast
                Rectangle {
                    id: actionButton
                    visible: card.action !== null
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: visible ? actionLabel.implicitWidth + 24 : 0
                    height: 30
                    radius: height / 2
                    color: actionMouse.containsMouse ? Qt.alpha(Theme.accent, 0.9) : Qt.alpha(Theme.accent, 0.75)

                    Text {
                        id: actionLabel
                        anchors.centerIn: parent
                        text: card.action ? card.action.text : ""
                        color: Theme.bg
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }
                    MouseArea {
                        id: actionMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            card.action.invoke()
                            Notifications.expire(card.modelData)
                        }
                    }
                }
            }
        }

        // the cards that do not fit, as a count
        Rectangle {
            visible: root.hidden > 0
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.max(26, countLabel.implicitWidth + 14)
            height: 26
            radius: height / 2
            color: Qt.alpha(Theme.bg, 0.94)

            Text {
                id: countLabel
                anchors.centerIn: parent
                text: "+" + root.hidden
                color: Theme.fg
                font.family: Theme.fontFamilyNum
                font.pixelSize: 11
            }
        }
    }
}
