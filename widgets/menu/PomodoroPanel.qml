import QtQuick
import "../../services"
import "../../services/menu"

// Pomodoro tab, in two views. Day: the day's focus time and a grid with one row
// per hour and one cell per 5 minutes (darker = more focus). Week: the current
// week, Sunday to Saturday, as rows, each with its focus time and finished work sessions.
// Pomodoro work time counts as focus even when no window has focus. The timer
// runs in a compact strip at the bottom. The switch shows or hides the focus
// widget.
Item {
    id: panel

    // the Loader in the menu sizes this panel
    anchors.fill: parent

    // false: the day grid; true: the week list
    property bool weekView: false

    // work sessions finished today, and the dots they fill: four per cycle
    readonly property int pomos: AppUsage.pomodoros(AppUsage.dayKey(), AppUsage.revision)
    readonly property int setFilled: Pomodoro.phase === "long" ? 4 : pomos % 4
    readonly property var slots: AppUsage.focusSlots(AppUsage.dayKey(), AppUsage.revision)
    readonly property real totalSec: AppUsage.focusTotal(AppUsage.dayKey(), AppUsage.revision)

    // the current week, Sunday to Saturday; days after today have no focus yet
    readonly property var weekDays: {
        const now = new Date()
        const sunday = now.getDate() - now.getDay()
        const out = []
        for (let i = 0; i < 7; i++) {
            const d = new Date(now.getFullYear(), now.getMonth(), sunday + i)
            const key = Qt.formatDate(d, "yyyy-MM-dd")
            out.push({
                label: Qt.formatDate(d, "ddd"),
                sec: AppUsage.focusTotal(key, AppUsage.revision),
                pomos: AppUsage.pomodoros(key, AppUsage.revision)
            })
        }
        const peak = Math.max(1, ...out.map(d => d.sec))
        out.forEach(d => d.share = d.sec / peak)
        return out
    }
    readonly property real weekSec: weekDays.reduce((s, d) => s + d.sec, 0)

    function fmt(secs) {
        const m = Math.floor(secs / 60)
        const s = secs % 60
        return String(m).padStart(2, "0") + ":" + String(s).padStart(2, "0")
    }

    readonly property string readout: Pomodoro.done ? "00:00"
        : fmt(Pomodoro.active ? Pomodoro.remaining : Pomodoro.minutes * 60)

    Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 12
        height: 18

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: panel.weekView
                ? "week  " + AppUsage.fmtHms(panel.weekSec)
                : "focus  " + AppUsage.fmtHms(panel.totalSec)
            color: Theme.fg
            font.family: Theme.fontFamilyAlt
            font.pixelSize: 13
            font.bold: true
        }

        WidgetSwitch {
            id: desktopSwitch
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            label: "desktop"
            checked: AppUsage.focusWidgetShown
            onToggled: AppUsage.toggleFocusWidget()
        }

        // day | week, the selected view in the accent colour
        Row {
            anchors.right: desktopSwitch.left
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            Repeater {
                model: ["day", "week"]

                Text {
                    required property string modelData
                    readonly property bool selected: (panel.weekView ? "week" : "day") === modelData
                    text: modelData
                    color: selected ? Theme.accent : Qt.alpha(Theme.fg, 0.5)
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    Behavior on color { ColorAnimation { duration: 120 } }

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -4
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panel.weekView = modelData === "week"
                    }
                }
            }
        }
    }

    // day view: 24 hour rows of twelve 5-minute cells; the label marks every sixth hour
    Column {
        id: grid
        visible: !panel.weekView
        anchors.top: header.bottom
        anchors.topMargin: 10
        anchors.left: parent.left
        anchors.leftMargin: 12
        width: parent.width - 24
        spacing: 1

        Repeater {
            model: 24

            Row {
                id: hourRow
                required property int index
                width: grid.width
                height: 4
                spacing: 1

                Text {
                    width: 16
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    text: hourRow.index % 6 === 0 ? String(hourRow.index).padStart(2, "0") : ""
                    color: Qt.alpha(Theme.fg, 0.4)
                    font.family: Theme.fontFamily
                    font.pixelSize: 7
                }

                Repeater {
                    model: 12

                    Rectangle {
                        required property int index
                        readonly property real sec: panel.slots[hourRow.index * 12 + index] ?? 0

                        width: (hourRow.width - 16 - 12) / 12
                        height: hourRow.height
                        radius: 1
                        // a full 5 minutes is the darkest cell
                        color: sec > 0
                            ? Qt.alpha(Theme.accent, 0.3 + 0.7 * Math.min(sec / 300, 1))
                            : Qt.alpha(Theme.fg, 0.07)
                    }
                }
            }
        }
    }

    // week view: one row per day, Sunday first; the bar is that day's focus against the busiest day
    Column {
        id: weekList
        visible: panel.weekView
        // centred in the space between the header and the timer strip
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -4
        anchors.left: parent.left
        anchors.leftMargin: 12
        width: parent.width - 24
        spacing: 4

        Repeater {
            model: panel.weekDays

            Row {
                id: dayRow
                required property var modelData
                width: weekList.width
                height: 12
                spacing: 8

                Text {
                    width: 22
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    text: dayRow.modelData.label
                    color: Qt.alpha(Theme.fg, 0.6)
                    font.family: Theme.fontFamilyAlt
                    font.pixelSize: 11
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 22 - 40 - 22 - 3 * parent.spacing
                    height: 4
                    radius: 2
                    color: Qt.alpha(Theme.fg, 0.07)

                    Rectangle {
                        width: parent.width * dayRow.modelData.share
                        height: parent.height
                        radius: parent.radius
                        color: Theme.accent
                    }
                }
                Text {
                    width: 40
                    height: parent.height
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                    text: AppUsage.fmt(dayRow.modelData.sec)
                    color: Theme.fg
                    font.family: Theme.fontFamilyAlt
                    font.pixelSize: 11
                }
                Text {
                    width: 22
                    height: parent.height
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                    text: dayRow.modelData.pomos > 0 ? dayRow.modelData.pomos + "×" : ""
                    color: Theme.accent
                    font.family: Theme.fontFamilyAlt
                    font.pixelSize: 11
                }
            }
        }
    }

    // the pomodoro: readout, play or pause, stop, the phase, and the cycle dots
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 12
        height: 26
        spacing: 14

        Text {
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            text: panel.readout
            color: Pomodoro.done ? Theme.red : Theme.fg
            font.family: Theme.fontFamilyAlt
            font.pixelSize: 16
            font.bold: true
        }

        Text {
            id: mainBtn
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            text: Pomodoro.done ? "" : Pomodoro.running ? "󰏤" : "󰐊"
            visible: !Pomodoro.done
            color: mainMouse.containsMouse ? Theme.accent : Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: 18
            Behavior on color { ColorAnimation { duration: 120 } }

            MouseArea {
                id: mainMouse
                anchors.fill: parent
                anchors.margins: -6
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (Pomodoro.running)
                        Pomodoro.pause()
                    else if (Pomodoro.paused)
                        Pomodoro.resume()
                    else
                        Pomodoro.start()
                }
            }
        }

        Text {
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            text: "󰓛"
            visible: Pomodoro.active || Pomodoro.done
            color: stopMouse.containsMouse ? Theme.alert : Qt.alpha(Theme.fg, 0.6)
            font.family: Theme.fontFamily
            font.pixelSize: 18
            Behavior on color { ColorAnimation { duration: 120 } }

            MouseArea {
                id: stopMouse
                anchors.fill: parent
                anchors.margins: -6
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Pomodoro.stop()
            }
        }

        // which session the timer is on; the durations come from the config file
        Text {
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            text: Pomodoro.phase === "work" ? "work"
                : Pomodoro.phase === "short" ? "short break" : "long break"
            color: Qt.alpha(Theme.fg, 0.6)
            font.family: Theme.fontFamilyAlt
            font.pixelSize: 11
        }

        // one dot per work session in the current cycle of four; the set
        // shows full through the long break and empties when work resumes
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            Repeater {
                model: 4

                Rectangle {
                    required property int index
                    width: 6
                    height: 6
                    radius: 3
                    color: index < panel.setFilled ? Theme.accent : Qt.alpha(Theme.fg, 0.15)
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
            }
        }
    }
}
