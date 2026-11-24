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
            // keyed by id: a new toast or a dismissal then changes only its own card. A plain
            // array is replaced whole, which rebuilds every card and replays its opening.
            model: ScriptModel {
                values: root.shown
                objectProp: "id"
            }

            // the slot is the card's full height from the start: resizing the column or the
            // window every frame of the opening is what made it choppy
            Item {
                id: slot
                required property var modelData

                width: 320
                height: 52

                Rectangle {
                    id: card
                    readonly property var modelData: slot.modelData
                    readonly property bool critical: modelData.urgency === NotificationUrgency.Critical
                    readonly property var action: modelData.actions.length > 0 ? modelData.actions[0] : null
                    // born at the notch: a bead swells out of its lower edge, falls, then stretches
                    // into the pill while the content fades in
                    property bool open: false

                    anchors.horizontalCenter: parent.horizontalCenter
                    y: -12
                    width: 14
                    height: 14
                    radius: height / 2
                    color: Qt.alpha(Theme.bg, 0.94)
                    clip: true

                    Component.onCompleted: opening.start()

                    // a click ends the toast only after the card has gone back into the notch
                    property bool closing: false

                    function dismiss(): void {
                        if (closing) return
                        closing = true
                        opening.stop()
                        closeAnim.start()
                    }

                    SequentialAnimation {
                        id: closeAnim

                        ParallelAnimation {
                            NumberAnimation { target: face; property: "opacity"; to: 0; duration: 120 }
                            NumberAnimation { target: card; property: "width"; to: 14; duration: 240; easing.type: Easing.InCubic }
                            NumberAnimation { target: card; property: "height"; to: 14; duration: 240; easing.type: Easing.InCubic }
                        }
                        NumberAnimation { target: card; property: "y"; to: -12; duration: 160; easing.type: Easing.InQuad }
                        ScriptAction { script: Notifications.expire(card.modelData) }
                    }

                    SequentialAnimation {
                        id: opening

                        NumberAnimation { target: card; property: "y"; to: -6; duration: 160; easing.type: Easing.OutQuad }
                        ParallelAnimation {
                            NumberAnimation { target: card; property: "y"; to: 0; duration: 200; easing.type: Easing.InQuad }
                            NumberAnimation { target: card; property: "width"; to: 20; duration: 200 }
                            NumberAnimation { target: card; property: "height"; to: 20; duration: 200 }
                        }
                        ParallelAnimation {
                            NumberAnimation { target: card; property: "width"; to: 320; duration: 320; easing.type: Easing.OutCubic }
                            NumberAnimation { target: card; property: "height"; to: 52; duration: 320; easing.type: Easing.OutCubic }
                            NumberAnimation { target: face; property: "opacity"; to: 1; duration: 200 }
                        }
                        ScriptAction { script: card.open = true }
                    }

                    // the card's own click ends its toast; the button sits above it and takes its own
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: card.dismiss()
                    }

                    // the content fades in once the card is open, so the droplet stays empty
                    Item {
                        id: face
                        anchors.fill: parent
                        opacity: 0

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
                            anchors.right: card.action ? actionButton.left : parent.right
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
                                enabled: card.open && !card.closing
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    card.action.invoke()
                                    card.dismiss()
                                }
                            }
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
