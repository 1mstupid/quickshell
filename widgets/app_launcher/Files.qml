pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "FileSearch.js" as FileSearch

// The launcher's file mode. A line starting with "/" or "~" lists that folder
// (ls, one short process at a time, like Calc). Anything else is fuzzy-matched
// in memory against the files under $HOME, which fd lists once when the mode
// opens, so each keystroke is instant. That list is a snapshot of that moment.
// The typed text goes in as an argument, never through a shell.
Singleton {
    id: root

    // true while the file mode is open: it is what triggers the listing
    property bool active: false
    property string query: ""
    // the rows, and the query they answer (they differ while typing)
    property var entries: []
    property string entriesFor: ""
    readonly property bool busy: debounce.running || proc.running || lister.running

    readonly property string home: Quickshell.env("HOME")
    // what the running ls was started with
    property string ran: ""

    // the fd listing, and what the last fuzzy query left of it
    property var items: []
    property bool loaded: false
    property var pool: []
    property string poolFor: ""

    onActiveChanged: {
        items = [];
        pool = [];
        poolFor = "";
        loaded = false;
        if (active)
            load();
    }

    onQueryChanged: {
        if (query === "") {
            debounce.stop();
            entries = [];
            entriesFor = "";
            poolFor = "";
            return;
        }
        debounce.restart();
    }

    Timer {
        id: debounce
        interval: 150
        onTriggered: root.run()
    }

    // fd skips hidden and git-ignored files by default, and the cap keeps a huge
    // home from filling memory. The pattern "." matches every name.
    function load() {
        if (lister.running)
            return;
        lister.command = ["timeout", "15", "fd", "--max-results", "100000", "--color", "never", "--absolute-path", "--", ".", home];
        lister.running = true;
    }

    // a longer query can only match what a shorter one did, so it starts from there
    function refresh() {
        var c = FileSearch.classify(query, home);
        if (c.kind !== "search" || !loaded)
            return;
        var from = poolFor !== "" && query.indexOf(poolFor) === 0 ? pool : items;
        var r = FileSearch.fuzzy(from, c.pattern, 50, home);
        pool = r.pool;
        poolFor = query;
        entries = r.top;
        entriesFor = query;
    }

    function run() {
        var c = FileSearch.classify(query, home);
        if (c.kind === "search") {
            refresh();
            return;
        }
        // a process is still going: onExited starts the next one
        if (c.kind !== "browse" || proc.running)
            return;
        ran = query;
        // timeout so a slow disk cannot leave the launcher waiting
        proc.command = ["timeout", "3", "ls", "-1ApL", "--", c.dir];
        proc.running = true;
    }

    Process {
        id: lister
        stdout: StdioCollector {
            onStreamFinished: {
                // the mode was closed while it ran
                if (!root.active)
                    return;
                root.items = FileSearch.prepare(text, root.home);
                root.loaded = true;
                root.refresh();
            }
        }
    }

    Process {
        id: proc
        stdout: StdioCollector {
            onStreamFinished: {
                var c = FileSearch.classify(root.ran, root.home);
                // the line changed meanwhile: onExited lists it again
                if (c.kind !== "browse" || root.ran !== root.query)
                    return;
                root.entries = FileSearch.parseLs(text, c.dir, c.frag, root.home);
                root.entriesFor = root.ran;
            }
        }
        onExited: {
            if (root.query !== "" && root.query !== root.ran)
                root.run();
        }
    }
}
