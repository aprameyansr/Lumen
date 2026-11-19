pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * One shared watcher for the internal laptop backlight. Every pill carries an
 * Osd, so reading /sys here keeps it a single loop instead of one per monitor.
 * The brightness file is re-read in-process once a frame (sysfs never signals
 * plain writes), so a key press lands in the OSD within ~16 ms with no process
 * spawns; the old shell loop forked cat and sleep a hundred times a second and
 * lagged behind volume. `changed` fires on a new reading after the initial
 * populate, so login doesn't flash the OSD. Machines without a backlight find
 * no device and never start the timer.
 */
Singleton {
    id: root

    property real brightness: 0
    property int lastPct: -1
    property string dev: ""
    property int maxRaw: 0

    signal changed()

    function ingest(raw) {
        if (root.maxRaw <= 0 || isNaN(raw))
            return;
        var pct = Math.round(raw * 100 / root.maxRaw);
        if (pct === root.lastPct)
            return;
        var seen = root.lastPct >= 0;
        root.brightness = Math.max(0, Math.min(100, pct)) / 100.0;
        root.lastPct = pct;
        if (seen)
            root.changed();
    }

    Process {
        command: ["sh", "-c", "ls /sys/class/backlight 2>/dev/null | head -n1"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.dev = this.text.trim()
        }
    }

    FileView {
        id: maxFile
        path: root.dev ? "/sys/class/backlight/" + root.dev + "/max_brightness" : ""
        blockLoading: true
        printErrors: false
        onLoaded: root.maxRaw = parseInt(text().trim(), 10) || 0
    }

    FileView {
        id: curFile
        path: root.dev ? "/sys/class/backlight/" + root.dev + "/brightness" : ""
        blockLoading: true
        printErrors: false
        onLoaded: root.ingest(parseInt(text().trim(), 10))
    }

    Timer {
        interval: 16
        repeat: true
        running: root.dev.length > 0 && root.maxRaw > 0
        onTriggered: curFile.reload()
    }
}
