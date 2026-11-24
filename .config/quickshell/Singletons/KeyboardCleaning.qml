pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool active: false
    property bool busy: false
    property string error: ""

    function toggle() {
        if (busy)
            return;

        error = "";
        busy = true;
        if (active)
            worker.write("stop\n");
        else
            worker.running = true;
    }

    Process {
        id: worker
        stdinEnabled: true
        command: ["systemd-inhibit",
            "--what=handle-power-key:handle-suspend-key:handle-hibernate-key:handle-reboot-key",
            "--mode=block", "--who=Lumen", "--why=Keyboard cleaning",
            "python3", "-u", Quickshell.shellPath("lib/keyboard_cleaning.py")]

        stdout: SplitParser {
            onRead: line => {
                if (line === "active") {
                    root.active = true;
                    root.busy = false;
                } else if (line.startsWith("error: ")) {
                    root.error = line.slice(7);
                }
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim())
                    console.warn("Keyboard cleaning:", text.trim());
            }
        }

        onExited: code => {
            if (code !== 0 && !root.error)
                root.error = root.active ? "Cleaning mode stopped unexpectedly."
                                         : "Could not start keyboard cleaning mode.";
            root.active = false;
            root.busy = false;
        }
    }
}
