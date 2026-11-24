pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property var entries: []
    property string error: ""
    readonly property bool busy: worker.running
    signal stored(int files, int folders, int failures)

    function run(mode, arguments) {
        if (busy)
            return false;
        error = "";
        result = null;
        operation = mode;
        worker.command = ["python3", "-B", Quickshell.shellDir + "/lib/file_shelf.py", mode].concat(arguments);
        worker.running = true;
        return true;
    }

    function refresh() {
        run("list", []);
    }
    function store(urls) {
        return run("store", urls);
    }
    function remove(id) {
        return run("remove", [id]);
    }

    property string operation: ""
    property var result: null

    Component.onCompleted: refresh()

    Process {
        id: worker
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.result = JSON.parse(text);
                } catch (_error) {
                    root.result = null;
                }
            }
        }
        onExited: {
            const reply = root.result;
            const mode = root.operation;
            if (reply && reply.entries)
                root.entries = reply.entries;
            const errors = reply ? reply.errors : ["The file shelf could not be read"];
            root.error = errors[0] || "";
            if (mode === "store")
                root.stored(reply?.files ?? 0, reply?.folders ?? 0, errors.length);
        }
    }
}
