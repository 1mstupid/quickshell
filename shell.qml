//@ pragma UseQApplication

import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import "./services"
import "./widgets/app_launcher"
import "./widgets/bar"
import "./widgets/bar/media"
import "./widgets/clipboard"
import "./widgets/dashboard"
import "./widgets/drawer"
import "./widgets/focus_notch"
import "./widgets/border"
import "./widgets/habits"
import "./widgets/layout"
import "./widgets/media_notch"
import "./widgets/notifications"
import "./widgets/power_menu"
import "./widgets/todo"
import "./widgets/usage"
import "./widgets/wallpaper"

ShellRoot {

    NotificationToast {}

    NotificationHistory {}

    ControlDrawer {}

    WallpaperPicker {}

    AppLauncher {}

    PowerMenu {}

    Clipboard {}

    Dashboard {}

    FocusNotch {}

    MediaWidget {}

    MediaNotch {}

    Usage {}

    FocusWidget {}

    TodoWidget {}

    HabitsWidget {}

    LayoutEditor {}

    Variants {
        model: Quickshell.screens

        Bar {}
    }
    Variants {
        model: Quickshell.screens

        ScreenBorder {}
    }

    property var notifications: Notifications.notifications
    // referenced so the singleton starts with the shell
    property var sleepReminder: SleepReminder
}
