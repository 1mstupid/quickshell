import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import "../../services"
import "../notch"

// One notch hung from the top-right corner, holding the stacked toasts.
// Hidden while there are no notifications.
PanelWindow {
    id: root

    readonly property int cardWidth: 350
    readonly property int pad: 10

    anchors { top: true; right: true }
    implicitWidth: notch.width
    implicitHeight: notch.height
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    visible: Notifications.notifications.values.length > 0

    // only the notch takes clicks; the rest of the window passes them through
    mask: Region { item: notch }

    // flush with the top and right screen edges, so only the left shoulder shows
    Notch {
        id: notch
        bodyWidth: root.cardWidth + 2 * root.pad
        bodyHeight: column.implicitHeight + 2 * root.pad
        leftShoulder: true
        rightShoulder: false
    }

    ColumnLayout {
        id: column
        x: notch.bodyX + root.pad
        y: root.pad
        width: root.cardWidth
        spacing: 8

        Repeater {

            model: Notifications.notifications

            delegate: Rectangle {
                id: card
                required property var modelData

                Timer {
                    running: card.modelData.urgency !== NotificationUrgency.Critical
                    interval: 5000
                    onTriggered: card.modelData.dismiss()
                }


                Layout.fillWidth: true
                // sized to its content, so long bodies are not clipped
                implicitHeight: layout.implicitHeight + 20
                radius: 8
                color: Qt.alpha(Theme.fg, 0.06)
                border.width: modelData.urgency === NotificationUrgency.Critical ? 2 : 0
                border.color: Theme.fg
                RowLayout {
                    id: layout
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
                        source: card.modelData.image !== ""
                            ? card.modelData.image
                            : (card.modelData.appIcon !== "" ? "image://icon/" + card.modelData.appIcon : "")
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            Layout.fillWidth: true
                            text: card.modelData.summary
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize + 2
                            font.bold: true
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: text !== ""
                            text: card.modelData.body
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize + 1
                            elide: Text.ElideRight
                            wrapMode: Text.WordWrap
                            maximumLineCount: 3
                        }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: card.modelData.dismiss()
                }
            }
        }
    }
}
