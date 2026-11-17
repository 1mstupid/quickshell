import QtQuick
import "../../services"

// The Share page of the focus notch: the files queued for a LocalSend send, each with a
// remove x, and cancel and send under them. A file dropped on the page joins the queue.
Item {
    id: page

    readonly property int pad: 18
    readonly property int actionsH: 28

    // the queued files as tiles, wrapping; the area is clipped so a long queue scrolls away
    Item {
        x: page.pad
        y: 12
        width: page.width - 2 * page.pad
        height: page.height - y - page.actionsH - 24
        clip: true

        Flow {
            width: parent.width
            spacing: 8

            Repeater {
                model: ShareService.queuedFiles

                Rectangle {
                    id: tile
                    required property string modelData

                    width: 150
                    height: 40
                    radius: 10
                    color: Qt.alpha(Theme.fg, 0.06)

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.right: parent.right
                        anchors.rightMargin: 22
                        anchors.verticalCenter: parent.verticalCenter
                        text: tile.modelData.split("/").pop()
                        elide: Text.ElideRight
                        color: Theme.fg
                        font.family: Theme.fontFamilySans
                        font.pixelSize: 12
                    }

                    // the remove x, in the tile's top-right corner
                    Text {
                        id: removeGlyph
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.topMargin: 3
                        anchors.rightMargin: 6
                        text: "󰅖"
                        color: Qt.alpha(Theme.fg, removeMouse.containsMouse ? 0.9 : 0.4)
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                    }
                    MouseArea {
                        id: removeMouse
                        anchors.right: parent.right
                        anchors.top: parent.top
                        width: 18
                        height: 18
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ShareService.removeFile(tile.modelData)
                    }
                }
            }
        }

        Text {
            visible: ShareService.queuedFiles.length === 0
            anchors.centerIn: parent
            text: "drop files here"
            color: Qt.alpha(Theme.fg, 0.4)
            font.family: Theme.fontFamilySans
            font.pixelSize: 12
        }
    }

    // why nothing went, or what is going: shown bottom-left, beside the actions
    Text {
        anchors.left: parent.left
        anchors.leftMargin: page.pad
        anchors.right: actions.left
        anchors.rightMargin: 10
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 14
        elide: Text.ElideRight
        text: ShareService.sending ? "Sending…"
            : ShareService.selectedDevice === "" ? "set shareDevice in settings"
            : ShareService.lastError
        color: Qt.alpha(Theme.fg, 0.5)
        font.family: Theme.fontFamilySans
        font.pixelSize: 11
    }

    Row {
        id: actions
        anchors.right: parent.right
        anchors.rightMargin: page.pad
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 10
        spacing: 8
        visible: ShareService.queuedFiles.length > 0

        PillButton {
            label: "Cancel"
            onClicked: ShareService.clearQueue()
        }
        PillButton {
            label: "Send"
            main: true
            onClicked: ShareService.send()
        }
    }

    // a file dropped anywhere on the page joins the queue
    DropArea {
        anchors.fill: parent
        keys: ["text/uri-list"]
        onDropped: drop => {
            ShareService.addUrls(drop.urls)
            drop.accept(Qt.CopyAction)
        }
    }
}
