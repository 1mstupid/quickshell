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
import "./widgets/menu"
import "./widgets/border"
import "./widgets/notifications"
import "./widgets/power_menu"
import "./widgets/usage"
import "./widgets/wallpaper"

ShellRoot {

    NotificationToast {}

    WallpaperPicker {}

    AppLauncher {}

    PowerMenu {}

    Clipboard {}

    Dashboard {}

    Menu {}

    MediaWidget {}

    Usage {}

    FocusWidget {}

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
