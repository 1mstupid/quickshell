import QtQuick
import Quickshell
import "../../services"
import "../notch"

Item {
    id: root

    required property var lock
    required property string screenName

    readonly property bool primary: PillState.originName === "" || screenName === PillState.originName

    // 0 = desktop/bar state, 1 = settled lockscreen
    property real t: 0
    Behavior on t {
        NumberAnimation {
            duration: PillState.morphMs
            easing.type: Easing.InOutCubic
        }
    }

    Component.onCompleted: {
        if (root.primary)
            PillState.owner = "lock"
        t = 1
    }

    Connections {
        target: root.lock
        function onUnlockingChanged() {
            if (root.lock.unlocking)
                root.t = 0
        }
    }

    onTChanged: {
        if (root.primary && root.lock.unlocking && t === 0 && PillState.owner === "lock") {
            PillState.progress = 0
            PillState.owner = ""
        }
    }

    Component.onDestruction: {
        if (root.primary && PillState.owner === "lock") {
            PillState.progress = 0
            PillState.owner = ""
        }
    }

    Binding {
        target: PillState
        property: "progress"
        value: root.t
        when: root.primary && PillState.owner === "lock"
    }

    // Sideways shake on wrong password
    property real shake: 0
    SequentialAnimation {
        id: shakeAnim
        NumberAnimation { target: root; property: "shake"; to: -10; duration: 50 }
        NumberAnimation { target: root; property: "shake"; to: 10; duration: 80 }
        NumberAnimation { target: root; property: "shake"; to: -6; duration: 70 }
        NumberAnimation { target: root; property: "shake"; to: 0; duration: 50 }
    }
    Connections {
        target: root.lock
        function onAuthFailed() { shakeAnim.restart() }
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // Background fades in/out with t so unlocking dissolves cleanly back to the desktop
    Rectangle {
        anchors.fill: parent
        color: Theme.bg
        opacity: root.t
    }

    Image {
        anchors.fill: parent
        source: root.lock.wallpaperPath !== "" ? "file://" + root.lock.wallpaperPath : ""
        sourceSize.width: root.width
        sourceSize.height: root.height
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        opacity: (status === Image.Ready ? 1 : 0) * root.t
        Behavior on opacity { NumberAnimation { duration: 200 } }
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(Theme.bg, 0.65)
        opacity: root.t
    }

    // Center clock emerges from the notch and returns to it on unlock
    Text {
        visible: root.primary
        text: Qt.formatDateTime(clock.date, UserSettings.clockFormat)
        color: Qt.alpha(Theme.fg, 0.9)
        font.family: Theme.fontFamilyDisplay
        font.bold: true
        font.pixelSize: Math.round(root.height * 0.28)
        scale: 0.06 + 0.94 * root.t
        opacity: root.t
        x: (root.width - width) / 2
        y: (PillState.pillTop + PillState.pillHeight / 2 - height / 2) * (1 - root.t)
            + (root.height / 2 - height / 2) * root.t
    }

    // Fixed-size notch matching the bar pill exactly
    Notch {
        id: notch

        visible: root.primary
        bodyWidth: PillState.pillWidth
        bodyHeight: PillState.pillHeight
        x: (root.width - bodyWidth) / 2 - bodyX + root.shake
        y: PillState.pillTop
    }

    // Password content inside the unchanged pill silhouette
    Item {
        visible: root.primary
        x: notch.x + notch.bodyX
        y: notch.y
        width: notch.bodyWidth
        height: notch.bodyHeight
        clip: true
        opacity: Math.max(0, (root.t - 0.5) * 2)

        Text {
            id: icon
            x: 12
            anchors.verticalCenter: parent.verticalCenter
            text: "󰌾"
            color: root.lock.failed ? Theme.alert : Qt.alpha(Theme.fg, 0.6)
            font.family: Theme.fontFamily
            font.pixelSize: 14
            Behavior on color { ColorAnimation { duration: 120 } }

            SequentialAnimation on opacity {
                running: root.lock.busy
                loops: Animation.Infinite
                alwaysRunToEnd: true
                NumberAnimation { to: 0.4; duration: 300 }
                NumberAnimation { to: 1.0; duration: 300 }
            }
        }

        Text {
            visible: root.lock.buffer.length === 0
            anchors.left: icon.right
            anchors.leftMargin: 8
            anchors.right: capsLabel.visible ? capsLabel.left : parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: root.lock.failed ? "Wrong password" : "Password"
            color: root.lock.failed ? Theme.alert : Qt.alpha(Theme.fg, 0.4)
            font.family: Theme.fontFamilySans
            font.pixelSize: 12
        }

        Row {
            anchors.left: icon.right
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5

            Repeater {
                model: Math.min(root.lock.buffer.length, 16)

                Rectangle {
                    width: 6
                    height: 6
                    radius: 3
                    color: Theme.fg
                }
            }
        }

        Text {
            id: capsLabel
            visible: Locks.shown
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: Locks.label
            color: Theme.accent
            font.family: Theme.fontFamilySans
            font.pixelSize: 10
            font.letterSpacing: 1
        }
    }

    Item {
        anchors.fill: parent
        focus: true
        enabled: !root.lock.unlocking
        Component.onCompleted: forceActiveFocus()

        Keys.onPressed: event => {
            const enter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter
            if (event.key === Qt.Key_Escape) {
                root.lock.clear()
            } else if (event.key === Qt.Key_Backspace) {
                root.lock.backspace()
            } else if (enter) {
                root.lock.submit()
            } else if (event.text.length > 0 && event.text.charCodeAt(0) >= 0x20
                       && !(event.modifiers & (Qt.ControlModifier | Qt.MetaModifier))) {
                root.lock.type(event.text)
            } else {
                return
            }
            event.accepted = true
        }
    }
}
