// SPDX-License-Identifier: 0BSD
import QtQuick
import QtQuick.Controls.Basic
import Quickshell.Io
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: playerPanel
    IpcHandler {
        target: "chaldea"

        function toggle(): void {
            playerPanel.visible = !playerPanel.visible;
        }

        function show(): void {
            playerPanel.visible = true;
        }

        function hide(): void {
            playerPanel.visible = false;
        }
    }

    visible: false
    implicitWidth: 520
    implicitHeight: 400

    anchors {
        top: true
        right: true
    }

    margins {
        top: 40
        right: 40
    }

    color: "transparent"

    exclusiveZone: 0

    Widget {
        id: player
        anchors.fill: parent
    }
}
   



