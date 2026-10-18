import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications

PanelWindow {
    anchors { top: true; right: true;}
    margins { top: 55; right: Theme.edgeInset + 2;}
    implicitWidth: 350
    implicitHeight: Math.max(1, column.implicitHeight)
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    ColumnLayout {
        id: column
        width: parent.width
        spacing: 10
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
                Layout.preferredHeight: 80
                radius: 8
                color: Theme.bg
                border.width: 2
                border.color: modelData.urgency === NotificationUrgency.Critical ? Theme.fg : Theme.bg
                RowLayout {
                    id: layout
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 10

                    Image {
                        Layout.preferredHeight: 36
                        Layout.preferredWidth: 36
                        Layout.alignment: Qt.AlignTop
                        fillMode: Image.PreservedAspectFit
                        visible: source.toString() !== ""
                        source: card.modelData.image || card.modelData.appIcon || ""
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
                            elide: Text.ElideRIght
                            wrapMode: Text.WordWrap
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

