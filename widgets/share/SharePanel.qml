import Quickshell
import Quickshell.Wayland
import QtQuick
import "../../services"
import "../notch"

// The share panel: a Files Tray and a LocalSend area that grow out of the bar pill when a
// file is dragged onto it. Click the LocalSend area to send the queue. It closes on its own
// when a drag leaves it without a drop.
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

    readonly property int panelW: 240
    readonly property int panelH: 96

    // 0 = the bar pill, 1 = the full panel
    property real t: 0

    function openPanel() {
        PillState.owner = "share"
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
        easing.type: Easing.InOutCubic
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

        width: fromW + (root.panelW - fromW) * root.t
        height: fromH + (root.panelH - fromH) * root.t
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

            // the LocalSend area: a click sends the whole queue
            Rectangle {
                width: 200
                height: 64
                radius: 14
                color: sendMa.containsMouse && ShareService.queuedFiles.length > 0
                    ? Qt.alpha(Theme.fg, 0.12) : Qt.alpha(Theme.fg, 0.08)

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
