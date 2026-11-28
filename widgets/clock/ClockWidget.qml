import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import "../../services"

// The time and date on the wallpaper, as bare type with no card: two lines need no
// container. It starts top-left, beside the todo widget. Nothing on it is clickable.
// Hidden while the overview is open.
PanelWindow {
    id: root

    screen: PillState.originScreen
    anchors {
        left: WidgetLayout.hasLeft("clock")
        right: WidgetLayout.hasRight("clock")
        top: WidgetLayout.hasTop("clock")
        bottom: WidgetLayout.hasBottom("clock")
    }
    margins {
        left: WidgetLayout.insetX("clock")
        right: WidgetLayout.insetX("clock")
        top: WidgetLayout.insetY("clock")
        bottom: WidgetLayout.insetY("clock")
    }
    // room around the text for its shadow, and the same inset as the text in the cards
    readonly property int pad: 16
    implicitWidth: Math.ceil(col.implicitWidth) + 2 * pad
    implicitHeight: Math.ceil(col.implicitHeight) + 2 * pad

    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "quickshell-clock"
    // an empty region: clicks go through to the wallpaper
    mask: Region {}

    Component.onCompleted: WidgetLayout.register("clock", root)

    visible: WidgetLayout.shown("clock") && !Overview.open

    // the lines sit against the side the widget is anchored to, so they do not shift
    // as the digits change width: 0 left, 1 right, 0.5 centred
    readonly property real align: WidgetLayout.hasLeft("clock") ? 0
        : WidgetLayout.hasRight("clock") ? 1 : 0.5

    // set in the layout edit mode; the type is sized by it, so it stays sharp
    readonly property real zoom: WidgetLayout.scaleOf("clock")

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Column {
        id: col
        x: root.pad
        y: root.pad

        // a halo in the background colour keeps the text readable on any wallpaper
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Theme.bg
            shadowBlur: 1.0
            blurMax: 16
        }

        Text {
            x: (col.width - width) * root.align
            text: Qt.formatDateTime(clock.date, UserSettings.clockFormat)
            color: Theme.fg
            // SF Rounded bold, as the bar's, the strip's and the lock's clock
            font.family: Theme.fontFamilyRounded
            font.pixelSize: Math.round(64 * root.zoom)
            font.bold: true
        }

        Text {
            x: (col.width - width) * root.align
            text: Qt.formatDate(clock.date, "dddd, MMMM d")
            color: Qt.alpha(Theme.fg, 0.8)
            font.family: Theme.fontFamilySans
            font.pixelSize: Math.round(15 * root.zoom)
        }
    }
}
