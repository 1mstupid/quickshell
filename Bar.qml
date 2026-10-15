import QtQuick
import QtQuick.Layouts
import Quickshell.Wayland
import Quickshell

PanelWindow {
    id: root

    property var modelData
    screen: modelData
    property bool expanded: false

    anchors { top: true }

    WlrLayershell.layer: WlrLayer.Top

    readonly property real topGap: 8

    implicitWidth: pill.width
    implicitHeight: pill.height + topGap

    exclusiveZone: topGap + pill.collapsedHeight

    color: "transparent"
    visible: Theme.barStateReady

    mask: Region { item: pill }

    Item {
        id: pill

        readonly property real collapsedWidth: 190
        readonly property real expandedWidth: 320
        readonly property real collapsedHeight: Theme.effectiveBarHeight
        readonly property real expandedHeight: 240

        x: 0
        y: root.topGap
        z: 0
        width: root.expanded ? expandedWidth : collapsedWidth
        height: root.expanded ? expandedHeight : collapsedHeight

        Behavior on height {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        Behavior on width {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        Rectangle {
            anchors.fill: parent
            radius: 2
            color: Qt.alpha(Theme.bg, 0.92)
            border.color: Qt.alpha("#34302f", 0.6)
            border.width: 1

            Behavior on radius {
                NumberAnimation { duration: 60; easing.type: Easing.OutCubic }
            }
        }
        Rectangle { z: 10; width: 7; height: 1; color: "#cc1515" }
        Rectangle { z: 10; width: 1; height: 7; color: "#cc1515" }
        Rectangle { z: 10; anchors.right: parent.right; anchors.bottom: parent.bottom; width: 7; height: 1; color: "#cc1515" }
        Rectangle { z: 10; anchors.right: parent.right; anchors.bottom: parent.bottom; width: 1; height: 7; color: "#cc1515" }

        Recorder {
            id: recorder
        }
        RowLayout {
            id: bar

            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                topMargin: 5
                leftMargin: 10
                rightMargin: 10
                bottomMargin: 5
            }
            height: 10
            spacing: 10
            opacity: root.expanded ? 0 : 1
            visible: opacity > 0

            Behavior on opacity {
                NumberAnimation { duration: 90 }
            }

            // Left side: recording indicator (takes up space only when active, or has a fixed/matching footprint)
            Item {
                id: recIndicator

                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: recorder.recording ? recRow.implicitWidth : 0
                Layout.preferredHeight: recRow.implicitHeight
                visible: recorder.recording // or true, but with width 0 when not recording

                Behavior on Layout.preferredWidth {
                    NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
                }

                RowLayout {
                    id: recRow
                    anchors.centerIn: parent
                    spacing: 5

                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 6
                        implicitHeight: 6
                        radius: 3
                        color: "#e5484d"

                        SequentialAnimation on opacity {
                            running: recIndicator.visible
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.2; duration: 600 }
                            NumberAnimation { to: 1; duration: 600 }
                        }
                    }

                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: recorder.fmt(recorder.elapsed)
                        font.family: "UAV OSD Sans Mono"
                        font.pixelSize: 12
                        font.bold: true
                        color: "#e5484d"
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.expanded = true
                        dashboard.page = 3
                    }
                }
            }

            // Center: The Clock component
            Clock {
                Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                Layout.fillWidth: true
                Layout.fillHeight: true
                onToggleDashboard: root.expanded = !root.expanded
            }

            Item {
                Layout.preferredWidth: recIndicator.Layout.preferredWidth
                Layout.preferredHeight: recIndicator.Layout.preferredHeight
                Layout.alignment: Qt.AlignVCenter
                visible: recIndicator.visible
            }
        }

        Item {
            id: dashboard

            anchors.fill: parent
            anchors.margins: 12
            opacity: root.expanded ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
                NumberAnimation { duration: 90 }
            }

            readonly property var pageNames: ["Clock", "Pomodoro", "Record"]
            property int page: 0

            function go(delta) {
                page = Math.max(0, Math.min(pageNames.length - 1, page + delta))
            }

            // header: current page name and a close button
            RowLayout {
                id: header

                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                }
                height: 16

                Text {
                    Layout.fillWidth: true
                    text: dashboard.pageNames[dashboard.page].toUpperCase()
                    font.family: "UAV OSD Sans Mono"
                    font.pixelSize: 9
                    font.bold: true
                    font.letterSpacing: 1.5
                    color: Qt.alpha(Theme.accent, 0.8)
                }

                Text {
                    text: "󰅖"
                    font.family: "UAV OSD Sans Mono"
                    font.pixelSize: 12
                    color: closeMa.containsMouse ? Theme.accent : Qt.alpha(Theme.fg, 0.6)
                    Behavior on color { ColorAnimation { duration: 120 } }

                    MouseArea {
                        id: closeMa
                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.expanded = false
                    }
                }
            }

            // pages slide horizontally; 170px tall to fit the pill
            Item {
                id: viewport

                anchors {
                    top: header.bottom
                    topMargin: 8
                    left: parent.left
                    right: parent.right
                    bottom: footer.top
                    bottomMargin: 6
                }
                clip: true

                WheelHandler {
                    onWheel: event => dashboard.go(event.angleDelta.y > 0 ? -1 : 1)
                }

                Row {
                    id: strip

                    height: viewport.height
                    x: -dashboard.page * viewport.width

                    Behavior on x {
                        NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
                    }

                    ClockPage {
                        width: viewport.width
                        height: viewport.height
                    }

                    Item {
                        width: viewport.width
                        height: viewport.height

                        Pomodoro {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                        }
                    }

                    Item {
                        width: viewport.width
                        height: viewport.height

                        RecordPage {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            recorder: recorder
                        }
                    }
                }
            }

            // footer: prev arrow, page dots, next arrow
            Row {
                id: footer

                anchors {
                    bottom: parent.bottom
                    horizontalCenter: parent.horizontalCenter
                }
                height: 16
                spacing: 6

                Text {
                    width: 14
                    height: 16
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "‹"
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                    color: prevMa.containsMouse ? Theme.accent : Qt.alpha(Theme.fg, 0.6)

                    MouseArea {
                        id: prevMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: dashboard.go(-1)
                    }
                }

                Repeater {
                    model: dashboard.pageNames

                    Item {
                        id: dot

                        required property int index

                        width: 10
                        height: 16

                        Rectangle {
                            anchors.centerIn: parent
                            width: 6
                            height: 6
                            radius: 3
                            color: dashboard.page === dot.index
                                ? Theme.accent
                                : Qt.alpha(Theme.fg, 0.2)
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: dashboard.page = dot.index
                        }
                    }
                }

                Text {
                    width: 14
                    height: 16
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "›"
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                    color: nextMa.containsMouse ? Theme.accent : Qt.alpha(Theme.fg, 0.6)

                    MouseArea {
                        id: nextMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: dashboard.go(1)
                    }
                }
            }
        }
    }
}
