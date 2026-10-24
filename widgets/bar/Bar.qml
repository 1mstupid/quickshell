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
    // while the menu is open the origin bar takes the keyboard, so Escape works
    // without a click first (same as the launcher)
    WlrLayershell.keyboardFocus: MenuState.open && isOrigin ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // notch: the bar sits flush with the top edge
    readonly property real topGap: 0

    // the window keeps the menu's full height, so the pill grows inside it
    // instead of the surface resizing every frame
    implicitHeight: topGap + pill.barH + pill.panelH

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

    Item {
        anchors.fill: parent
        focus: root.isOrigin && MenuState.open
        Keys.onEscapePressed: MenuState.hide()
    }

    Rectangle {
        id: pill

        readonly property int pad: Math.round(12 * Theme.barScale)
        readonly property bool timerShown: Pomodoro.active || Pomodoro.done

        // volume readout replaces the contents while it is shown; panels
        // also hide the contents, but they keep the pill's own background
        // the bar becomes the menu on the origin screen only
        readonly property bool menuOn: MenuState.open && root.isOrigin
        readonly property int barH: Theme.effectiveBarHeight
        readonly property int panelH: 220
        readonly property int menuW: 380

        readonly property bool volumeOn: Volume.shown && !PillState.active && !menuOn
        readonly property bool contentHidden: PillState.active || Volume.shown || menuOn

        // each side reserves its own content width; the larger one is used on
        // both sides, so the clock stays centered
        readonly property int side: Math.max(workspaces.implicitWidth, rightRow.implicitWidth)

        y: Overview.open ? -(height + root.topGap) : root.topGap
        Behavior on y {
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }
        anchors.horizontalCenter: parent.horizontalCenter
        width: menuOn ? Math.max(menuRow.implicitWidth + 4 * pad, menuW)
             : volumeOn ? volumeRow.implicitWidth + 4 * pad
             : clock.implicitWidth + 2 * (pad + side)
        height: menuOn ? barH + panelH : barH
        Behavior on height {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

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

        // right: recorder, then pomodoro ring
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
        }

        // clicking the clock opens or closes the menu (origin screen only)
        MouseArea {
            anchors.fill: clock
            enabled: root.isOrigin
            cursorShape: Qt.PointingHandCursor
            onClicked: MenuState.toggle()
        }

        // tabs: the top strip of the expanded bar
        Row {
            id: menuRow
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            height: pill.barH
            spacing: Math.round(4 * Theme.barScale)

            opacity: pill.menuOn ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

            Repeater {
                model: MenuState.tabs

                Item {
                    id: tabButton
                    required property var modelData
                    required property int index
                    readonly property bool selected: MenuState.tab === index

                    width: Math.round(30 * Theme.barScale)
                    height: menuRow.height

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width
                        height: pill.barH - 6
                        radius: height / 2
                        color: tabButton.selected ? Qt.alpha(Theme.accent, 0.25)
                             : tabMouse.containsMouse ? Qt.alpha(Theme.fg, 0.1)
                             : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                    Text {
                        anchors.centerIn: parent
                        text: tabButton.modelData.icon
                        color: tabButton.selected ? Theme.accent : Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.iconSize
                    }
                    MouseArea {
                        id: tabMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: MenuState.select(tabButton.index)
                    }
                }
            }
        }

        // the body of the expanded bar, under the tabs; each tab's panel goes here
        Item {
            id: menuBody
            x: 0
            y: pill.barH
            width: pill.width
            height: pill.panelH
            opacity: pill.menuOn ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

            Text {
                anchors.centerIn: parent
                text: MenuState.tabs[MenuState.tab].name
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
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

        Clock {
            id: clock
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter

            opacity: pill.contentHidden ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }
    }
}
