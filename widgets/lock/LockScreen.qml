import QtQuick
import Quickshell
import "../../services"
import "../notch"

// What one screen shows while locked: the wallpaper dimmed, and on the origin screen the clock
// in the middle and the notch as the password field. The clock starts as a speck inside the
// notch and grows out to the centre while the screen dims. Every screen takes the keys, since
// the compositor decides which one has the keyboard, and they all feed the same lock.
Item {
    id: root

    required property var lock
    required property string screenName

    // the clock and the notch are drawn on the origin screen only; the rest are dimmed
    readonly property bool primary: PillState.originName === "" || screenName === PillState.originName

    // 0 = just locked, 1 = settled
    property real t: 0
    NumberAnimation on t {
        from: 0
        to: 1
        duration: 600
        easing.type: Easing.InOutCubic
        running: true
    }

    // sideways offset of the notch, for the shake after a wrong password
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

    // the surface colour is not reliable on every compositor, so this is drawn as well
    Rectangle {
        anchors.fill: parent
        color: Theme.bg
    }

    Image {
        anchors.fill: parent
        source: root.lock.wallpaperPath !== "" ? "file://" + root.lock.wallpaperPath : ""
        sourceSize.width: root.width
        sourceSize.height: root.height
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        opacity: status === Image.Ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
    }

    // the dim
    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(Theme.bg, 0.65)
        opacity: root.t
    }

    Text {
        visible: root.primary
        text: Qt.formatDateTime(clock.date, "HH:mm")
        color: Qt.alpha(Theme.fg, 0.9)
        font.family: Theme.fontFamilyDisplay
        font.bold: true
        font.pixelSize: Math.round(root.height * 0.28)
        // from the notch's middle to the screen's middle, growing as it goes
        scale: 0.06 + 0.94 * root.t
        opacity: root.t
        x: (root.width - width) / 2
        y: (PillState.pillTop + PillState.pillHeight / 2 - height / 2) * (1 - root.t)
            + (root.height / 2 - height / 2) * root.t
    }

    // the notch: grows from the bar pill into the password field
    Item {
        id: card

        readonly property real fromW: PillState.pillWidth
        readonly property real fromH: PillState.pillHeight

        visible: root.primary
        width: fromW + (280 - fromW) * root.t
        height: fromH + (46 - fromH) * root.t
        x: (root.width - width) / 2 + root.shake
        y: PillState.pillTop
    }

    Notch {
        visible: root.primary
        bodyWidth: card.width
        bodyHeight: card.height
        x: card.x - bodyX
        y: card.y
    }

    // the lock icon, the typed characters as dots (or what to type), and Caps Lock. Fades in
    // during the second half of the morph, like the pickers' content.
    Item {
        visible: root.primary
        x: card.x
        y: card.y
        width: card.width
        height: card.height
        opacity: Math.max(0, (root.t - 0.5) * 2)

        Text {
            id: icon
            x: 16
            anchors.verticalCenter: parent.verticalCenter
            text: "󰌾"
            color: root.lock.failed ? Theme.alert : Qt.alpha(Theme.fg, 0.6)
            font.family: Theme.fontFamily
            font.pixelSize: 16
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
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: root.lock.failed ? "Wrong password" : "Password"
            color: root.lock.failed ? Theme.alert : Qt.alpha(Theme.fg, 0.4)
            font.family: Theme.fontFamilySans
            font.pixelSize: 13
        }

        Row {
            anchors.left: icon.right
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Repeater {
                model: Math.min(root.lock.buffer.length, 20)

                Rectangle {
                    width: 7
                    height: 7
                    radius: 3.5
                    color: Theme.fg
                }
            }
        }

        Text {
            visible: Locks.shown
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            text: Locks.label
            color: Theme.accent
            font.family: Theme.fontFamilySans
            font.pixelSize: 10
            font.letterSpacing: 1
        }
    }

    // Keyboard: characters go to the password, Backspace removes one, Enter checks it, Esc clears it
    Item {
        anchors.fill: parent
        focus: true
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
