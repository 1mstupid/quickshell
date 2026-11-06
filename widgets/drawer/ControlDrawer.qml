import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../services"
import "../../services/menu"
import "../notch"

// The control drawer: a notch hung from the top-right corner, like the toasts
// and the notification history, opened by the bar's control icon. It grows out
// of the corner. Tiles for the quick switches, sliders for volume and
// brightness, and the power profile. Brightness and the profile only show on
// hardware that has them, and every item can be turned off in settings.json.
// The Wi-Fi and Bluetooth tiles switch on a tap and open their list from the
// arrow; the VPN tile opens its list. A list replaces the switches until Back.
// A click outside the notch closes it, and Escape does too.
PanelWindow {
    id: root

    screen: PillState.originScreen
    visible: false

    // full screen, so a click anywhere outside the notch can close the drawer
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
    readonly property int tileGap: 8
    readonly property int tileWidth: (cardWidth - 2 * pad - tileGap) / 2

    readonly property bool showBrightness: UserSettings.brightness && Power.hasBacklight
    readonly property bool showProfile: UserSettings.powerProfile && Power.hasProfiles

    // "" for the switches, or "wifi", "bluetooth" or "vpn" for a list in their place
    property string view: ""
    readonly property bool inView: view !== ""

    // run once the drawer has closed, so it is not in the shot
    readonly property var screenshotCommand: ["screenshot"]

    // 0 = closed, 1 = fully open
    property real t: 0

    // the notch's height, eased so it does not jump when the view or the rows change
    readonly property real targetH: col.implicitHeight + 2 * pad
    property real shownH: targetH
    Behavior on shownH {
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }

    // so the brightness and profile rows are known before the first opening
    Component.onCompleted: Power.refresh()

    function openDrawer() {
        // a panel on the pill and the notification history give way to this one
        if (PillState.owner !== "")
            PillState.owner = ""
        Notifications.open = false
        Power.refresh()
        Net.refreshState()
        view = ""
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

    // the network tiles are read on demand, so keep them fresh while it is open
    Timer {
        interval: 5000
        repeat: true
        running: root.visible
        onTriggered: Net.refreshState()
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

    // a click outside the notch closes the drawer
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
        // with an arrow at the right that opens a list, apart from the tap
        property bool expandable: false
        signal clicked()
        signal expand()

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
            anchors.rightMargin: tile.expandable ? 24 : 6
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

        Text {
            visible: tile.expandable
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            horizontalAlignment: Text.AlignHCenter
            text: "›"
            color: tile.active ? Theme.bg : Qt.alpha(Theme.fg, 0.6)
            font.family: Theme.fontFamily
            font.pixelSize: 18
        }

        // above the tile's own area, so the arrow does not switch
        MouseArea {
            visible: tile.expandable
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            width: 28
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.expand()
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

    // flush with the top and right screen edges, like the toast and history notches
    Notch {
        id: outline
        bodyWidth: card.width
        bodyHeight: card.height
        leftShoulder: true
        rightShoulder: false
        bottomRightSquare: true
        x: card.x - bodyX
        y: card.y
    }

    Rectangle {
        id: card

        // grows out of the top-right corner, the way the history does
        width: root.cardWidth * root.t
        height: root.shownH * root.t
        x: root.width - width
        y: 0
        color: "transparent"
        clip: true

        // clicks on the notch stay on the notch, not the catcher behind it
        MouseArea { anchors.fill: parent }

        Item {
            id: keyHost
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: {
                if (root.inView)
                    root.view = ""
                else
                    DrawerState.hide()
            }
        }

        // full size from the start and anchored to the corner, so the notch
        // reveals it as it grows; it fades in during the second half
        Column {
            id: col
            x: parent.width - root.cardWidth + root.pad
            y: root.pad
            width: root.cardWidth - 2 * root.pad
            spacing: 12
            opacity: Math.max(0, (root.t - 0.5) * 2)

            Grid {
                columns: 2
                spacing: root.tileGap
                visible: !root.inView

                Tile {
                    width: root.tileWidth
                    visible: UserSettings.wifi
                    // without a wireless device this shows the wired link and only opens the list
                    expandable: Net.hasWifi
                    glyph: "󰖩"
                    title: Net.hasWifi ? "Wi-Fi" : "Network"
                    subtitle: Net.hasWifi
                        ? (Net.wifiOn ? (Net.wifiConn !== "" ? Net.wifiConn : "Not connected") : "Off")
                        : (Net.wiredUp ? "Ethernet" : "Disconnected")
                    active: Net.hasWifi ? Net.wifiOn : Net.wiredUp
                    onClicked: {
                        if (Net.hasWifi)
                            Net.toggleWifi()
                        else
                            root.view = "wifi"
                    }
                    onExpand: root.view = "wifi"
                }
                Tile {
                    width: root.tileWidth
                    visible: UserSettings.bluetooth && Net.btPresent
                    expandable: true
                    glyph: "󰂯"
                    title: "Bluetooth"
                    subtitle: Net.btOn ? "On" : "Off"
                    active: Net.btOn
                    onClicked: Net.toggleBluetooth()
                    onExpand: root.view = "bluetooth"
                }
                // which profile to switch is a choice, so a tap opens the list
                Tile {
                    width: root.tileWidth
                    visible: UserSettings.vpn && Net.vpnCount > 0
                    glyph: "󰦝"
                    title: "VPN"
                    subtitle: Net.vpnActive.length === 0 ? "Off"
                        : Net.vpnActive.length === 1 ? Net.vpnActive[0]
                        : Net.vpnActive.length + " active"
                    active: Net.vpnActive.length > 0
                    onClicked: root.view = "vpn"
                }

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
                visible: !root.inView && (Volume.audio !== null || root.showBrightness)

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
                visible: !root.inView && root.showProfile
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

            // a network list, in place of the switches
            Column {
                visible: root.inView
                width: parent.width
                spacing: 6

                Rectangle {
                    width: backRow.implicitWidth + 20
                    height: 24
                    radius: height / 2
                    color: Qt.alpha(Theme.fg, backMouse.containsMouse ? 0.14 : 0.08)

                    Row {
                        id: backRow
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            text: "‹"
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                        }
                        Text {
                            text: "Back"
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                    }

                    MouseArea {
                        id: backMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.view = ""
                    }
                }

                Item {
                    width: parent.width
                    height: 230

                    // the lists keep their own 10 px margins, so the loader reaches past
                    // the padding to line them up with the switches
                    Loader {
                        x: -10
                        width: parent.width + 20
                        height: parent.height
                        active: root.inView
                        source: root.view === "wifi" ? "../menu/WifiPanel.qml"
                              : root.view === "bluetooth" ? "../menu/BluetoothPanel.qml"
                              : root.view === "vpn" ? "../menu/VpnPanel.qml"
                              : ""
                    }
                }
            }
        }
    }
}
