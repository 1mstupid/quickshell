import Quickshell
import Quickshell.Wayland
import QtQuick
import "../../services"
import "../notch"

// The share panel: a shelf of the queued files on the left, and a LocalSend area in the
// rest of the space. A click on a shelf file opens it; dragging one onto LocalSend sends it
// alone; a click on LocalSend sends the whole queue. A file dropped on the card joins the
// shelf. It closes on its own when a drag leaves it without a drop.
PanelWindow {
    id: root

    screen: PillState.originScreen
    visible: false

    // full screen, so a click anywhere outside the card closes the panel
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-share"

    readonly property int panelW: 360
    readonly property int panelH: 96

    // 0 = the bar pill, 1 = the full panel
    property real t: 0
    // a card closed back to the pill is hidden there: the elastic close reaches the pill early, and
    // a card left over it hid the bar's content until the morph finished
    onTChanged: if (morph.running && morph.to === 0 && t <= 0) visible = false

    function openPanel() {
        if (!PillState.claim("share")) {
            ShareService.close()
            return
        }
        visible = true
        morph.stop()
        morph.from = root.t
        morph.to = 1
        morph.start()
    }

    function closePanel() {
        if (PillState.owner === "share")
            PillState.returning = true
        morph.stop()
        morph.from = root.t
        morph.to = 0
        morph.start()
    }

    // opened and closed by ShareService; the morph follows its state
    Connections {
        target: ShareService
        function onPanelOpenChanged() {
            if (ShareService.panelOpen)
                root.openPanel()
            else
                root.closePanel()
        }
    }

    // another panel took the pill: close at once, without handing the card over
    Connections {
        target: PillState
        function onOwnerChanged() {
            if (PillState.owner !== "share" && root.visible)
                ShareService.close()
        }
    }

    NumberAnimation {
        id: morph
        target: root
        property: "t"
        duration: PillState.morphMs
        easing.type: PillState.openEase
        easing.period: PillState.easePeriod
        onFinished: {
            if (root.t < 0.5) {
                root.visible = false
                if (PillState.owner === "share")
                    PillState.owner = ""
            }
        }
    }

    // a click outside the card closes the panel
    MouseArea {
        anchors.fill: parent
        onClicked: ShareService.close()
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

        width: fromW + (root.panelW - fromW) * Math.max(0, root.t)
        height: fromH + (root.panelH - fromH) * Math.max(0, root.t)
        x: (root.width - width) / 2
        y: PillState.pillTop
        color: "transparent"
        clip: true

        // clicks on the card stay on the card, not the catcher behind it
        MouseArea { anchors.fill: parent }

        // a file dragged over the card joins the queue; a drag that leaves without a drop
        // lets the panel close
        DropArea {
            anchors.fill: parent
            keys: ["text/uri-list"]
            onEntered: ShareService.cancelClose()
            onExited: ShareService.scheduleClose()
            onDropped: drop => {
                ShareService.addUrls(drop.urls)
                drop.accept(Qt.CopyAction)
            }
        }

        // content fades in during the second half of the morph
        Row {
            anchors.centerIn: parent
            spacing: 10
            opacity: Math.max(0, (root.t - 0.5) * 2)

            // the shelf: the queued files, one a row. A click opens a file with xdg-open;
            // a row dragged onto LocalSend sends that file alone.
            Rectangle {
                width: 130
                height: 64
                radius: 14
                color: Qt.alpha(Theme.fg, 0.05)
                clip: true

                Text {
                    visible: ShareService.queuedFiles.length === 0
                    anchors.centerIn: parent
                    text: "drop files here"
                    color: Qt.alpha(Theme.fg, 0.4)
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }

                ListView {
                    anchors.fill: parent
                    anchors.margins: 5
                    spacing: 2
                    model: ShareService.queuedFiles

                    delegate: Item {
                        id: shelfRow
                        required property string modelData

                        width: ListView.view.width
                        height: 28

                        // the drag moves this proxy and not the row, so the list keeps its place
                        Item {
                            id: ghost
                            width: shelfRow.width
                            height: shelfRow.height
                            Drag.active: shelfMa.drag.active
                            Drag.keys: ["shelf"]
                            Drag.mimeData: { "text/uri-list": ShareService.fileUrl(shelfRow.modelData) }
                            Drag.supportedActions: Qt.CopyAction
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: 8
                            color: shelfMa.containsMouse ? Qt.alpha(Theme.fg, 0.1) : "transparent"
                        }

                        Column {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 7
                            anchors.rightMargin: 7
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                width: parent.width
                                text: shelfRow.modelData.split("/").pop()
                                elide: Text.ElideRight
                                color: Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                            }
                            Text {
                                width: parent.width
                                text: shelfRow.modelData.split("/").slice(-2, -1)[0] ?? ""
                                elide: Text.ElideRight
                                color: Qt.alpha(Theme.fg, 0.4)
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                            }
                        }

                        MouseArea {
                            id: shelfMa
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
                    }
                }
            }

            // the LocalSend area: a click sends the whole queue; a shelf file dropped here is sent alone
            Rectangle {
                width: 200
                height: 64
                radius: 14
                color: sendMa.containsMouse && ShareService.queuedFiles.length > 0
                    ? Qt.alpha(Theme.fg, 0.12) : Qt.alpha(Theme.fg, 0.08)

                DropArea {
                    anchors.fill: parent
                    keys: ["shelf"]
                    onDropped: drop => {
                        ShareService.send(ShareService.pathsOf(drop.urls))
                        drop.accept(Qt.CopyAction)
                    }
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 3

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "LocalSend"
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }

                    Text {
                        width: 180
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: ShareService.sending ? "Sending…"
                            : ShareService.selectedDevice === "" ? "set shareDevice in settings"
                            : ShareService.lastError !== "" ? ShareService.lastError
                            : ShareService.queuedFiles.length > 0
                                ? ShareService.queuedFiles.length + (ShareService.queuedFiles.length === 1 ? " file, click to send" : " files, click to send")
                            : "drop files here"
                        color: Qt.alpha(Theme.fg, 0.5)
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
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
    }
}
