pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "Modes.js" as Modes

// The launcher's calculator. qalc has no QML binding, so each expression runs
// as one short process, started once typing pauses and never two at a time.
// The expression goes in as an argument, never through a shell.
Singleton {
    id: root

    property string expression: ""
    // the answer, and the expression it answers (they differ while typing)
    property string result: ""
    property string resultFor: ""
    readonly property bool busy: debounce.running || proc.running

    // what the running process was started with
    property string ran: ""

    onExpressionChanged: {
        if (expression === "") {
            debounce.stop();
            result = "";
            resultFor = "";
            return;
        }
        debounce.restart();
    }

    Timer {
        id: debounce
        interval: 120
        onTriggered: root.run()
    }

    function run() {
        // a process is still going: onExited starts the next one
        if (proc.running)
            return;
        ran = expression;
        // the leading space keeps "-5+3" from being read as a qalc option;
        // timeout so a hung qalc cannot leave the launcher waiting
        proc.command = ["timeout", "3", "qalc", "-t", " " + ran];
        proc.running = true;
    }

    Process {
        id: proc
        stdout: StdioCollector {
            onStreamFinished: {
                root.result = Modes.answer(text, root.ran);
                root.resultFor = root.ran;
            }
        }
        onExited: {
            if (root.expression !== "" && root.expression !== root.ran)
                root.run();
        }
    }
}
