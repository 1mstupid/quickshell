import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../services"

// The control drawer: a card on the right edge, below the bar, opened by the
// bar's control icon. Tiles for the quick switches, sliders for volume and
// brightness, and the power profile. Brightness and the profile only show on
// hardware that has them, and every item can be turned off in settings.json.
// A click outside the card closes it, and Escape does too.
PanelWindow {
    id: root

    screen: PillState.originScreen
    visible: false

    // full screen, so a click anywhere outside the card can close the drawer
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "quickshell-drawer"

    readonly property int cardWidth: 300
    readonly property int pad: 14
    readonly property int cardRadius: 12
    readonly property int tileGap: 8
    readonly property int tileWidth: (cardWidth - 2 * pad - tileGap) / 2

    readonly property bool showBrightness: UserSettings.brightness && Power.hasBacklight
    readonly property bool showProfile: UserSettings.powerProfile && Power.hasProfiles

    // run once the drawer has closed, so it is not in the shot
    readonly property var screenshotCommand: ["screenshot"]

    // 0 = closed, 1 = fully out
    property real t: 0

    // so the brightness and profile rows are known before the first opening
    Component.onCompleted: Power.refresh()

    function openDrawer() {
        // a panel on the pill and the notification history give way to this one
        if (PillState.owner !== "")
            PillState.owner = ""
        Notifications.open = false
        Power.refresh()
        visible = true
        slide.stop()
        slide.from = root.t
        slide.to = 1
        slide.start()
    }

    function closeDrawer() {
        slide.stop()
        slide.from = root.t
        slide.to = 0
        slide.start()
    }

    // brightnessctl is a process per call, so a drag applies at most every
    // 100 ms and always ends on the last value
    property int pendingBrightness: -1

    function moveBrightness(v) {
        const p = Math.max(1, Math.round(v * 100))
        // the track follows the pointer right away
        Power.brightness = p
        pendingBrightness = p
        if (!gate.running)
            gate.flush()
    }

    Timer {
        id: gate
        interval: 100
        function flush() {
            Power.setBrightness(root.pendingBrightness)
            root.pendingBrightness = -1
            start()
        }
        onTriggered: {
            if (root.pendingBrightness >= 0)
                flush()
        }
    }

    Timer {
        id: shot
        interval: 450
        onTriggered: Quickshell.execDetached(root.screenshotCommand)
    }

    onVisibleChanged: {
        if (visible)
            keyHost.forceActiveFocus()
    }

    Connections {
        target: DrawerState
        function onOpenChanged() {
            if (DrawerState.open)
                root.openDrawer()
            else
                root.closeDrawer()
        }
    }

    // a panel took the pill, or the history opened, so the drawer gives way
    Connections {
        target: PillState
        function onOwnerChanged() {
            if (PillState.owner !== "" && root.visible)
                DrawerState.hide()
        }
    }

    Connections {
        target: Notifications
        function onOpenChanged() {
            if (Notifications.open && root.visible)
                DrawerState.hide()
        }
    }

    NumberAnimation {
        id: slide
        target: root
        property: "t"
        duration: 280
        easing.type: Easing.InOutCubic
        onFinished: {
            if (root.t < 0.5)
                root.visible = false
        }
    }

    // a click outside the card closes the drawer
    MouseArea {
        anchors.fill: parent
        onClicked: DrawerState.hide()
    }

    // a switch: icon, name and state; filled while on
    component Tile: Rectangle {
        id: tile

        property string glyph
        property string title
        property string subtitle
        property bool active: false
        signal clicked()

        height: 52
        radius: 10
        color: active ? Theme.accent : Qt.alpha(Theme.fg, tileMouse.containsMouse ? 0.10 : 0.06)
        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
            id: tileIcon
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            width: 20
            horizontalAlignment: Text.AlignHCenter
            text: tile.glyph
            color: tile.active ? Theme.bg : Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: 18
        }

        Column {
            anchors.left: tileIcon.right
            anchors.leftMargin: 8
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Text {
                width: parent.width
                text: tile.title
                elide: Text.ElideRight
                color: tile.active ? Theme.bg : Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.bold: true
            }
            Text {
                width: parent.width
                visible: tile.subtitle !== ""
                text: tile.subtitle
                elide: Text.ElideRight
                color: tile.active ? Qt.alpha(Theme.bg, 0.7) : Qt.alpha(Theme.fg, 0.5)
                font.family: Theme.fontFamily
                font.pixelSize: 10
            }
        }

        MouseArea {
            id: tileMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.clicked()
        }
    }

    // icon, track and readout; click or drag the track to set `value` (0 to 1)
    component SliderRow: Item {
        id: row

        property string glyph
        property real value: 0
        property string readout
        // a muted look, for a muted output
        property bool dim: false
        signal moved(real v)
        signal glyphClicked()

        height: 28

        Text {
            id: rowIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 22
            horizontalAlignment: Text.AlignHCenter
            text: row.glyph
            color: row.dim ? Qt.alpha(Theme.fg, 0.5) : Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: 16

            MouseArea {
                anchors.fill: parent
                anchors.margins: -4
                cursorShape: Qt.PointingHandCursor
                onClicked: row.glyphClicked()
            }
        }

        Text {
            id: rowReadout
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 30
            horizontalAlignment: Text.AlignRight
            text: row.readout
            color: row.dim ? Qt.alpha(Theme.fg, 0.5) : Theme.fg
            font.family: Theme.fontFamilyAlt
            font.pixelSize: 11
            font.bold: true
        }

        Rectangle {
            id: track
            anchors.left: rowIcon.right
            anchors.leftMargin: 8
            anchors.right: rowReadout.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            height: 6
            radius: 3
            color: Qt.alpha(Theme.fg, 0.12)

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * Math.max(0, Math.min(1, row.dim ? 0 : row.value))
                radius: parent.radius
                color: Theme.accent
            }
        }

        // taller than the track, so it is easy to hit
        MouseArea {
            anchors.fill: track
            anchors.topMargin: -10
            anchors.bottomMargin: -10
            cursorShape: Qt.PointingHandCursor

            function set(x) {
                row.moved(Math.max(0, Math.min(1, x / width)))
            }
            onPressed: mouse => set(mouse.x)
            onPositionChanged: mouse => {
                if (pressed)
                    set(mouse.x)
            }
        }
    }

    Rectangle {
        id: card

        // wider than what shows: the right corners sit past the screen edge, so
        // only the left ones read as rounded
        width: root.cardWidth + root.cardRadius
        height: col.implicitHeight + 2 * root.pad
        x: root.width - root.cardWidth * root.t
        y: Theme.effectiveBarHeight + Theme.edgeInset
        radius: root.cardRadius
        color: Theme.bg
        border.width: 1
        border.color: Qt.alpha(Theme.border, 0.6)

        // clicks on the card stay on the card, not the catcher behind it
        MouseArea { anchors.fill: parent }

        Item {
            id: keyHost
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: DrawerState.hide()
        }

        Column {
            id: col
            x: root.pad
            y: root.pad
            width: root.cardWidth - 2 * root.pad
            spacing: 12

            Grid {
                columns: 2
                spacing: root.tileGap

                Tile {
                    width: root.tileWidth
                    glyph: "󰂛"
                    title: "Mute"
                    subtitle: Notifications.muted ? "On" : "Off"
                    active: Notifications.muted
                    onClicked: Notifications.muted = !Notifications.muted
                }
                Tile {
                    width: root.tileWidth
                    visible: UserSettings.nightLight
                    glyph: "󰖔"
                    title: "Night light"
                    subtitle: Power.nightLight ? "On" : "Off"
                    active: Power.nightLight
                    onClicked: Power.setNightLight(!Power.nightLight)
                }
                Tile {
                    width: root.tileWidth
                    visible: UserSettings.keepAwake
                    glyph: "󰅶"
                    title: "Keep awake"
                    subtitle: Power.caffeine ? "On" : "Off"
                    active: Power.caffeine
                    onClicked: Power.setCaffeine(!Power.caffeine)
                }
                Tile {
                    width: root.tileWidth
                    visible: UserSettings.screenshot
                    glyph: "󰄀"
                    title: "Screenshot"
                    onClicked: {
                        DrawerState.hide()
                        shot.restart()
                    }
                }
            }

            Column {
                width: parent.width
                spacing: 6
                visible: Volume.audio !== null || root.showBrightness

                SliderRow {
                    width: parent.width
                    visible: Volume.audio !== null
                    glyph: Volume.muted ? "󰝟" : "󰕾"
                    value: Volume.audio ? Math.min(1, Volume.audio.volume) : 0
                    readout: Volume.muted ? "MU" : Volume.volume.toString()
                    dim: Volume.muted
                    onMoved: v => {
                        Volume.audio.volume = v
                        if (Volume.audio.muted)
                            Volume.audio.muted = false
                    }
                    onGlyphClicked: Volume.audio.muted = !Volume.audio.muted
                }

                SliderRow {
                    width: parent.width
                    visible: root.showBrightness
                    glyph: "󰃟"
                    value: Power.brightness / 100
                    readout: Power.brightness.toString()
                    onMoved: v => root.moveBrightness(v)
                }
            }

            // power profile: one of three, the current one filled
            Row {
                visible: root.showProfile
                spacing: 4

                Repeater {
                    model: [
                        { label: "Quiet", key: "power-saver" },
                        { label: "Balanced", key: "balanced" },
                        { label: "Performance", key: "performance" }
                    ]

                    Rectangle {
                        id: seg
                        required property var modelData
                        readonly property bool current: Power.profile === modelData.key

                        width: (col.width - 2 * 4) / 3
                        height: 28
                        radius: 8
                        color: current ? Theme.accent : Qt.alpha(Theme.fg, segMouse.containsMouse ? 0.10 : 0.06)
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text: seg.modelData.label
                            color: seg.current ? Theme.bg : Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.bold: seg.current
                        }

                        MouseArea {
                            id: segMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Power.setProfile(seg.modelData.key)
                        }
                    }
                }
            }
        }
    }
}
