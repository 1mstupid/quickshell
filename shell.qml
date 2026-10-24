//@ pragma UseQApplication

import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import "./services"
import "./widgets/app_launcher"
import "./widgets/bar"
import "./widgets/bar/media"
import "./widgets/border"
import "./widgets/network"
import "./widgets/notifications"
import "./widgets/power_menu"
import "./widgets/wallpaper"

ShellRoot {

    NotificationToast {}

    WallpaperPicker {}

    AppLauncher {}

    MediaWidget {}

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
    Variants {
        model: Quickshell.screens

        Network {
            property var modelData
            screen: modelData
        }
    }

    property var notifications: Notifications.notifications
}
