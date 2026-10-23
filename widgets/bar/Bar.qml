import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../services"
import "./media"

PanelWindow {
    id: root

    property var modelData
    screen: modelData

    // toggled by: qs ipc call bar toggle
    property bool shown: true
    IpcHandler {
        target: "bar"
        function toggle(): void { root.shown = !root.shown }
    }

    anchors { top: true; left: true; right: true }

    WlrLayershell.layer: WlrLayer.Top

    readonly property real topGap: 8

    implicitHeight: topGap + pill.height

    // hidden bar gives its space back to windows
    readonly property bool showBar: shown && !Overview.open
    exclusiveZone: showBar ? topGap + Theme.effectiveBarHeight : 0

    color: "transparent"
    visible: Theme.barStateReady && shown

    // while the picker is open the pill is non-interactive, so clicks pass through
    mask: Region { item: PillState.active ? null : pill }

    // the picker card grows out of the origin bar's pill, so publish its geometry
    readonly property bool isOrigin: root.modelData?.name === PillState.originName

    Binding { target: PillState; property: "pillTop"; value: root.topGap; when: root.isOrigin }
    Binding { target: PillState; property: "pillWidth"; value: pill.width; when: root.isOrigin }
    Binding { target: PillState; property: "pillHeight"; value: pill.height; when: root.isOrigin }

    Recorder {
        id: recorder
    }

    Rectangle {
        id: pill

        readonly property int pad: Math.round(12 * Theme.barScale)
        readonly property bool timerShown: Pomodoro.active || Pomodoro.done

        // each side reserves its own content width; the larger one is used on
        // both sides, so the clock stays centered
        readonly property int side: Math.max(workspaces.implicitWidth, rightRow.implicitWidth)

        y: Overview.open ? -(height + root.topGap) : root.topGap
        Behavior on y {
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }
        anchors.horizontalCenter: parent.horizontalCenter
        width: clock.implicitWidth + 2 * (pad + side)
        height: Theme.effectiveBarHeight
        radius: height / 2

        color: Qt.alpha(Theme.bg, 0.92)
        border.width: 1
        border.color: Qt.alpha(Theme.border, 0.6)

        // non-origin bars fade the whole pill; the origin keeps its background
        // so the picker card can take over from the same spot
        opacity: PillState.active ? 0 : 1
        Behavior on opacity {
            NumberAnimation { duration: 120; easing.type: Easing.OutQuad }
        }
        Behavior on width {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        // left: workspace dots
        Workspaces {
            id: workspaces
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: pill.pad
            outputName: root.modelData.name

            opacity: PillState.active ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }

        // right: recorder, then pomodoro ring
        RowLayout {
            id: rightRow
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: pill.pad
            spacing: 8

            opacity: PillState.active ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 120 } }

            // recording indicator; click stops it
            MediaWave {
                Layout.alignment: Qt.AlignVCenter
            }
            Item {
                id: recIndicator
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: recRow.implicitWidth
                implicitHeight: recRow.implicitHeight
                opacity: recorder.recording ? 1 : 0
                visible: opacity > 0

                Behavior on opacity {
                    NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
                }

                RowLayout {
                    id: recRow
                    spacing: 5

                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: recorder.fmt(recorder.elapsed)
                        font.family: Theme.fontFamilyAlt
                        font.pixelSize: 12
                        font.bold: true
                        color: Theme.red
                    }
                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 6
                        implicitHeight: 6
                        radius: 3
                        color: Theme.red

                        SequentialAnimation on opacity {
                            running: recorder.recording
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.2; duration: 600 }
                            NumberAnimation { to: 1; duration: 600 }
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    onClicked: recorder.stop()
                }
            }

            // pomodoro ring; click pauses or resumes, or dismisses when finished
            Item {
                id: timerDot
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 16
                implicitHeight: 16
                opacity: pill.timerShown ? 1 : 0
                visible: opacity > 0

                Behavior on opacity {
                    NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
                }

                Canvas {
                    id: ring
                    anchors.centerIn: parent
                    width: 14
                    height: 14

                    readonly property color ringColor: Pomodoro.done ? Theme.red
                        : Pomodoro.paused ? Theme.disabled : Theme.accent

                    onRingColorChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d")
                        const c = width / 2
                        const r = c - 1.5
                        const f = Pomodoro.fraction
                        ctx.reset()
                        ctx.lineWidth = 2

                        ctx.strokeStyle = String(Qt.alpha(Theme.fg, 0.15))
                        ctx.beginPath()
                        ctx.arc(c, c, r, 0, 2 * Math.PI)
                        ctx.stroke()

                        ctx.strokeStyle = String(ringColor)
                        ctx.beginPath()
                        ctx.arc(c, c, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * f)
                        ctx.stroke()
                    }
                }

                // repaint on every tick while the arc moves
                Connections {
                    target: Pomodoro
                    function onFractionChanged() { ring.requestPaint() }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Pomodoro.done ? Pomodoro.stop() : Pomodoro.toggle()
                }
            }
        }

        Clock {
            id: clock
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter

            opacity: PillState.active ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }
    }
}
