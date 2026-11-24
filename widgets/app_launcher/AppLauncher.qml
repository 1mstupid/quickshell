import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import "../../services"
import "../notch"
import "Modes.js" as Modes
import "FileSearch.js" as FileSearch

// The launcher grows out of the bar pill, the same way the wallpaper picker does. It is an
// item of the origin bar's window (Bar.qml), so it drops from the pill with no seam.
Item {
    id: root

    visible: false
    anchors.fill: parent

    IpcHandler {
        target: "applauncher"
        function toggle(): void { AppLauncherState.toggle() }
    }

    // ── Geometry ───────────────────────────────────────────────────────────
    readonly property int maxVisible: 7
    readonly property int itemH: 44
    readonly property int panelW: 400
    readonly property int chromeH: 90
    readonly property int maxPanelH: chromeH + maxVisible * itemH

    property real startW: PillState.pillWidth
    property real startH: PillState.pillHeight
    property real t: 0
    // a card closed back to the pill is hidden there: the elastic close reaches the pill early, and
    // a card left over it hid the bar's content until the morph finished
    onTChanged: if (morph.running && morph.to === 0 && t <= 0) visible = false

    property real panelH: chromeH + Math.max(1, Math.min(results.length, maxVisible)) * itemH
    Behavior on panelH {
        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
    }

    // ── State ────────────────────────────────______________________________
    property string searchQuery: ""
    property int selectedIndex: 0
    property int selectionAnchor: -1
    property var selectedFiles: []

    readonly property bool isSearching: searchQuery.trim() !== ""
    property string mode: ""
    readonly property var modeInfo: Modes.find(mode)

    // Clipboard tracking properties for copy/cut/paste
    property string fileClipboardAction: ""
    property var fileClipboardPaths: []

    function copySelectedFiles() {
        var targets = selectedFiles.length > 0 ? selectedFiles : (results[selectedIndex] && results[selectedIndex].kind === "file" ? [results[selectedIndex].value] : []);
        if (targets.length === 0) return;

        fileClipboardAction = "copy";
        fileClipboardPaths = targets;

        var uriList = targets.map(p => fileUri(p)).join("\n");
        Quickshell.execDetached(["wl-copy", "--type", "text/uri-list", uriList]);
        
        selectedFiles = [];
        selectionAnchor = -1;
    }

    function cutSelectedFiles() {
        var targets = selectedFiles.length > 0 ? selectedFiles : (results[selectedIndex] && results[selectedIndex].kind === "file" ? [results[selectedIndex].value] : []);
        if (targets.length === 0) return;

        fileClipboardAction = "cut";
        fileClipboardPaths = targets;

        var uriList = targets.map(p => fileUri(p)).join("\n");
        Quickshell.execDetached(["wl-copy", "--type", "text/uri-list", uriList]);

        selectedFiles = [];
        selectionAnchor = -1;
    }

    function pasteFilesIntoCurrentDirectory() {
        if (fileClipboardPaths.length === 0 || mode !== "file") return;

        var q = searchQuery.trim();
        var targetDir = "";

        // 1. Resolve current directory from searchQuery
        if (q === "" || q === "~") {
            targetDir = Quickshell.env("HOME") || "/home";
        } else if (q.startsWith("~")) {
            targetDir = q.replace("~", Quickshell.env("HOME") || "/home");
        } else if (q.endsWith("/")) {
            targetDir = q;
        } else {
            var lastSlash = q.lastIndexOf("/");
            if (lastSlash !== -1) {
                targetDir = q.substring(0, lastSlash + 1);
            } else {
                targetDir = Quickshell.env("HOME") + "/";
            }
        }

        // Ensure targetDir is an absolute path for gio
        if (targetDir.startsWith("./")) {
            targetDir = (Quickshell.env("HOME") || "/") + targetDir.substring(1);
        }

        console.log("Pasting into target directory:", targetDir);
        console.log("Files to paste:", fileClipboardPaths);

        var cmd = [];
        if (fileClipboardAction === "cut") {
            cmd = ["gio", "move"].concat(fileClipboardPaths).concat([targetDir]);
        } else {
            cmd = ["gio", "copy"].concat(fileClipboardPaths).concat([targetDir]);
        }

        Quickshell.execDetached(cmd);

        if (fileClipboardAction === "cut") {
            fileClipboardPaths = [];
            fileClipboardAction = "";
        }

        // Trigger a refresh of the file list view
        var refreshQ = searchQuery;
        searchQuery = "";
        searchQuery = refreshQ;
    }

    property var results: {
        var q = searchQuery.trim();

        if (mode === "calc") {
            if (Calc.result === "" || Calc.resultFor !== q)
                return [];
            return [{ kind: "calc", title: Calc.result, subtitle: q, icon: "", glyph: modeInfo.glyph, value: Calc.result }];
        }

        if (mode === "file") {
            if (Files.entriesFor !== q)
                return [];
            return Files.entries.map(function (e) {
                return { kind: "file", title: e.name, subtitle: FileSearch.describe(e, Files.meta[e.path], Date.now()), icon: "", glyph: e.glyph, value: e.path, next: e.next };
            });
        }

        if (mode === "clipboard") {
            const all = ClipboardHistory.entries;
            return all.filter(e => q === "" || e.preview.toLowerCase().indexOf(q.toLowerCase()) !== -1).map(function (e) {
                return { kind: "clipboard", title: e.preview, subtitle: "Clipboard entry", icon: "", glyph: modeInfo ? modeInfo.glyph : "📋", value: e };
            });
        }

        var hints = Modes.hints(searchQuery);
        if (hints.length > 0) {
            return hints.map(function (m) {
                return { kind: "mode", title: m.title, subtitle: m.subtitle, icon: "", glyph: m.glyph, value: m.name };
            });
        }

        return appResults(q.toLowerCase());
    }

    onResultsChanged: {
      selectedIndex = 0;
      selectionAnchor = -1;
    }
    
    function toggleFileSelection(path) {
        var next = selectedFiles.slice();
        var index = next.indexOf(path);

        if (index !== -1)
            next.splice(index, 1);
        else
            next.push(path);

        selectedFiles = next;

        if (selectedFiles.length === 0)
            selectionAnchor = -1;
    }

    function goToParentDirectory() {
        if (mode !== "file" || searchQuery.trim() === "")
            return false;

        var q = searchQuery.trim();
        if (q.charAt(0) !== "/" && q.charAt(0) !== "~")
            return false;

        var path = q.replace(/\/+$/, "");
        var slash = path.lastIndexOf("/");

        if (slash < 0)
            return false;

        var parent = path.slice(0, slash + 1);
        if (parent === "")
            parent = "/";

        searchInput.text = parent;
        searchInput.cursorPosition = searchInput.text.length;
        return true;
    }

    function appResults(q) {
        // an entry is hidden if either its StartupWMClass or its id is blocked, since
        // a window's class may match either one
        var vals = DesktopEntries.applications.values.filter(function (e) {
            return !AppUsage.blockedNow(e.startupClass) && !AppUsage.blockedNow(e.id);
        });
        var list;

        if (q !== "") {
            list = vals.filter(function (e) {
                if (e.name.toLowerCase().indexOf(q) !== -1) return true;
                if (e.genericName && e.genericName.toLowerCase().indexOf(q) !== -1) return true;
                for (var i = 0; i < e.keywords.length; i++)
                    if (e.keywords[i].toLowerCase().indexOf(q) !== -1) return true;
                return false;
            }).sort(function (a, b) { return a.name.localeCompare(b.name); });
        } else {
            var recent = AppLauncherState.recentIds;
            list = vals.slice().sort(function (a, b) {
                var ai = recent.indexOf(a.id);
                var bi = recent.indexOf(b.id);
                if (ai !== -1 && bi !== -1) return ai - bi;
                if (ai !== -1) return -1;
                if (bi !== -1) return 1;
                return a.name.localeCompare(b.name);
            });
        }

        return list.map(function (e) {
            return { kind: "app", title: e.name, subtitle: subtitleOf(e), icon: e.icon, glyph: "", entry: e };
        });
    }

    readonly property string emptyText: {
        if (mode === "calc") return searchQuery.trim() === "" ? "Type an expression" : (Calc.busy ? "" : "No result");
        if (mode === "file") return searchQuery.trim() === "" ? "Type a name, or / or ~ to browse" : (Files.busy ? "" : "Nothing found");
        if (mode === "clipboard") return ClipboardHistory.entries.length === 0 ? "Nothing copied yet" : "No matches";
        return "No apps found";
    }

    function subtitleOf(entry) {
        if (entry.genericName && entry.genericName !== "") return entry.genericName;
        if (entry.categories && entry.categories.length > 0) return entry.categories[0];
        return "";
    }

    function openLauncher() {
        if (!PillState.claim("applauncher")) return;
        Sounds.play("open");
        const from = PillState.takeOver();
        startW = from.w;
        startH = from.h;
        mode = "";
        selectionAnchor = -1;
        selectedFiles = [];
        searchInput.text = "";
        if (ClipboardHistory.reload) ClipboardHistory.reload();
        visible = true;
        morph.stop();
        morph.from = root.t;
        morph.to = 1;
        morph.start();
    }

    function giveWay() {
        PillState.takeoverW = card.width;
        PillState.takeoverH = card.height;
        morph.stop();
        visible = false;
        t = 0;
    }

    function close() {
        if (!visible) return;
        Sounds.play("close");
        if (PillState.owner === "applauncher")
            PillState.returning = true;
        startW = PillState.pillWidth;
        startH = PillState.pillHeight;
        morph.stop();
        morph.from = root.t;
        morph.to = 0;
        morph.start();
    }

    NumberAnimation {
        id: morph
        target: root
        property: "t"
        duration: PillState.morphMs
        easing.type: PillState.openEase
        easing.period: PillState.easePeriod
        onFinished: {
            if (root.t < 0.5) {
                root.visible = false;
                if (PillState.owner === "applauncher") PillState.owner = "";
            }
        }
    }

    Connections {
        target: AppLauncherState
        function onLauncherVisibleChanged() {
            if (AppLauncherState.launcherVisible) root.openLauncher();
            else root.close();
        }
    }

    Connections {
        target: PillState
        function onOwnerChanged() {
            if (PillState.owner !== "applauncher" && root.visible) {
                if (PillState.owner !== "") root.giveWay();
                AppLauncherState.launcherVisible = false;
            }
        }
    }

    onVisibleChanged: {
        if (visible) searchInput.forceActiveFocus();
    }

    function enterMode(name) {
        mode = name;
        selectionAnchor = -1;
        selectedFiles = [];
        searchInput.text = "";
        if (name === "clipboard" && ClipboardHistory.reload) {
            ClipboardHistory.reload();
        }
    }

    function fileUri(path) {
        return "file://" + path.split("/").map(encodeURIComponent).join("/");
    }

    function deleteSelectedFiles() {
        var targets = selectedFiles.length > 0 ? selectedFiles : (results[selectedIndex] && results[selectedIndex].kind === "file" ? [results[selectedIndex].value] : []);
        if (targets.length === 0) return;

        var cmd = ["gio", "trash"].concat(targets);
        Quickshell.execDetached(cmd);
        selectedFiles = [];
        selectionAnchor = -1;
        if (mode === "file") {
            var q = searchQuery;
            searchQuery = "";
            searchQuery = q;
        }
    }

    function activate(r) {
        if (!r) return;
        
        if (r.kind === "file" && selectedFiles.length > 1) {
            if (r.next !== "") {
                searchInput.text = r.next;
                return;
            }
            for (var i = 0; i < selectedFiles.length; i++) {
                Quickshell.execDetached(["xdg-open", selectedFiles[i]]);
            }
            AppLauncherState.hide();
            return;
        }

        if (r.kind === "app") {
            Sounds.play("launch");
            AppLauncherState.recordLaunch(r.entry.id);
            r.entry.execute();
            AppLauncherState.hide();
        } else if (r.kind === "mode") {
            enterMode(r.value);
        } else if (r.kind === "calc") {
            Quickshell.execDetached(["wl-copy", "--", r.value]);
            AppLauncherState.hide();
        } else if (r.kind === "file") {
            if (r.next !== "") {
                searchInput.text = r.next;
            } else {
                Sounds.play("launch");
                Quickshell.execDetached(["xdg-open", r.value]);
                AppLauncherState.hide();
            }
        } else if (r.kind === "clipboard") {
            ClipboardHistory.copy(r.value);
            AppLauncherState.hide();
        }
    }

    function forgetEntry(r) {
        if (r && r.kind === "clipboard") {
            ClipboardHistory.remove(r.value);
        }
    }

    function shareSelected() {
        var r = results[selectedIndex];
        if (!r || r.kind !== "file") return;

        var targets = selectedFiles.length > 0 ? selectedFiles : [r.value];
        for (var i = 0; i < targets.length; i++) {
            ShareService.addFile(targets[i]);
        }
        ShareService.open();

        if (ShareService.selectedDevice !== "") {
            ShareService.send();
        } else {
            console.log("Share warning: 'shareDevice' is not configured in config.toml ([settings])");
        }
        AppLauncherState.hide();
    }

    function navigate(delta, isShiftPressed) {
        if (results.length === 0) return;

        const nextIndex = Math.max(
            0,
            Math.min(results.length - 1, selectedIndex + delta)
        );

        if (nextIndex === selectedIndex) return;

        if (isShiftPressed && mode === "file") {
            if (selectionAnchor === -1)
                selectionAnchor = selectedIndex;

            selectedIndex = nextIndex;

            var start = Math.min(selectionAnchor, selectedIndex);
            var end = Math.max(selectionAnchor, selectedIndex);

            var next = selectedFiles.slice();

            for (var i = start; i <= end; i++) {
                var item = results[i];

                if (item && item.kind === "file"
                        && next.indexOf(item.value) === -1) {
                    next.push(item.value);
                }
            }

            selectedFiles = next;
        } else {
            selectionAnchor = -1;
            selectedIndex = nextIndex;
        }

        listView.positionViewAtIndex(selectedIndex, ListView.Contain);
    }

    readonly property color accentFill: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18)

    Binding {
        target: Calc
        property: "expression"
        value: root.mode === "calc" ? root.searchQuery.trim() : ""
    }

    Binding {
        target: Files
        property: "query"
        value: root.mode === "file" ? root.searchQuery.trim() : ""
    }

    // only the card takes clicks: the bar's window masks its input to this while the launcher is open
    readonly property Item maskItem: outline

    Notch {
        id: outline
        bodyWidth: card.width
        bodyHeight: card.height
        x: card.x - bodyX
        y: card.y
    }

    Rectangle {
        id: card

        readonly property real fromW: root.startW
        readonly property real fromH: root.startH

        width: fromW + (root.panelW - fromW) * Math.max(0, root.t)
        height: fromH + (root.panelH - fromH) * Math.max(0, root.t)
        x: (root.width - width) / 2
        y: PillState.pillTop
        color: "transparent"
        clip: true

        Column {
            anchors {
                top: parent.top
                topMargin: 12
                left: parent.left
                leftMargin: 12
                right: parent.right
                rightMargin: 12
            }
            spacing: 8
            opacity: Math.max(0, (root.t - 0.5) * 2)

            Item {
                width: parent.width
                height: 34

                Text {
                    id: searchGlyph
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.modeInfo ? root.modeInfo.glyph : "󰍉"
                    color: root.modeInfo ? Theme.primary : Qt.alpha(Theme.fg, 0.45)
                    font.family: Theme.fontFamily
                    font.pixelSize: 15
                }

                TextInput {
                    id: searchInput
                    anchors.left: searchGlyph.right
                    anchors.leftMargin: 10
                    anchors.right: countText.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.fg
                    selectionColor: root.accentFill
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    clip: true

                    onTextChanged: {
                        if (root.mode === "") {
                            var p = Modes.parse(text);
                            if (p.mode !== "") {
                                root.mode = p.mode;
                                text = p.text;
                                return;
                            }
                        }
                        root.searchQuery = text;
                    }

                    Keys.onPressed: function (event) {
                        var shiftPressed = (event.modifiers & Qt.ShiftModifier) !== 0;
                        var ctrlPressed = (event.modifiers & Qt.ControlModifier) !== 0;

                        if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) {
                            root.navigate(-1, shiftPressed);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
                            root.navigate(1, shiftPressed);
                            event.accepted = true;
                        } else if (ctrlPressed && event.key === Qt.Key_C && root.mode === "file") {
                            root.copySelectedFiles();
                            event.accepted = true;
                        } else if (ctrlPressed && event.key === Qt.Key_X && root.mode === "file") {
                            root.cutSelectedFiles();
                            event.accepted = true;
                        } else if (ctrlPressed && event.key === Qt.Key_P && root.mode === "file") {
                            root.pasteFilesIntoCurrentDirectory();
                            event.accepted = true;
                        } else if (ctrlPressed && event.key === Qt.Key_D) {
                            root.navigate(root.maxVisible, shiftPressed);
                            event.accepted = true;
                        } else if (ctrlPressed && event.key === Qt.Key_U) {
                            root.navigate(-root.maxVisible, shiftPressed);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Home) {
                            root.navigate(-root.results.length, shiftPressed);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_End) {
                            root.navigate(root.results.length, shiftPressed);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Delete && root.mode === "file") {
                            root.deleteSelectedFiles();
                            event.accepted = true;
                        } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && ctrlPressed && shiftPressed) {
                            root.shareSelected();
                            event.accepted = true;
                        } else if (ctrlPressed && event.key === Qt.Key_Return ||
                                   ctrlPressed && event.key === Qt.Key_Enter) {
                            var current = root.results[root.selectedIndex];

                            if (root.mode === "file" && current && current.kind === "file") {
                                root.toggleFileSelection(current.value);
                                event.accepted = true;
                            }
                        } else if (ctrlPressed && event.key === Qt.Key_Space) {
                            root.selectedFiles = [];
                            root.selectionAnchor = -1;
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            if (shiftPressed) {
                                var currentItem = root.results[root.selectedIndex];
                                if (currentItem && currentItem.kind === "file") {
                                    if (root.selectionAnchor === -1) root.selectionAnchor = root.selectedIndex;
                                    root.toggleFileSelection(currentItem.value);
                                    event.accepted = true;
                                    return;
                                }
                            }
                            root.activate(root.results[root.selectedIndex]);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Delete && ctrlPressed && root.mode === "clipboard") {
                            root.forgetEntry(root.results[root.selectedIndex]);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Backspace
                                 && root.mode === "file"
                                 && text === "") {
                                    root.mode = "";
                                    event.accepted = true;
                                  }
                         else if (event.key === Qt.Key_Escape) {
                            AppLauncherState.hide();
                            event.accepted = true;
                        }
                    }
                }

                Text {
                    id: countText
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.mode !== "" ? (root.mode === "clipboard" ? root.results.length + " / " + ClipboardHistory.entries.length : (root.fileClipboardPaths.length > 0 ? (root.fileClipboardAction === "cut" ? "✂️ " : "📋 ") + root.fileClipboardPaths.length + " staged" : (root.selectedFiles.length > 0 ? root.selectedFiles.length + " selected" : ""))) : root.results.length + " / " + DesktopEntries.applications.values.length
                    color: Theme.fg
                    opacity: 0.35
                    font.family: Theme.fontFamilyAlt
                    font.pixelSize: 11
                }
            }

            ListView {
                id: listView
                width: parent.width
                height: Math.max(1, Math.min(root.results.length, root.maxVisible)) * root.itemH
                model: root.results
                clip: true
                interactive: false

                Text {
                    anchors.centerIn: parent
                    visible: root.results.length === 0
                    text: root.emptyText
                    color: Theme.fg
                    opacity: 0.28
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                }

                MouseArea {
                    anchors.fill: parent
                    onWheel: function (wheel) {
                        if (wheel.angleDelta.y < 0) root.navigate(1, false);
                        else root.navigate(-1, false);
                    }
                }

                delegate: Rectangle {
                    id: appRow
                    required property var modelData
                    required property int index

                    width: listView.width
                    height: root.itemH
                    radius: 10
                    
                    readonly property bool isFileSelected: modelData.kind === "file" && root.selectedFiles.indexOf(modelData.value) !== -1
                    color: root.selectedIndex === index ? root.accentFill : (isFileSelected ? Qt.alpha(Theme.primary, 0.1) : "transparent")
                    
                    Behavior on color { ColorAnimation { duration: 100 } }
                    opacity: dragHandler.active ? 0.4 : (isFileSelected ? 0.55 : 1)
                    Behavior on opacity { NumberAnimation { duration: 100 } }

                    readonly property bool sel: root.selectedIndex === index

                    Row {
                        anchors {
                            left: parent.left
                            right: returnHint.left
                            verticalCenter: parent.verticalCenter
                            leftMargin: 10
                            rightMargin: 8
                        }
                        spacing: 12

                        Item {
                            width: 26
                            height: 26
                            anchors.verticalCenter: parent.verticalCenter

                            Image {
                                id: appIcon
                                anchors.fill: parent
                                source: appRow.modelData.icon && appRow.modelData.icon !== "" ? "image://icon/" + appRow.modelData.icon : ""
                                smooth: true
                                mipmap: true
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: appIcon.status !== Image.Ready
                                text: appRow.modelData.glyph !== "" ? appRow.modelData.glyph : appRow.modelData.title.charAt(0).toUpperCase()
                                font.family: Theme.fontFamily
                                font.pixelSize: appRow.modelData.glyph !== "" ? 17 : 14
                                font.weight: appRow.modelData.glyph !== "" ? Font.Normal : Font.Bold
                                color: appRow.sel ? Theme.primary : Theme.fg
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 26 - parent.spacing
                            spacing: 2

                            Text {
                                width: parent.width
                                text: appRow.modelData.title
                                elide: Text.ElideRight
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.weight: appRow.sel ? Font.Medium : Font.Normal
                                color: Theme.fg
                                opacity: appRow.sel ? 1 : 0.8
                            }

                            Text {
                                width: parent.width
                                visible: text !== ""
                                text: appRow.modelData.kind === "file"
                                    ? (appRow.modelData.subtitle || "File")
                                    : appRow.modelData.kind === "folder"
                                        ? (appRow.modelData.subtitle || "Folder")
                                        : appRow.modelData.subtitle
                                elide: Text.ElideRight
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                color: appRow.modelData.kind === "folder"
                                    ? Theme.primary : Theme.fg
                                opacity: appRow.modelData.kind === "folder" ? 0.75 : 0.35
                            }
                        }
                    }

                    Text {
                        id: returnHint
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter

                        text: appRow.isFileSelected
                            ? "✓"
                            : appRow.modelData.kind === "folder"
                                ? "→"
                                : appRow.modelData.kind === "file"
                                    ? "↵"
                                    : "↵"

                        visible: appRow.sel || appRow.isFileSelected
                        color: appRow.modelData.kind === "folder"
                            ? Theme.primary : Theme.fg
                        opacity: 0.7
                        font.family: Theme.fontFamilyAlt
                        font.pixelSize: 12
                    }

                    DragHandler {
                        id: dragHandler
                        target: null
                    }

                    Drag.active: dragHandler.active
                    Drag.dragType: Drag.Automatic
                    Drag.supportedActions: Qt.CopyAction

                    Drag.mimeData: appRow.modelData.kind === "file"
                        ? (() => {
                            var urisToDrag = (root.selectedFiles.indexOf(appRow.modelData.value) !== -1 && root.selectedFiles.length > 1)
                                ? root.selectedFiles
                                : [appRow.modelData.value];
                            
                            var uriString = urisToDrag.map(p => root.fileUri(p)).join("\r\n") + "\r\n";
                            return { "text/uri-list": uriString };
                        })()
                        : ({})

                    Drag.hotSpot.x: dragHandler.centroid.position.x
                    Drag.hotSpot.y: dragHandler.centroid.position.y

                    HoverHandler {
                        onHoveredChanged: {
                            if (hovered) root.selectedIndex = appRow.index
                        }
                    }

                    TapHandler {
                        onTapped: function(event) {
                            if (event.modifiers & Qt.ShiftModifier && appRow.modelData.kind === "file") {
                                if (root.selectionAnchor === -1) root.selectionAnchor = root.selectedIndex;
                                root.toggleFileSelection(appRow.modelData.value);
                            } else {
                                root.selectionAnchor = -1;
                                root.selectedFiles = [];
                                root.activate(appRow.modelData);
                            }
                        }
                    }
                }
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.mode === "calc" ? "↵ copy    ⌫ back    esc close" : 
                      root.mode === "file" ? (root.fileClipboardPaths.length > 0 ? "↵ open    ^c copy    ^x cut    ^p paste here    ⌫ delete    esc close" : "↵ open    ^c copy    ^x cut    ⌫ delete    esc close") : 
                      root.mode === "clipboard" ? "↵ copy    ^⌫ delete    ⌫ back    esc close" : 
                      "↑↓ move    ↵ launch    esc close"
                color: Theme.fg
                opacity: 0.25
                font.family: Theme.fontFamilyAlt
                font.pixelSize: 10
            }
        }
    }
}
