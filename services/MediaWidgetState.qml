pragma Singleton
import QtQuick
import Quickshell

// Open state of the media widget. The bar's wave sets it; MediaWidget reacts.
QtObject {
    id: root

    property bool open: false

    function toggle() { open = !open }
    function show()   { open = true }
    function hide()   { open = false }
}
