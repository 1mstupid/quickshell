//@ pragma UseQApplication

import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import "./services"
import "./widgets/app_launcher"
import "./widgets/bar"
import "./widgets/bar/media"
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

    Menu {}

    MediaWidget {}

    Usage {}

    Variants {
        model: Quickshell.screens

        Bar {}
    }
    Variants {
        model: Quickshell.screens

        ScreenBorder {}
    }
    Variants {
        model: Quickshell.screens
        PowerMenu {
            property var modelData
            screen: modelData
        }
    }

    property var notifications: Notifications.notifications
}
