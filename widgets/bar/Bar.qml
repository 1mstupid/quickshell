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

    // notch: the bar sits flush with the top edge; pill: it floats a little below it. Every
    // panel grows from here, through PillState.pillTop.
    readonly property real topGap: UserSettings.pill ? 8 : 0

    // the pointer area of the pill also takes a margin below and around it (hoverZone)
    readonly property int hoverPad: 10
    implicitHeight: topGap + pill.height + hoverPad

    // hidden bar gives its space back to windows
    readonly property bool showBar: shown && !Overview.open
    exclusiveZone: showBar ? topGap + Theme.effectiveBarHeight : 0

    color: "transparent"
    visible: Theme.barStateReady && shown

    // while the picker is open the pill is non-interactive, so clicks pass through
    mask: Region { item: PillState.active ? null : hoverZone }

    // the focus notch's pointer area: the pill with a margin, so a near miss still opens it
    Item {
        id: hoverZone
        anchors.fill: pill
        anchors.margins: -root.hoverPad
        HoverHandler {
            id: pillHover
            enabled: root.isOrigin
        }
    }

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

        readonly property int pad: Math.round(10 * Theme.barScale)
        readonly property int innerGap: Math.round(6 * Theme.barScale)
        readonly property bool timerShown: Pomodoro.active || Pomodoro.done

        // volume readout replaces the contents while it is shown; panels
        // also hide the contents, but they keep the pill's own background
        readonly property bool volumeOn: Volume.shown && !PillState.active
        // lock readout, shown while Caps or Num Lock is on and the volume readout is not
        readonly property bool lockOn: Locks.shown && !PillState.active && !Volume.shown
        readonly property bool contentHidden: PillState.active || Volume.shown || Locks.shown

        // Only count width + innerGap if that side actually has visible content
        readonly property int leftW: (workspaces.visible && workspaces.implicitWidth > 0)
            ? workspaces.implicitWidth + innerGap : 0
        readonly property int rightW: (rightRow.visible && rightRow.implicitWidth > 0)
            ? rightRow.implicitWidth + innerGap : 0

        // Symmetrical side width keeps the clock dead-center; collapses to 0 when only the clock is shown
        readonly property int side: Math.max(leftW, rightW)

        y: Overview.open ? -(height + root.topGap)
           : root.topGap + (PillState.pillDropped ? PillState.lockDrop : 0)
        Behavior on y {
            NumberAnimation {
                duration: Overview.open ? 150 : PillState.lockMs
                easing.type: Overview.open ? Easing.OutCubic : PillState.openEase
                easing.period: PillState.easePeriod
                easing.amplitude: PillState.pillAmplitude
            }
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

        // the focus notch opens when the pointer is on the pill (origin screen only)
        Binding {
            target: FocusNotchState
            property: "pillHovered"
            value: pillHover.hovered
            when: root.isOrigin
        }

        // notch outline; the shoulders reach past the pill onto the screen edge (not in pill mode)
        Notch {
            x: -bodyX
            bodyWidth: pill.width
            bodyHeight: pill.height
        }

        // a file dragged onto the pill opens the share panel and joins its queue (origin screen only)
        DropArea {
            anchors.fill: parent
            enabled: root.isOrigin
            keys: ["text/uri-list"]
            onEntered: ShareService.open()
            onExited: ShareService.scheduleClose()
            onDropped: drop => {
                ShareService.addUrls(drop.urls)
                drop.accept(Qt.CopyAction)
            }
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
            visible: UserSettings.workspaces
        }

        // right: media wave, recorder, pomodoro ring, the notification glyph, then the control icon
        Row {
            id: rightRow
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: pill.pad
            spacing: Math.round(4 * Theme.barScale)

            opacity: pill.contentHidden ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 120 } }

            // media wave
            Network {
                anchors.verticalCenter: parent.verticalCenter
                visible: UserSettings.network ?? true
            }

            Battery {
                anchors.verticalCenter: parent.verticalCenter
                showPercentage: false // set to true if you want "85%" next to the icon
                visible: hasBattery && (UserSettings.battery ?? true)
            }
            MediaWave {
                anchors.verticalCenter: parent.verticalCenter
                visible: UserSettings.wave
            }

            // recording indicator; click stops it
            Item {
                id: recIndicator
                anchors.verticalCenter: parent.verticalCenter
                width: recRow.implicitWidth
                height: recRow.implicitHeight
                opacity: recorder.recording ? 1 : 0
                visible: UserSettings.recording && opacity > 0

                Behavior on opacity {
                    NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
                }

                Row {
                    id: recRow
                    spacing: 4

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: recorder.fmt(recorder.elapsed)
                        font.family: Theme.fontFamilyAlt
                        font.pixelSize: 11
                        font.bold: true
                        color: Theme.red
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 5
                        height: 5
                        radius: 2.5
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
                anchors.verticalCenter: parent.verticalCenter
                width: 14
                height: 14
                opacity: pill.timerShown ? 1 : 0
                visible: UserSettings.pomo && opacity > 0

                Behavior on opacity {
                    NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
                }

                Canvas {
                    id: ring
                    anchors.centerIn: parent
                    width: 13
                    height: 13

                    readonly property color ringColor: Pomodoro.done ? Theme.red
                        : Pomodoro.paused ? Theme.disabled : Theme.accent

                    onRingColorChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d")
                        const c = width / 2
                        const r = c - 1.5
                        const f = Pomodoro.fraction
                        ctx.reset()
                        ctx.lineWidth = 1.75

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
                anchors.verticalCenter: parent.verticalCenter
                width: 18
                height: 18
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
                    font.pixelSize: 11
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
                anchors.verticalCenter: parent.verticalCenter
                visible: false
                width: controlIcon.implicitWidth
                height: controlIcon.implicitHeight

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
