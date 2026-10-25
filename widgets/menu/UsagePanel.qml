import QtQuick
import "../../services"

// Usage tab: today's focus time per app, most used first. An app with a limit
// shows its limit, and its line fills toward that limit.
Item {
    id: panel

    // the Loader in the menu sizes this panel
    anchors.fill: parent

    readonly property var rows: AppUsage.totals(AppUsage.dayKey(), AppUsage.revision)
    readonly property real topSec: rows.length > 0 ? rows[0].sec : 1
    readonly property real totalSec: rows.reduce((s, r) => s + r.sec, 0)

    Text {
        anchors.centerIn: parent
        visible: panel.rows.length === 0
        horizontalAlignment: Text.AlignHCenter
        text: "No app time yet today.\nLimits go in ~/.local/xdg/config/app-limits"
        color: Theme.disabled
        font.family: Theme.fontFamily
        font.pixelSize: 11
    }

    Text {
        id: heading
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: 12
        visible: panel.rows.length > 0
        text: "today  " + AppUsage.fmt(panel.totalSec)
        color: Qt.alpha(Theme.fg, 0.6)
        font.family: Theme.fontFamily
        font.pixelSize: 11
    }

    Column {
        anchors.top: heading.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 12
        anchors.topMargin: 10
        spacing: 8

        Repeater {
            model: panel.rows.slice(0, 6)

            Item {
                id: row
                required property var modelData
                readonly property int limit: AppUsage.limits[modelData.app] ?? 0
                readonly property real fill: limit > 0
                    ? Math.min(modelData.sec / (limit * 60), 1)
                    : modelData.sec / panel.topSec

                width: parent.width
                height: 24

                Text {
                    anchors.left: parent.left
                    anchors.right: amount.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.app
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
                Text {
                    id: amount
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: AppUsage.fmt(row.modelData.sec) + (row.limit > 0 ? " / " + row.limit + "m" : "")
                    color: row.limit > 0 && row.modelData.sec >= row.limit * 60
                        ? Theme.alert : Qt.alpha(Theme.fg, 0.5)
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }
                Rectangle {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    height: 2
                    radius: 1
                    color: row.limit > 0 && row.fill >= 1 ? Theme.alert : Theme.accent
                    width: parent.width * row.fill
                }
            }
        }
    }
}
