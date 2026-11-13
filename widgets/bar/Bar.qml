import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../services"
import "./media"
import "../notch"
import "../../services/menu"

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

    // notch: the bar sits flush with the top edge
    readonly property real topGap: 0

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

        // volume readout replaces the contents while it is shown; panels
        // also hide the contents, but they keep the pill's own background
        readonly property bool volumeOn: Volume.shown && !PillState.active
        // lock readout, shown while Caps or Num Lock is on and the volume readout is not
        readonly property bool lockOn: Locks.shown && !PillState.active && !Volume.shown
        readonly property bool contentHidden: PillState.active || Volume.shown || Locks.shown

        // each side reserves its own content width; the larger one is used on
        // both sides, so the clock stays centered
        readonly property int side: Math.max(workspaces.implicitWidth, rightRow.implicitWidth)

        y: Overview.open ? -(height + root.topGap) : root.topGap
        Behavior on y {
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }
        anchors.horizontalCenter: parent.horizontalCenter
        width: volumeOn ? volumeRow.implicitWidth + 4 * pad
             : lockOn ? lockRow.implicitWidth + 4 * pad
             : clock.implicitWidth + 2 * (pad + side)
        height: Theme.effectiveBarHeight

        // the notch is painted by the Canvas below, so the rectangle itself stays clear
        color: "transparent"

        // non-origin bars fade the whole pill; the origin keeps its background
        // so the picker card can take over from the same spot
        opacity: PillState.active ? 0 : 1
        Behavior on opacity {
            NumberAnimation { duration: 120; easing.type: Easing.OutQuad }
        }
        Behavior on width {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        // the focus notch opens when the pointer rests on the pill (origin screen only)
        HoverHandler {
            id: pillHover
            enabled: root.isOrigin
        }
        Binding {
            target: FocusNotchState
            property: "pillHovered"
            value: pillHover.hovered
            when: root.isOrigin
        }

        // notch outline; the shoulders reach past the pill onto the screen edge
        Notch {
            x: -bodyX
            bodyWidth: pill.width
            bodyHeight: pill.height
        }

        // left: workspace dots
        Workspaces {
            id: workspaces
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: pill.pad
            outputName: root.modelData.name

            opacity: pill.contentHidden ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }

        // right: media wave, recorder, pomodoro ring, the notification glyph, then the control icon
        RowLayout {
            id: rightRow
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: pill.pad
            spacing: 8

            opacity: pill.contentHidden ? 0 : 1
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

            // notification glyph: shows when a notification arrives, in a ring that drains
            // over its lifetime, and goes away with it; the notification itself is in the Home
            // list. A critical one has no timeout: its ring stays full, in red, until it is
            // seen. Click opens the focus notch on Home (origin screen only).
            Item {
                id: bell
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 22
                implicitHeight: 22
                opacity: Notifications.toastCount > 0 ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

                readonly property color tint: Notifications.critical ? Theme.red : Theme.accent
                // 1 = full ring, 0 = gone
                property real frac: 1
                readonly property real shown: Notifications.critical ? 1 : frac
                onTintChanged: bellRing.requestPaint()
                onShownChanged: bellRing.requestPaint()

                NumberAnimation {
                    id: drain
                    target: bell
                    property: "frac"
                    from: 1
                    to: 0
                    duration: Notifications.toastLifetime
                }
                Connections {
                    target: Notifications
                    function onArrivalsChanged() { drain.restart() }
                }

                Canvas {
                    id: bellRing
                    anchors.fill: parent
                    onPaint: {
                        const ctx = getContext("2d")
                        const c = width / 2
                        const r = c - 1.5
                        ctx.reset()
                        ctx.lineWidth = 1.5
                        ctx.strokeStyle = String(Qt.alpha(Theme.fg, 0.15))
                        ctx.beginPath()
                        ctx.arc(c, c, r, 0, 2 * Math.PI)
                        ctx.stroke()
                        if (bell.shown > 0) {
                            ctx.strokeStyle = String(bell.tint)
                            ctx.beginPath()
                            ctx.arc(c, c, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * bell.shown)
                            ctx.stroke()
                        }
                    }
                }
                Text {
                    anchors.centerIn: parent
                    // nf-md-bell
                    text: "󰂚"
                    color: bell.tint
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: root.isOrigin
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Notifications.endToasts(true)
                        FocusNotchState.setPage("home")
                        FocusNotchState.show()
                    }
                }
            }

            // control icon: click opens the drawer (origin screen only)
            Item {
                id: control
                Layout.alignment: Qt.AlignVCenter
                visible: false
                implicitWidth: controlIcon.implicitWidth
                implicitHeight: controlIcon.implicitHeight

                Text {
                    id: controlIcon
                    // nf-md-tune
                    text: "󰘮"
                    color: DrawerState.open ? Theme.accent : Qt.alpha(Theme.fg, 0.7)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.iconSize
                }
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    onClicked: DrawerState.toggle()
                }
            }
        }

        // volume readout: icon, track, number; "MU" when muted
        Row {
            id: volumeRow
            anchors.centerIn: parent
            spacing: Math.round(8 * Theme.barScale)

            opacity: pill.volumeOn ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                // nf-md-volume_high / nf-md-volume_off
                text: Volume.muted ? "󰝟" : "󰕾"
                color: Volume.muted ? Qt.alpha(Theme.fg, 0.5) : Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: Theme.iconSize
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.round(72 * Theme.barScale)
                height: 4
                radius: 2
                color: Qt.alpha(Theme.fg, 0.12)

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * (Volume.muted ? 0 : Volume.volume / 100)
                    radius: parent.radius
                    color: Volume.muted ? Qt.alpha(Theme.fg, 0.4) : Theme.accent
                    Behavior on width { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
                }
            }
            // sizes the number slot to "100" so the readout never overflows
            Text {
                id: volumeWidest
                visible: false
                text: "100"
                font.family: Theme.fontFamilyAlt
                font.pixelSize: Theme.fontSize
                font.bold: true
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: volumeWidest.implicitWidth
                horizontalAlignment: Text.AlignRight
                text: Volume.muted ? "MU" : Volume.volume.toString()
                color: Volume.muted ? Qt.alpha(Theme.fg, 0.5) : Theme.fg
                font.family: Theme.fontFamilyAlt
                font.pixelSize: Theme.fontSize
                font.bold: true
            }
        }

        // lock readout: "CAPS LOCK"; replaces the contents while Caps Lock is on
        Text {
            id: lockRow
            anchors.centerIn: parent

            opacity: pill.lockOn ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

            text: Locks.label
            color: Theme.alert
            font.family: Theme.fontFamilyAlt
            font.pixelSize: Theme.fontSize
            font.bold: true
        }

        Clock {
            id: clock
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter

            opacity: pill.contentHidden ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }
    }
}
