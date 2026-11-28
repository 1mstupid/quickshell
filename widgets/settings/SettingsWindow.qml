import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../services"
import "../../services/Settings.js" as Schema

// The settings panel: a window of its own, in the middle of the screen, with a sidebar of
// pages and the settings of the page beside it. `qs ipc call settings toggle` opens and closes
// it; Escape and a click outside close it too, and Tab and Shift+Tab step through the pages.
// What it shows is the list in Settings.js: a page for each group, a row for each setting in
// it. A setting is changed in UserSettings, which writes config.toml, so the file and the panel
// never disagree.
PanelWindow {
    id: root

    screen: PillState.originScreen
    visible: false

    // the whole screen, so a click outside the window can close it
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
    WlrLayershell.namespace: "quickshell-settings"

    readonly property int panelW: 720
    readonly property int panelH: 460
    readonly property int sideW: 200

    // the page in view: an id from Schema.GROUPS
    property string group: Schema.GROUPS[0].id
    readonly property var rows: Schema.SETTINGS.filter(s => s.group === root.group)

    // 0 = closed, 1 = open
    property real t: 0

    function open() {
        if (!visible)
            Sounds.play("open-settings")
        visible = true
        fade.stop()
        fade.from = root.t
        fade.to = 1
        fade.start()
    }

    function close() {
        if (fade.to === 1)
            Sounds.play("close-settings")
        fade.stop()
        fade.from = root.t
        fade.to = 0
        fade.start()
    }

    function toggle() {
        if (visible && fade.to === 1)
            close()
        else
            open()
    }

    onVisibleChanged: {
        if (visible)
            keys.forceActiveFocus()
    }

    function showPage(id) {
        // first, so a text being edited is written before its page goes
        keys.forceActiveFocus()
        if (id !== root.group)
            Sounds.play("page")
        root.group = id
    }

    // the next or previous page, round from either end
    function stepPage(delta) {
        const n = Schema.GROUPS.length
        const i = Schema.GROUPS.findIndex(g => g.id === root.group)
        showPage(Schema.GROUPS[(i + delta + n) % n].id)
    }

    // the lock is about to take the screen: the settings close back first
    Connections {
        target: PillState
        function onLockingChanged() {
            if (PillState.locking && root.visible)
                root.close()
        }
    }

    NumberAnimation {
        id: fade
        target: root
        property: "t"
        duration: PillState.morphMs
        easing.type: Easing.InOutCubic
        onFinished: {
            if (root.t < 0.5)
                root.visible = false
        }
    }

    // qs ipc call settings toggle | show | hide
    IpcHandler {
        target: "settings"
        function toggle(): void { root.toggle() }
        function show(): void { root.open() }
        function hide(): void { root.close() }
    }

    // a click outside the window closes it
    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: root.panelW
        height: root.panelH
        radius: UserSettings.cornerRadius
        color: Theme.bg
        border.width: 1
        border.color: Qt.alpha(Theme.fg, 0.08)
        opacity: root.t
        scale: 0.97 + 0.03 * root.t

        // here, not on `keys`, so Tab from a text field gets this far too
        Keys.onTabPressed: root.stepPage(1)
        Keys.onBacktabPressed: root.stepPage(-1)

        // clicks on the window stay on it, not on the catcher behind; one that is not on a field
        // takes the focus back, which ends the editing of a text
        MouseArea {
            anchors.fill: parent
            onPressed: keys.forceActiveFocus()
        }

        Item {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: root.close()
        }

        // the pages
        Column {
            x: 14
            y: 18
            width: root.sideW - 28
            spacing: 4

            Repeater {
                model: Schema.GROUPS

                Rectangle {
                    id: page
                    required property var modelData
                    readonly property bool on: root.group === modelData.id

                    width: parent.width
                    height: 40
                    radius: height / 2
                    color: on ? Qt.alpha(Theme.fg, 0.10)
                         : pageMouse.containsMouse ? Qt.alpha(Theme.fg, 0.05) : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }

                    // keyboard hint tools find a target by its role
                    Accessible.role: Accessible.Button
                    Accessible.name: page.modelData.title

                    Rectangle {
                        id: badge
                        x: 6
                        anchors.verticalCenter: parent.verticalCenter
                        width: 28
                        height: 28
                        radius: 14
                        color: page.on ? Theme.accent : Qt.alpha(Theme.fg, 0.10)
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text: page.modelData.glyph
                            color: page.on ? Theme.bg : Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                        }
                    }
                    Text {
                        anchors.left: badge.right
                        anchors.leftMargin: 10
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: page.modelData.title
                        elide: Text.ElideRight
                        color: Theme.fg
                        font.family: Theme.fontFamilySans
                        font.pixelSize: 13
                    }
                    MouseArea {
                        id: pageMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.showPage(page.modelData.id)
                    }
                }
            }
        }

        // the rule between the pages and the settings
        Rectangle {
            x: root.sideW
            y: 18
            width: 1
            height: parent.height - 36
            color: Qt.alpha(Theme.fg, 0.08)
        }

        // the settings of the page; they scroll when there are more than fit
        Flickable {
            id: content
            x: root.sideW + 1
            y: 0
            width: parent.width - x
            height: parent.height
            contentWidth: width
            contentHeight: body.implicitHeight + 36
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: body
                x: 20
                y: 18
                width: content.width - 40
                spacing: 12

                Text {
                    text: Schema.GROUPS.find(g => g.id === root.group).title
                    color: Theme.fg
                    font.family: Theme.fontFamilySans
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                }

                Rectangle {
                    width: parent.width
                    height: list.implicitHeight
                    radius: 16
                    color: Qt.alpha(Theme.fg, 0.05)

                    Column {
                        id: list
                        width: parent.width

                        Repeater {
                            model: root.rows

                            Column {
                                id: item
                                required property var modelData
                                required property int index
                                width: list.width

                                // a thin rule between the rows
                                Rectangle {
                                    visible: item.index > 0
                                    x: 14
                                    width: parent.width - 28
                                    height: 1
                                    color: Qt.alpha(Theme.fg, 0.06)
                                }
                                SettingRow {
                                    width: parent.width
                                    def: item.modelData
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
