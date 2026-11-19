pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * 覚 Keep-awake controller. Holds the logind inhibitor for as long as
 * Flags.keepAwake is set, picking its scope from Flags.awakeLid: "awake" also
 * takes the lid switch so a closed lid keeps the machine running, "sleep"
 * blocks only idle so the lid suspends as usual. A timed session ends at
 * Flags.awakeUntil; a minute before a sleep or shutdown it posts a
 * notification, then drops the inhibitor and, a beat later, runs the action
 * (the inhibitor would otherwise block it). Start, end and preset all persist
 * through Flags, so a shell restart resumes the countdown. A deadline missed by
 * more than a couple of minutes (the machine slept through it) just ends the
 * session instead of firing a shutdown on wake.
 */
Singleton {
    id: root

    /** Wall clock, ticking only while a timed session runs. */
    property real now: Date.now()
    property bool warned: false

    /**
     * Session span held in memory as the source of truth. Flags only keeps a
     * copy for restarts: its file is rewritten per property and reloaded on
     * change, so a reload landing between two writes could hand back a stale
     * end and turn a timed session untimed.
     */
    property real from: 0
    property real until: 0
    Component.onCompleted: {
        root.from = Flags.awakeFrom;
        root.until = Flags.awakeUntil;
        root.guard();
    }

    function persist() {
        Flags.awakeFrom = root.from;
        Flags.awakeUntil = root.until;
    }

    /** On with a finite length must always carry an end; off carries none. */
    function guard() {
        if (Flags.keepAwake && root.until <= 0 && Flags.awakeMins > 0)
            root.arm();
        else if (!Flags.keepAwake && root.until > 0) {
            root.from = 0;
            root.until = 0;
            root.persist();
        }
    }

    Connections {
        target: Flags
        function onKeepAwakeChanged() { Qt.callLater(root.guard); }
    }

    readonly property bool on: Flags.keepAwake
    readonly property bool timed: on && root.until > 0
    readonly property real remainingMs: timed ? Math.max(0, root.until - now) : 0
    readonly property real frac: (timed && root.until > root.from)
        ? Math.max(0, Math.min(1, remainingMs / (root.until - root.from))) : 0

    readonly property var endLabels: ({ off: "turn off", sleep: "sleep", poweroff: "shut down" })

    /** "1h 30m", "45m", "∞" for a length in minutes. */
    function durLabel(mins) {
        if (mins <= 0)
            return "∞";
        var h = Math.floor(mins / 60);
        var m = mins % 60;
        return h > 0 ? (m > 0 ? h + "h " + m + "m" : h + "h") : m + "m";
    }

    /** Countdown text: "1:04:09" or "4:09". */
    function clock(ms) {
        var t = Math.ceil(ms / 1000);
        var h = Math.floor(t / 3600);
        var m = Math.floor((t % 3600) / 60);
        var sec = t % 60;
        var mm = (h > 0 && m < 10 ? "0" : "") + m;
        return (h > 0 ? h + ":" : "") + mm + ":" + (sec < 10 ? "0" : "") + sec;
    }

    /** Wall time "HH:MM" for an epoch ms, following the clock's 12/24h setting. */
    function wall(ms) {
        return Qt.formatTime(new Date(ms), Flags.time12h ? "h:mm AP" : "HH:mm");
    }

    function arm() {
        root.now = Date.now();
        root.warned = false;
        root.from = root.now;
        root.until = Flags.awakeMins > 0 ? root.now + Flags.awakeMins * 60000 : 0;
        root.persist();
    }

    function start() {
        root.arm();
        Flags.keepAwake = true;
    }

    function stop() {
        root.from = 0;
        root.until = 0;
        root.persist();
        Flags.keepAwake = false;
        root.warned = false;
    }

    function toggle() {
        if (root.on)
            root.stop();
        else
            root.start();
    }

    /** Pick a length; a running session re-arms from now so the chip means "this long from here". */
    function setMins(mins) {
        Flags.awakeMins = mins;
        if (root.on)
            root.arm();
    }

    /** Push a timed session's end out by `mins`, starting the clock from now if it was untimed. */
    function extend(mins) {
        if (!root.on)
            return;
        root.now = Date.now();
        if (root.until <= 0) {
            root.from = root.now;
            root.until = root.now + mins * 60000;
        } else {
            root.until = Math.max(root.until, root.now) + mins * 60000;
        }
        root.persist();
        root.warned = false;
    }

    function applyPreset(p) {
        Flags.awakeLid = p.lid;
        Flags.awakeEnd = p.end;
        Flags.awakeMins = p.mins;
        root.start();
    }

    function presetMatches(p) {
        return p.lid === Flags.awakeLid && p.mins === Flags.awakeMins && p.end === Flags.awakeEnd;
    }

    function savePreset(name) {
        var n = (name || "").trim();
        if (!n.length)
            return false;
        var list = (Flags.awakePresets || []).filter(function (p) { return p.name.toLowerCase() !== n.toLowerCase(); });
        list.push({ name: n, lid: Flags.awakeLid, mins: Flags.awakeMins, end: Flags.awakeEnd });
        Flags.awakePresets = list;
        return true;
    }

    function deletePreset(i) {
        var list = (Flags.awakePresets || []).slice();
        if (i < 0 || i >= list.length)
            return;
        list.splice(i, 1);
        Flags.awakePresets = list;
    }

    function notify(body) {
        Quickshell.execDetached(["notify-send", "-a", "Keep awake", "-i", "preferences-desktop-screensaver", "Keep awake", body]);
    }

    function tick() {
        root.now = Date.now();
        if (!root.timed)
            return;
        var left = root.until - root.now;
        var end = Flags.awakeEnd;
        if (left <= 0) {
            var missed = left < -120000;
            root.stop();
            if (missed || end === "off") {
                root.notify("Session ended. Idle and lid are back to normal.");
                return;
            }
            endCmd.command = ["systemctl", end === "sleep" ? "suspend" : "poweroff"];
            endDelay.restart();
            return;
        }
        if (!root.warned && left <= 60000 && end !== "off") {
            root.warned = true;
            root.notify((end === "sleep" ? "Sleeping" : "Shutting down") + " in a minute. Open keep awake to stop or extend.");
        }
    }

    Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: root.timed
        onTriggered: root.tick()
    }

    /** Lets the inhibitor process die before the action, which it would otherwise block. */
    Timer {
        id: endDelay
        interval: 1500
        onTriggered: endCmd.running = true
    }

    Process {
        id: endCmd
        command: []
    }

    /**
     * The Wayland IdleInhibitor in shell.qml only pauses the compositor's own
     * idle; hypridle runs its own timer and respects logind inhibitors, so hold
     * one for the session. One process per lid mode, so switching the lid mode
     * mid-session swaps the lock cleanly instead of editing a running command.
     */
    Process {
        running: Flags.keepAwake && Flags.awakeLid !== "sleep"
        command: ["systemd-inhibit", "--what=idle:sleep:handle-lid-switch", "--who=Lumen",
                  "--why=keep awake", "--mode=block", "sleep", "infinity"]
    }

    Process {
        running: Flags.keepAwake && Flags.awakeLid === "sleep"
        command: ["systemd-inhibit", "--what=idle", "--who=Lumen",
                  "--why=keep awake (lid sleeps)", "--mode=block", "sleep", "infinity"]
    }
}
