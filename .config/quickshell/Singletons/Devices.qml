pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Single owner of external-monitor brightness (ddcutil) for the mixer.
 * DDC monitors come from `ddcutil detect` (one brightness fader each); the
 * setvcp/getvcp wire format lives here so every caller speaks it the same.
 * The internal laptop backlight (eDP, no DDC/CI) is driven separately via
 * brightnessctl and gated on /sys/class/backlight being present, so a desktop
 * exposes nothing.
 */
Singleton {
    id: root

    /**
     * DDC-capable monitors from `ddcutil detect`: [{ bus, label }] with label
     * taken from the DRM connector, falling back to the I2C bus number.
     */
    property var ddcMonitors: []

    /** True once an internal backlight has been found under /sys/class/backlight. */
    property bool backlightPresent: false

    /** Current internal-backlight level, 0..100. */
    property int backlightPct: 75

    function detect() {
        ddcDetect.running = true;
        blDetect.running = true;
    }

    function setBrightness(bus, pct) {
        Quickshell.execDetached(["timeout", "3", "ddcutil", "setvcp", "10", String(pct), "--bus", bus, "--noverify"]);
    }

    /**
     * Sets the internal laptop backlight to `pct` percent via brightnessctl.
     * No-op effect on machines without /sys/class/backlight (brightnessctl
     * simply finds no device), and inert when brightnessctl is absent.
     */
    function setBacklight(pct) {
        root.backlightPct = Math.round(Math.max(1, Math.min(100, pct)));
        root.liveSent = -1;
        Quickshell.execDetached(["brightnessctl", "set", root.backlightPct + "%"]);
    }

    /**
     * Live variant for fader drags: one brightnessctl in flight at a time, and
     * the newest level goes out the moment the previous write lands (~6 ms), so
     * the panel tracks the fader like volume does without queuing a backlog.
     */
    property int liveWant: -1
    property int liveSent: -1

    function setBacklightLive(pct) {
        root.backlightPct = Math.round(Math.max(1, Math.min(100, pct)));
        root.liveWant = root.backlightPct;
        if (!blLive.running)
            root.pushLive();
    }

    function pushLive() {
        if (root.liveWant < 0 || root.liveWant === root.liveSent)
            return;
        root.liveSent = root.liveWant;
        blLive.command = ["brightnessctl", "-q", "set", root.liveSent + "%"];
        blLive.running = true;
    }

    Process {
        id: blLive
        onExited: root.pushLive()
    }

    /**
     * Parses a `ddcutil getvcp --brief` line, returning the current brightness
     * percent or -1 when no value is present.
     */
    function parseBrightness(text) {
        var m = text.match(/C\s+(\d+)\s+/);
        return m ? parseInt(m[1], 10) : -1;
    }

    Process {
        id: ddcDetect
        command: ["ddcutil", "detect", "--brief"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var mons = [];
                var blocks = this.text.split(/\bDisplay \d+/);
                for (let i = 0; i < blocks.length; i++) {
                    const bus = /I2C bus:\s+\/dev\/i2c-(\d+)/.exec(blocks[i]);
                    const conn = /DRM connector:\s+card\d+-(\S+)/.exec(blocks[i]);
                    if (bus && (!conn || !conn[1].startsWith("eDP-")))
                        mons.push({
                            bus: bus[1],
                            label: conn ? conn[1] : "BUS " + bus[1]
                        });
                }
                root.ddcMonitors = mons;
            }
        }
    }

    Process {
        id: blDetect
        command: ["sh", "-c", "dev=$(ls /sys/class/backlight 2>/dev/null | head -n1); [ -n \"$dev\" ] || exit 0; max=$(cat /sys/class/backlight/$dev/max_brightness); cur=$(cat /sys/class/backlight/$dev/brightness); echo \"$(( cur * 100 / max ))\""]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var v = parseInt(this.text.trim(), 10);
                if (!isNaN(v)) {
                    root.backlightPct = Math.max(1, Math.min(100, v));
                    root.backlightPresent = true;
                }
            }
        }
    }
}
