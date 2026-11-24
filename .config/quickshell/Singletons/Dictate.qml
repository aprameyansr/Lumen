pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * 声 Dictation. One key (the `dictate` global bind in binds.lua, Right Alt by
 * default) drives the whole flow on the resting pill, which never changes shape:
 * the clock row gives way to live mic bars while talking and a small spinner
 * while the words are worked out, then the clock comes back.
 *
 * Hold the key past `holdMs` to talk; letting go finishes. Two quick taps lock
 * the take so the key can be let go; the next press finishes. A lone short tap
 * does nothing, so a stray brush of the key never flashes the pill.
 *
 * Mic levels come from a headless cava on the default input source, spawned
 * only while listening so the idle cost is nil.
 *
 * Recognition runs locally: `svc` is the dictation service
 * (~/.local/share/lumen-dictate/dictated.py, Parakeet through sherpa-onnx),
 * alive only while dictation is enabled so turning it off gives the memory
 * back. Recording starts the moment the key goes down, before the hold is
 * confirmed, so the first word is never clipped; a tap that turns out not to
 * be a hold just drops it. In `teaching` mode (the Vocabulary page) a take is
 * transcribed raw and handed back through `heard` instead of being typed.
 */
Singleton {
    id: root

    /** "" | "listening" | "locked" | "working" */
    property string state: ""
    readonly property bool active: state !== ""
    readonly property bool live: state === "listening" || state === "locked"

    /** Monitor the take started on; only that pill shows it. */
    property string mon: ""

    readonly property int bars: 14
    property var levels: []

    /**
     * Laptop mics carry a loud, steady hiss, so a fixed gate can't separate it
     * from speech. Each band tracks its own noise floor instead: it drops at
     * once to a quieter frame and creeps up only over a few seconds, so steady
     * hiss sinks into the floor while speech, which comes and goes, stands
     * above it and fills the strip over `gainSpan`.
     */
    property var noise: []

    /**
     * Automatic gain on top of the floor: mics differ by 30x or more (a laptop
     * array against Bluetooth earbuds), so the strip scales to the loudest
     * recent speech above the floor. The peak jumps up at once and relaxes
     * over a few seconds; `minSpan` stops it from blowing hiss up to full bars
     * in a silent room, and the last take's peak seeds the next so the first
     * syllable already lands at the right height.
     */
    readonly property real minSpan: 0.004
    property real peak: 0.03
    property real lastPeak: 0.03

    readonly property int holdMs: 220
    readonly property int tapGapMs: 350

    property bool down: false
    property double lastTapEnd: 0
    /** A press that already did its job (lock or finish) swallows its own release. */
    property bool consumed: false

    /**
     * The key as people say it, read from the `dictate` line in binds.lua so a
     * rebind on the Keybinds page shows up in Settings straight away.
     */
    property string keyLabel: "Right Alt"

    readonly property var keyNames: ({
            "Alt_R": "Right Alt",
            "Alt_L": "Left Alt",
            "Control_R": "Right Ctrl",
            "Control_L": "Left Ctrl",
            "Shift_R": "Right Shift",
            "Shift_L": "Left Shift",
            "Super_R": "Right Super",
            "Super_L": "Left Super",
            "SUPER": "Super",
            "CTRL": "Ctrl",
            "ALT": "Alt",
            "SHIFT": "Shift"
        })

    function prettyCombo(combo) {
        return combo.split("+").map(function (p) {
            const k = p.trim();
            return root.keyNames[k] || (k.length === 1 ? k.toUpperCase() : k);
        }).join(" + ");
    }

    FileView {
        path: Quickshell.env("HOME") + "/.config/hypr/modules/binds.lua"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const lines = text().split("\n");
            const mod = (text().match(/^local mod = "([^"]*)"/m) || [])[1] || "SUPER";
            for (const l of lines) {
                if (l.indexOf("quickshell:dictate") === -1 || l.trim().indexOf("--") === 0)
                    continue;
                const m = l.match(/hl\.bind\(\s*(mod\s*\.\.\s*)?"([^"]*)"/);
                if (m) {
                    root.keyLabel = root.prettyCombo((m[1] ? mod : "") + m[2]);
                    return;
                }
            }
        }
    }

    /**
     * Right after the shell (re)starts Hyprland.focusedMonitor stays null until
     * the next focus change, which left a take on "no monitor" and no pill
     * showed it. Fall back to the monitor flagged focused, then the first one.
     */
    function focusedMon() {
        if (Hyprland.focusedMonitor)
            return Hyprland.focusedMonitor.name;
        const ms = Hyprland.monitors.values;
        const f = ms.find(m => m && m.focused) || ms[0];
        return f ? f.name : "";
    }

    function begin(nextState) {
        if (!root.active)
            root.mon = root.focusedMon();
        root.state = nextState;
    }

    // ── service ──

    readonly property string home: Quickshell.env("HOME")
    readonly property string svcDir: home + "/.local/share/lumen-dictate"
    property bool installed: false
    property bool ready: false
    /** The Vocabulary page is listening for a sample instead of dictating. */
    property bool teaching: false
    signal heard(string text)
    /**
     * Real sound is arriving from the mic. A Bluetooth mic is silent for about
     * a second while it switches to headset mode; the bars stay dim until then
     * so it's clear when to start talking.
     */
    property bool micHot: false

    /** The engine actually running, and why it isn't the one picked (if so). */
    property string engine: ""
    property string engineNote: ""

    /** Picking another engine restarts the service with it. */
    Connections {
        target: Flags
        function onDictateEngineChanged() {
            if (!svc.running)
                return;
            root.cancel();
            root.ready = false;
            root.engine = "";
            svc.running = false;
            engineRestart.restart();
        }
    }
    Timer {
        id: engineRestart
        interval: 400
        onTriggered: if (Flags.dictateEnabled && root.installed)
            svc.running = true
    }

    /** Last thing typed, for anything that wants to show it. */
    property string lastText: ""

    function send(obj) {
        if (svc.running)
            svc.write(JSON.stringify(obj) + "\n");
    }

    Process {
        running: true
        command: ["test", "-x", root.svcDir + "/venv/bin/python"]
        onExited: code => root.installed = (code === 0)
    }

    Process {
        id: svc
        running: Flags.dictateEnabled && root.installed
        stdinEnabled: true
        command: [root.svcDir + "/venv/bin/python", "-u", root.svcDir + "/dictated.py", "--engine", Flags.dictateEngine]
        onRunningChanged: if (!running)
            root.ready = false
        stdout: SplitParser {
            onRead: line => {
                let m;
                try {
                    m = JSON.parse(line);
                } catch (e) {
                    return;
                }
                if (m.event === "engine") {
                    root.engine = m.name;
                    root.engineNote = m.note || "";
                    /** The picked model didn't load (Whisper fell back to Parakeet): say so once. */
                    if (root.engineNote.length > 0)
                        root.notifyUser(root.engineNote);
                } else if (m.event === "ready") {
                    root.ready = true;
                } else if (m.event === "done") {
                    root.lastText = m.text;
                    root.record(m.text, m.raw || "");
                    root.settle();
                } else if (m.event === "heard") {
                    root.heard(m.text);
                    root.settle();
                } else if (m.event === "hot") {
                    root.micHot = true;
                } else if (m.event === "empty") {
                    root.settle();
                } else if (m.event === "error") {
                    root.settle();
                    root.notifyUser(m.msg);
                }
            }
        }
        /** A crash while still wanted earns one relaunch after a beat, never a tight loop. */
        onExited: if (Flags.dictateEnabled && root.installed)
            relaunch.restart()
    }

    Timer {
        id: relaunch
        interval: 3000
        onTriggered: if (Flags.dictateEnabled && root.installed && !svc.running)
            svc.running = true
    }

    Process {
        id: notify
    }

    function notifyUser(msg) {
        notify.command = ["notify-send", "-a", "Dictation", "-i", "audio-input-microphone", "Dictation", msg];
        notify.running = true;
    }

    // ── history and word count ──

    /**
     * Every typed take, newest first, plus running totals kept apart from the
     * list so removing an entry never takes words off the count. Lives in
     * history.json beside the service; capped at `historyCap` entries.
     */
    readonly property string historyPath: root.svcDir + "/history.json"
    readonly property int historyCap: 300
    property var history: []
    property int totalWords: 0
    property int takes: 0
    property double since: 0
    property var days: ({})

    /** Rolls over at midnight so "today" restarts at zero. */
    property string todayKey: Qt.formatDate(new Date(), "yyyy-MM-dd")
    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: root.todayKey = Qt.formatDate(new Date(), "yyyy-MM-dd")
    }
    readonly property int todayWords: root.days[root.todayKey] || 0
    /** Typing at ~40 wpm against speaking at ~130 wpm. */
    readonly property int minutesSaved: Math.round(root.totalWords * (1 / 40 - 1 / 130))

    function countWords(text) {
        return text.replace(/^\s*(?:-|\d+\.)\s+/gm, "").split(/\s+/).filter(w => /[\w]/.test(w)).length;
    }

    /** `raw` is what the engine heard before commands and vocabulary, kept for diagnosing. */
    function record(text, raw) {
        if (!text || !text.trim())
            return;
        const n = root.countWords(text);
        const now = Date.now();
        const key = Qt.formatDate(new Date(now), "yyyy-MM-dd");
        const d = Object.assign({}, root.days);
        d[key] = (d[key] || 0) + n;
        root.days = d;
        root.totalWords += n;
        root.takes += 1;
        if (!root.since)
            root.since = now;
        root.history = [
            {
                t: now,
                text: text,
                raw: raw || "",
                words: n
            }
        ].concat(root.history).slice(0, root.historyCap);
        root.saveHistory();
    }

    function removeHistory(t) {
        root.history = root.history.filter(h => h.t !== t);
        root.saveHistory();
    }

    /** Drop every history entry; the word count is kept apart and stays. */
    function wipeHistory() {
        root.history = [];
        root.saveHistory();
    }

    function copyText(text) {
        copyProc.command = ["wl-copy", "--", text];
        copyProc.running = true;
    }

    function saveHistory() {
        historyWriter.setText(JSON.stringify({
            totalWords: root.totalWords,
            takes: root.takes,
            since: root.since,
            days: root.days,
            items: root.history
        }, null, 1) + "\n");
    }

    Process {
        id: copyProc
    }

    FileView {
        path: root.historyPath
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const d = JSON.parse(text());
                root.history = d.items || [];
                root.totalWords = d.totalWords || 0;
                root.takes = d.takes || 0;
                root.since = d.since || 0;
                root.days = d.days || {};
            } catch (e) {}
        }
    }

    FileView {
        id: historyWriter
        path: root.historyPath
        atomicWrites: true
        printErrors: false
    }

    function settle() {
        work.stop();
        if (root.state === "working")
            root.state = "";
    }

    function finish() {
        root.state = "working";
        root.send({
            cmd: "stop",
            mode: root.teaching ? "teach" : "type"
        });
        work.restart();
    }

    function cancel() {
        holdTimer.stop();
        work.stop();
        if (root.state !== "" && root.state !== "working")
            root.send({
                cmd: "cancel"
            });
        root.state = "";
        root.down = false;
        root.consumed = false;
    }

    function press() {
        if (!Flags.dictateEnabled || !svc.running || root.down)
            return;
        root.down = true;
        root.consumed = false;
        if (root.state === "working")
            return;
        if (root.state === "locked") {
            root.consumed = true;
            root.finish();
            return;
        }
        root.micHot = false;
        root.send({
            cmd: "start",
            mic: Flags.dictateMic
        });
        if (Date.now() - root.lastTapEnd < root.tapGapMs) {
            root.consumed = true;
            root.lastTapEnd = 0;
            root.begin("locked");
            return;
        }
        holdTimer.restart();
    }

    function release() {
        if (!root.down)
            return;
        root.down = false;
        if (root.consumed) {
            root.consumed = false;
            return;
        }
        if (holdTimer.running) {
            holdTimer.stop();
            root.send({
                cmd: "cancel"
            });
            root.lastTapEnd = Date.now();
            return;
        }
        if (root.state === "listening")
            root.finish();
    }

    onStateChanged: {
        if (root.state === "listening" || root.state === "locked") {
            if (!cavaProc.running) {
                root.peak = Math.max(root.minSpan, root.lastPeak * 0.6);
                cavaProc.running = true;
            }
        } else {
            cavaProc.running = false;
            root.levels = [];
            root.noise = [];
            if (root.peak > root.minSpan)
                root.lastPeak = root.peak;
        }
    }

    Connections {
        target: Flags
        function onDictateEnabledChanged() {
            if (!Flags.dictateEnabled)
                root.cancel();
        }
    }

    Timer {
        id: holdTimer
        interval: root.holdMs
        onTriggered: if (root.down)
            root.begin("listening")
    }

    /** Safety net: never leave the spinner up if the service goes quiet. */
    Timer {
        id: work
        interval: 30000
        onTriggered: root.settle()
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "dictate"
        description: "Dictation: hold to talk, double-tap to lock"
        onPressed: root.press()
        onReleased: root.release()
    }

    readonly property string config: "[general]\n" + "bars = " + (bars / 2) + "\nframerate = 60\nautosens = 0\nsensitivity = 300\n" + "lower_cutoff_freq = 90\nhigher_cutoff_freq = 4000\n" + "[input]\nmethod = pipewire\nsource = SRC\n" + "[output]\nmethod = raw\nraw_target = /dev/stdout\ndata_format = ascii\n" + "ascii_max_range = 100000\nbar_delimiter = 59\nframe_delimiter = 10\n" + "channels = mono\nmono_option = average\n" + "[smoothing]\nnoise_reduction = 0.6\n"

    /**
     * Half the bands, mirrored outward from the centre, so the strip reads as a
     * voice swelling from the middle rather than a left-to-right spectrum.
     */
    Process {
        id: cavaProc
        command: ["sh", "-c", "if [ \"$2\" != builtin ] && [ \"$2\" != default ] && pactl list sources short 2>/dev/null | awk '{print $2}' | grep -qxF -- \"$2\"; then src=$2; " + "elif [ \"$2\" != default ]; then src=$(pactl list sources short 2>/dev/null | awk '$2 ~ /^alsa_input\\./ && $2 !~ /monitor/ {print $2; exit}'); fi; " + "[ -n \"$src\" ] || src=$(pactl get-default-source 2>/dev/null); [ -n \"$src\" ] || src=auto; " + "printf '%s' \"$1\" | sed \"s|^source = SRC$|source = $src|\" | exec cava -p /dev/stdin", "_", root.config, Flags.dictateMic]
        stdout: SplitParser {
            onRead: line => {
                if (!line || !root.live)
                    return;
                const parts = line.split(";");
                const half = root.bars / 2;
                const h = [];
                const nf = root.noise;
                const ex = [];
                let top = 0;
                for (let i = 0; i < half; i++) {
                    const v = (parseInt(parts[i]) || 0) / 100000;
                    let f = nf[i];
                    if (f === undefined || v < f)
                        f = f === undefined ? v : f * 0.6 + v * 0.4;
                    else
                        f += (v - f) * 0.004;
                    nf[i] = f;
                    /** Under ~1.6x the floor is the hiss breathing, not a voice. */
                    const e = Math.max(0, v - f * 1.6);
                    ex.push(e);
                    if (e > top)
                        top = e;
                }
                root.peak = top > root.peak ? root.peak * 0.4 + top * 0.6 : Math.max(root.minSpan, root.peak * 0.994);
                for (let i = 0; i < half; i++)
                    h.push(Math.min(1, Math.sqrt(ex[i] / root.peak) * 0.95));
                const out = [];
                for (let i = half - 1; i >= 0; i--)
                    out.push(h[i]);
                for (let i = 0; i < half; i++)
                    out.push(h[i]);
                root.levels = out;
            }
        }
    }
}
