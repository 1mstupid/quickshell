import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../../services"

// Workspaces for one output, read from Hyprland. The workspace list updates
// itself, so there is no subprocess to restart. Special workspaces (id <= 0)
// are left out.
Item {
    id: root

    property string outputName: ""

    readonly property var workspaces: Hyprland.workspaces.values
        .filter(w => w.id > 0 && w.monitor?.name === outputName)
        .map(w => ({
            index: w.id,
            id: w.id,
            name: w.name,
            focused: w.active,
            occupied: (w.lastIpcObject?.windows ?? 0) > 0
        }))
        .sort((a, b) => a.index - b.index)
}
