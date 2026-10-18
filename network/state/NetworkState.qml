pragma Singleton

import QtQuick

QtObject {
    property bool open: false

    function toggle() {
        open = !open
    }

    function show() {
        open = true
    }

    function hide() {
        open = false
    }
}
