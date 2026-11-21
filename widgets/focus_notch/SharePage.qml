import QtQuick
import "../../services"

// The Share page of the focus notch: the shelf of the files queued for a LocalSend send, a
// vertical list on the left, and LocalSend in the rest of the space. A click on a shelf file
// opens it; a shelf file dragged onto LocalSend is sent alone; cancel and send sit under them.
// A file dropped on the page joins the shelf.
Item {
    id: page

    readonly property int pad: 18
    readonly property int actionsH: 28

    // the shelf and LocalSend share the space above the actions: the queued files as a
    // vertical list on the left, LocalSend in the rest
    Item {
        id: sharing
        x: page.pad
        y: 12
        width: page.width - 2 * page.pad
        height: page.height - y - page.actionsH - 24

        // the shelf: a click opens a file with xdg-open, the x takes it off the queue,
        // and a row dragged onto LocalSend is sent alone
        Rectangle {
            id: shelf
            width: 150
            height: parent.height
            radius: 12
            color: Qt.alpha(Theme.fg, 0.05)
            clip: true

            Text {
                visible: ShareService.queuedFiles.length === 0
                anchors.centerIn: parent
                text: "drop files here"
                color: Qt.alpha(Theme.fg, 0.4)
                font.family: Theme.fontFamilySans
                font.pixelSize: 12
            }

            ListView {
                anchors.fill: parent
                anchors.margins: 6
                spacing: 3
                model: ShareService.queuedFiles

                delegate: Item {
                    id: shelfRow
                    required property string modelData

                    width: ListView.view.width
                    height: 36

                    // the drag moves this proxy and not the row, so the list keeps its place
                    Item {
                        id: ghost
                        width: shelfRow.width
                        height: shelfRow.height
                        Drag.active: rowMa.drag.active
                        Drag.keys: ["shelf"]
                        Drag.mimeData: { "text/uri-list": ShareService.fileUrl(shelfRow.modelData) }
                        Drag.supportedActions: Qt.CopyAction
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 8
                        color: rowMa.containsMouse ? Qt.alpha(Theme.fg, 0.1) : "transparent"
                    }

                    Column {
                        anchors.left: parent.left
                        anchors.right: removeGlyph.left
                        anchors.leftMargin: 8
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            width: parent.width
                            text: shelfRow.modelData.split("/").pop()
                            elide: Text.ElideRight
                            color: Theme.fg
                            font.family: Theme.fontFamilySans
                            font.pixelSize: 12
                        }
                        Text {
                            width: parent.width
                            text: shelfRow.modelData.split("/").slice(-2, -1)[0] ?? ""
                            elide: Text.ElideRight
                            color: Qt.alpha(Theme.fg, 0.4)
                            font.family: Theme.fontFamilySans
                            font.pixelSize: 10
                        }
                    }

                    MouseArea {
                        id: rowMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        drag.target: ghost
                        onReleased: {
                            ghost.x = 0
                            ghost.y = 0
                        }
                        onClicked: ShareService.openFile(shelfRow.modelData)
                    }

                    // the remove x, at the row's right; it sits above the row's own area
                    Text {
                        id: removeGlyph
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.rightMargin: 6
                        text: "󰅖"
                        color: Qt.alpha(Theme.fg, removeMouse.containsMouse ? 0.9 : 0.4)
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                    }
                    MouseArea {
                        id: removeMouse
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18
                        height: 18
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ShareService.removeFile(shelfRow.modelData)
                    }
                }
            }
        }

        // LocalSend: the rest of the space. A click sends the queue; a shelf row dropped here is sent alone.
        Rectangle {
            id: sendArea
            x: shelf.width + 10
            width: sharing.width - x
            height: parent.height
            radius: 12
            color: sendMa.containsMouse && ShareService.queuedFiles.length > 0
                ? Qt.alpha(Theme.fg, 0.12) : Qt.alpha(Theme.fg, 0.06)

            Column {
                anchors.centerIn: parent
                spacing: 4

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "LocalSend"
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                    font.weight: Font.Medium
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: ShareService.queuedFiles.length > 0 ? "click to send, or drop a file here" : "drop a file here"
                    color: Qt.alpha(Theme.fg, 0.5)
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }
            }

            DropArea {
                anchors.fill: parent
                keys: ["shelf"]
                onDropped: drop => {
                    ShareService.send(ShareService.pathsOf(drop.urls))
                    drop.accept(Qt.CopyAction)
                }
            }

            MouseArea {
                id: sendMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: ShareService.send()
            }
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
        text: ShareService.expanding ? "Preparing files…"
            : ShareService.sending ? "Sending…"
            : ShareService.selectedDevice === "" ? "set shareDevice in settings"
            : ShareService.lastError !== "" ? ShareService.lastError
            : ShareService.queuedFiles.length > 0 ? ShareService.totalFileCount + " files (" + ShareService.formatSize(ShareService.totalSize) + ")"
            : ""
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
            enabled: !ShareService.sending && !ShareService.expanding
            onClicked: ShareService.clearQueue()
        }
        PillButton {
            label: "Send"
            main: true
            enabled: !ShareService.sending && !ShareService.expanding
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
