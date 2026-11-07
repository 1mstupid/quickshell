pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "FileSearch.js" as FileSearch

// The launcher's file mode. A line starting with "/" or "~" lists that folder
// (ls); anything else is searched for under $HOME (fd). Same shape as Calc: one
// short process at a time, started once typing pauses. The typed text goes in
// as an argument, never through a shell.
Singleton {
    id: root

    property string query: ""
    // the rows, and the query they answer (they differ while typing)
    property var entries: []
    property string entriesFor: ""
    readonly property bool busy: debounce.running || proc.running

    readonly property string home: Quickshell.env("HOME")
    // what the running process was started with
    property string ran: ""

    onQueryChanged: {
        if (query === "") {
            debounce.stop();
            entries = [];
            entriesFor = "";
            return;
        }
        debounce.restart();
    }

    Timer {
        id: debounce
        interval: 150
        onTriggered: root.run()
    }

    function run() {
        // a process is still going: onExited starts the next one
        if (proc.running)
            return;
        ran = query;
        var c = FileSearch.classify(ran, home);
        // timeout so a slow disk cannot leave the launcher waiting. fd skips
        // hidden and git-ignored files by default; -F reads the text as plain
        // text, not a regex, so "(" cannot make it fail.
        if (c.kind === "browse")
            proc.command = ["timeout", "3", "ls", "-1ApL", "--", c.dir];
        else
            proc.command = ["timeout", "5", "fd", "--max-results", "50", "--color", "never", "--absolute-path", "-F", "--", c.pattern, home];
        proc.running = true;
    }

    Process {
        id: proc
        stdout: StdioCollector {
            onStreamFinished: {
                var c = FileSearch.classify(root.ran, root.home);
                root.entries = c.kind === "browse" ? FileSearch.parseLs(text, c.dir, c.frag, root.home) : FileSearch.parseFd(text, root.home);
                root.entriesFor = root.ran;
            }
        }
        onExited: {
            if (root.query !== "" && root.query !== root.ran)
                root.run();
        }
    }
}
