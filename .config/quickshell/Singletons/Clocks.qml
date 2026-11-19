pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * 刻 Clock engine behind the clock page: stopwatch, timer and world clock. All
 * state lives in Flags as wall-clock timestamps (a start or an end in epoch ms),
 * never as a ticking counter, so the page can close, the shell can reload and a
 * restart picks up exactly where things were. Nothing ticks while idle: `now`
 * advances once a second only while something runs (the resting pill's
 * readout), the page drives its own per-frame clock, and the timer's end is a
 * single-shot alarm armed for the exact moment.
 *
 * A finished timer posts a critical notification (it breaks through any open
 * page) and plays the system alarm sound. One that ended while the machine was
 * asleep says so with the time it actually ran out.
 *
 * World clock offsets come from `date` per zone, since Qt's JS has no time zone
 * database; they are refetched when the list changes and every half hour so a
 * DST switch lands.
 */
Singleton {
    id: root

    property real now: Date.now()

    /** A timer just ran out (the resting pill pulses its outline). */
    signal finished()

    // ── date formatting ──

    function localeName(lang) {
        return lang === "de" ? "de_DE" : "en_US";
    }

    /** Short weekday name ("Mon", "Mo") for a Date or a weekday number 0-6 from Sunday. */
    function weekday(when, lang) {
        const dow = typeof when === "number" ? when : when.getDay();
        return Qt.locale(localeName(lang)).dayName(dow, Locale.ShortFormat).replace(/\.$/, "");
    }

    /**
     * `when` in a date preset; German drops the abbreviation dots ("Mo 27",
     * "27. Okt") and unknown styles go to Qt as a format string.
     */
    function dateFor(style, lang, when) {
        const d = when || new Date();
        const loc = Qt.locale(localeName(lang));
        const de = lang === "de";
        const day = d.getDate();
        const dayNum = de ? day + "." : String(day);
        const mon = loc.monthName(d.getMonth(), Locale.ShortFormat).replace(/\.$/, "");
        switch (style) {
        case "ddd d":
            return weekday(d, lang) + " " + day;
        case "d MMM":
            return dayNum + " " + mon;
        case "ddd d MMM":
            return weekday(d, lang) + " " + dayNum + " " + mon;
        case "dd.MM.":
            return String(day).padStart(2, "0") + "." + String(d.getMonth() + 1).padStart(2, "0") + ".";
        default:
            return loc.toString(d, style || "ddd d MMM");
        }
    }

    // ── stopwatch ──

    readonly property bool swRunning: Flags.swStart > 0
    readonly property bool swIdle: !swRunning && Flags.swAccum <= 0

    function swElapsedAt(t) {
        return Flags.swAccum + (root.swRunning ? Math.max(0, t - Flags.swStart) : 0);
    }

    function swToggle() {
        var t = Date.now();
        if (root.swRunning) {
            Flags.swAccum = root.swElapsedAt(t);
            Flags.swStart = 0;
        } else {
            Flags.swStart = t;
        }
        root.now = t;
    }

    /** Mark a lap at the current total. Only while running. */
    function swLap() {
        if (!root.swRunning)
            return;
        Flags.swLaps = (Flags.swLaps || []).concat([root.swElapsedAt(Date.now())]);
    }

    function swReset() {
        Flags.swStart = 0;
        Flags.swAccum = 0;
        Flags.swLaps = [];
    }

    // ── timer ──

    readonly property bool tmRunning: Flags.tmEnd > 0
    readonly property bool tmPaused: !tmRunning && Flags.tmLeft > 0
    readonly property bool tmIdle: !tmRunning && !tmPaused

    function tmRemainAt(t) {
        if (root.tmRunning)
            return Math.max(0, Flags.tmEnd - t);
        if (root.tmPaused)
            return Flags.tmLeft;
        return Flags.tmDur;
    }

    /** Share of the current run still left, 1 at the start and 0 at the end; 1 while idle. */
    function tmFracAt(t) {
        if (root.tmIdle || Flags.tmTotal <= 0)
            return 1;
        return Math.max(0, Math.min(1, root.tmRemainAt(t) / Flags.tmTotal));
    }

    /** Start, pause or resume. */
    function tmToggle() {
        if (root.ringing) {
            root.stopAlarm();
            return;
        }
        var t = Date.now();
        if (root.tmRunning) {
            Flags.tmLeft = Math.max(1, Flags.tmEnd - t);
            Flags.tmEnd = 0;
        } else if (root.tmPaused) {
            Flags.tmEnd = t + Flags.tmLeft;
            Flags.tmLeft = 0;
        } else if (Flags.tmDur > 0) {
            Flags.tmTotal = Flags.tmDur;
            Flags.tmEnd = t + Flags.tmDur;
        }
        root.now = t;
    }

    /** Start a fresh `min`-minute timer (from IPC); 0 cancels the running one. */
    function tmStartMinutes(min) {
        root.tmReset();
        if (min > 0) {
            root.tmSet(min * 60000);
            root.tmToggle();
        }
    }

    function tmReset() {
        Flags.tmEnd = 0;
        Flags.tmLeft = 0;
        Flags.tmTotal = 0;
    }

    /** Add time to a running or paused timer (the bar's total grows with it). */
    function tmAdd(ms) {
        if (root.tmRunning)
            Flags.tmEnd = Flags.tmEnd + ms;
        else if (root.tmPaused)
            Flags.tmLeft = Flags.tmLeft + ms;
        else
            return;
        Flags.tmTotal = Flags.tmTotal + ms;
    }

    /** Set the length for the next run; only while idle. */
    function tmSet(ms) {
        if (!root.tmIdle)
            return;
        Flags.tmDur = Math.max(1000, Math.min(100 * 3600000 - 1000, Math.round(ms / 1000) * 1000));
    }

    function tmFire() {
        var t = Date.now();
        var end = Flags.tmEnd;
        var total = Flags.tmTotal;
        root.tmReset();
        var late = t - end > 120000;
        var body = root.fmtDur(total) + " timer is done"
            + (late ? " (ran out at " + root.wallTime(end) + ")" : "");
        Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "Timer", "-i", "alarm-symbolic", "Timer", body]);
        root.finished();
        root.alarmSeen = false;
        root.ringing = true;
        alarmProc.running = false;
        alarmProc.running = true;
    }

    /**
     * The alarm sound, held as a process so it can be cut short: dismissing
     * the "Timer" notification or pressing Stop on the clock page ends it at
     * once instead of letting it play out.
     */
    property bool ringing: false
    property bool alarmSeen: false

    function stopAlarm() {
        root.ringing = false;
        alarmProc.running = false;
    }

    /** A Timer notification is still up in the pill. */
    readonly property bool timerPopupUp: Notifs.popups.some(function (p) { return p && p.appName === "Timer"; })

    /** Super: silence the alarm and clear the Timer notification from the pill, like its ×; it stays in the inbox. */
    function dismissAlarm() {
        root.stopAlarm();
        Notifs.popups.filter(function (p) { return p && p.appName === "Timer"; })
            .forEach(function (p) { Notifs.removePopup(p); });
    }

    Process {
        id: alarmProc
        command: ["pw-play", "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"]
        onExited: root.ringing = false
    }

    /** The notification lands a beat after the sound starts, so only a Timer popup that was seen and then left stops it. */
    Connections {
        target: Notifs
        function onPopupsChanged() {
            if (!root.ringing)
                return;
            var up = Notifs.popups.some(function (p) { return p && p.appName === "Timer"; });
            if (up)
                root.alarmSeen = true;
            else if (root.alarmSeen)
                root.stopAlarm();
        }
    }

    /** Fires at the exact end; re-armed whenever the end moves. */
    Timer {
        id: endAlarm
        running: root.tmRunning
        interval: Math.max(1, Flags.tmEnd - Date.now())
        onTriggered: {
            if (!root.tmRunning)
                return;
            if (Flags.tmEnd - Date.now() > 50) {
                endAlarm.interval = Flags.tmEnd - Date.now();
                endAlarm.restart();
                return;
            }
            root.tmFire();
        }
    }

    /** One-second wall clock for the resting pill's readout, only while something runs. */
    Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: root.swRunning || root.tmRunning
        onTriggered: root.now = Date.now()
    }

    // ── formatting ──

    function pad2(n) {
        return (n < 10 ? "0" : "") + n;
    }

    /** "1:04:09" / "4:09" from ms, rounding up so a timer never shows 0:00 while still running. */
    function fmtClock(ms, ceil) {
        var t = ceil ? Math.ceil(ms / 1000) : Math.floor(ms / 1000);
        var h = Math.floor(t / 3600);
        var m = Math.floor((t % 3600) / 60);
        var s = t % 60;
        return h > 0 ? h + ":" + root.pad2(m) + ":" + root.pad2(s) : m + ":" + root.pad2(s);
    }

    /** Hundredths for the stopwatch: "07". */
    function fmtCenti(ms) {
        return root.pad2(Math.floor((ms % 1000) / 10));
    }

    /** "1h 30m", "5m", "45s", "1m 30s" for a length. */
    function fmtDur(ms) {
        var t = Math.round(ms / 1000);
        var h = Math.floor(t / 3600);
        var m = Math.floor((t % 3600) / 60);
        var s = t % 60;
        var out = [];
        if (h)
            out.push(h + "h");
        if (m)
            out.push(m + "m");
        if (s || !out.length)
            out.push(s + "s");
        return out.join(" ");
    }

    function wallTime(ms) {
        return Qt.formatTime(new Date(ms), Flags.time12h ? "h:mm AP" : "HH:mm");
    }

    /**
     * Parse a typed timer length: "5" (minutes), "90s", "1:30" (m:ss),
     * "1:02:03", "1h 30m", "2h", "45 sec". Returns ms, or -1 when it doesn't read.
     */
    function parseDur(text) {
        var t = String(text).toLowerCase().trim();
        if (!t.length)
            return -1;
        if (/^\d+(\.\d+)?$/.test(t))
            return Math.round(parseFloat(t) * 60000);
        if (/^\d+(:\d{1,2}){1,2}$/.test(t)) {
            var p = t.split(":").map(function (x) { return parseInt(x, 10); });
            var secs = p.length === 3 ? p[0] * 3600 + p[1] * 60 + p[2] : p[0] * 60 + p[1];
            return secs * 1000;
        }
        var re = /(\d+(?:\.\d+)?)\s*(h|hr|hrs|hour|hours|m|min|mins|minute|minutes|s|sec|secs|second|seconds)(?![a-z])/g;
        var total = 0, seen = 0, m;
        while ((m = re.exec(t)) !== null) {
            var v = parseFloat(m[1]);
            var u = m[2].charAt(0);
            total += v * (u === "h" ? 3600000 : (u === "m" ? 60000 : 1000));
            seen += m[0].length;
        }
        return seen > 0 && t.replace(/\s+/g, "").length <= seen + 2 ? Math.round(total) : -1;
    }

    // ── world clock ──

    /** Zone name → UTC offset in minutes, filled by `date` per zone. */
    property var offsets: ({})

    function refreshOffsets() {
        var zones = Flags.worldZones || [];
        if (!zones.length)
            return;
        offProc.command = ["sh", "-c", 'for z; do printf "%s %s\\n" "$z" "$(TZ="$z" date +%z)"; done', "_"].concat(zones);
        offProc.running = true;
    }

    Process {
        id: offProc
        stdout: StdioCollector {
            onStreamFinished: {
                var map = {};
                this.text.split("\n").forEach(function (line) {
                    var m = /^(\S+) ([+-])(\d\d)(\d\d)$/.exec(line.trim());
                    if (m)
                        map[m[1]] = (m[2] === "-" ? -1 : 1) * (parseInt(m[3], 10) * 60 + parseInt(m[4], 10));
                });
                root.offsets = map;
            }
        }
    }

    Connections {
        target: Flags
        function onWorldZonesChanged() { root.refreshOffsets(); }
    }

    Timer {
        interval: 30 * 60000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refreshOffsets()
    }

    /** The system time zone ("Asia/Kolkata"), for naming the local row. */
    property string localZone: ""

    Process {
        running: true
        command: ["timedatectl", "show", "-p", "Timezone", "--value"]
        stdout: StdioCollector {
            onStreamFinished: root.localZone = this.text.trim()
        }
    }

    function localOffset() {
        return -new Date().getTimezoneOffset();
    }

    /** Wall time in `zone` at epoch ms `t`, as a Date whose local fields read as that zone's time. */
    function zoneDate(zone, t) {
        var off = root.offsets[zone];
        if (off === undefined)
            return null;
        return new Date(t + (off - root.localOffset()) * 60000);
    }

    /** "Kolkata" from "Asia/Kolkata", "New York" from "America/New_York". */
    function cityOf(zone) {
        var parts = String(zone).split("/");
        return parts[parts.length - 1].replace(/_/g, " ");
    }

    function addZone(zone) {
        var list = (Flags.worldZones || []).filter(function (z) { return z !== zone; });
        list.push(zone);
        Flags.worldZones = list;
    }

    /** Move a city one place up (dir -1) or down (+1) in the list. */
    function moveZone(zone, dir) {
        var list = (Flags.worldZones || []).slice();
        var i = list.indexOf(zone);
        var j = i + dir;
        if (i < 0 || j < 0 || j >= list.length)
            return;
        list.splice(i, 1);
        list.splice(j, 0, zone);
        Flags.worldZones = list;
    }

    /** Move a city to position `j` (drag-and-drop). */
    function moveZoneTo(zone, j) {
        var list = (Flags.worldZones || []).slice();
        var i = list.indexOf(zone);
        if (i < 0 || j < 0 || j >= list.length || i === j)
            return;
        list.splice(i, 1);
        list.splice(j, 0, zone);
        Flags.worldZones = list;
    }

    function removeZone(zone) {
        Flags.worldZones = (Flags.worldZones || []).filter(function (z) { return z !== zone; });
    }

    /** Searchable zone catalogue from the system tz database: [{ zone, city, country }]. Loaded on first use. */
    property var catalogue: []
    property var countries: ({})

    function loadCatalogue() {
        if (root.catalogue.length)
            return;
        var names = {};
        isoFile.text().split("\n").forEach(function (l) {
            if (!l.length || l.charAt(0) === "#")
                return;
            var c = l.split("\t");
            if (c.length >= 2)
                names[c[0]] = c[1];
        });
        var out = [];
        zoneFile.text().split("\n").forEach(function (l) {
            if (!l.length || l.charAt(0) === "#")
                return;
            var c = l.split("\t");
            if (c.length < 3 || c[2].indexOf("/") < 0)
                return;
            var cc = c[0].split(",")[0];
            out.push({ zone: c[2], city: root.cityOf(c[2]), country: names[cc] || cc });
        });
        out.sort(function (a, b) { return a.city.localeCompare(b.city); });
        root.countries = names;
        root.catalogue = out;
    }

    /** Best matches for a query: city prefix first, then city/country/zone contains. */
    function search(q, limit) {
        root.loadCatalogue();
        var s = String(q).toLowerCase().trim();
        if (!s.length)
            return [];
        var have = Flags.worldZones || [];
        var first = [], rest = [];
        root.catalogue.forEach(function (e) {
            if (have.indexOf(e.zone) >= 0)
                return;
            var city = e.city.toLowerCase();
            if (city.indexOf(s) === 0)
                first.push(e);
            else if (city.indexOf(s) >= 0 || e.country.toLowerCase().indexOf(s) >= 0
                     || e.zone.toLowerCase().replace(/_/g, " ").indexOf(s) >= 0)
                rest.push(e);
        });
        return first.concat(rest).slice(0, limit || 6);
    }

    FileView {
        id: zoneFile
        path: "/usr/share/zoneinfo/zone1970.tab"
        blockLoading: true
        printErrors: false
    }

    FileView {
        id: isoFile
        path: "/usr/share/zoneinfo/iso3166.tab"
        blockLoading: true
        printErrors: false
    }
}
