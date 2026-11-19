import QtQuick
import QtQuick.Effects
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
    // the pill stays at the top and drops a little in the lock state
    readonly property real lockTop: PillState.pillTop + 20
    // the bar clock's size (widgets/bar/Clock.qml): the centre clock lands on it
    readonly property real barClockPx: 15
    // t clamped to 0..1: the elastic overshoot moves position, but not widths, blur or scale
    readonly property real tClamped: Math.max(0, Math.min(1, t))
    Behavior on t {
        NumberAnimation {
            duration: PillState.lockMs
            easing.type: PillState.openEase
            easing.period: PillState.easePeriod
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
            if (!root.lock.unlocking)
                return
            root.t = 0
            // the bar's pill comes back now, so its fade finishes while the lock is still up
            if (root.primary && PillState.owner === "lock") {
                PillState.progress = 0
                PillState.owner = ""
            }
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

    // The desktop behind the lock: blurred as the lock comes in
    Image {
        anchors.fill: parent
        source: root.lock.wallpaperPath !== "" ? "file://" + root.lock.wallpaperPath : ""
        sourceSize.width: root.width
        sourceSize.height: root.height
        fillMode: Image.PreserveAspectCrop
        layer.enabled: true
        layer.effect: MultiEffect {
            blurEnabled: true
            blurMax: 64
            blur: root.tClamped
        }
    }

    // A transparent veil over the blurred desktop
    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(Theme.bg, 0.35)
        opacity: root.t
    }

    // Center clock emerges from the notch and returns to it on unlock
    Text {
        id: timeText
        visible: root.primary
        text: Qt.formatDateTime(clock.date, UserSettings.clockFormat)
        color: Qt.alpha(Theme.fg, 0.9)
        font.family: Theme.fontFamilyRounded
        font.bold: true
        font.pixelSize: Math.round(root.height * 0.28)
        
        transformOrigin: Item.Center
        readonly property real endScale: root.barClockPx / font.pixelSize
        scale: endScale + (1 - endScale) * root.tClamped
        opacity: Math.min(1, root.tClamped * 1.5)

        // Screen center vs Exact Notch body center (accounting for shoulders via bodyX)
        readonly property real screenCenterX: root.width / 2
        readonly property real screenCenterY: root.height / 2

        readonly property real notchCenterX: notch.x + notch.bodyX + notch.bodyWidth / 2
        readonly property real notchCenterY: notch.y + notch.bodyHeight / 2

        x: (screenCenterX * root.t + notchCenterX * (1 - root.t)) - (width / 2)
        y: (screenCenterY * root.t + notchCenterY * (1 - root.t)) - (height / 2)
    }

    // Fixed-size notch matching the bar pill exactly
    // Dynamically expanding notch
    Notch {
        id: notch

        readonly property int dotsCount: Math.min(root.lock.buffer.length, 24)
        readonly property real dotsWidth: dotsCount > 0 ? (dotsCount * 6 + (dotsCount - 1) * 5) : 0
        readonly property real capsWidth: capsLabel.visible ? (capsLabel.implicitWidth + 12) : 0
        // the glyph alone until something is typed, then the dots take its place
        readonly property real contentWidth: dotsCount > 0 ? dotsWidth : 14
        // leftMargin (12) + content + rightMargin (12) + caps
        readonly property real neededWidth: 24 + contentWidth + capsWidth

        // eases when typing starts or stops; bodyWidth moves between the bar's pill and this
        property real fitWidth: neededWidth
        Behavior on fitWidth {
            NumberAnimation {
                duration: 140
                easing.type: Easing.OutCubic
            }
        }

        visible: root.primary
        bodyWidth: PillState.pillWidth + (fitWidth - PillState.pillWidth) * root.tClamped
        bodyHeight: PillState.pillHeight
        x: (root.width - bodyWidth) / 2 - bodyX + root.shake
        // unlocking returns it to the bar's place, through the same progress t
        y: PillState.pillTop + (root.lockTop - PillState.pillTop) * root.t
    }

    // Password content inside the pill silhouette
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
            visible: root.lock.buffer.length === 0
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

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5

            Repeater {
                model: notch.dotsCount

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
