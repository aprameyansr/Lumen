pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Shared session flags persisted to a small JSON file and watched for external
 * change, so every Lumen daemon (pill, lock) reads and writes the same
 * Do-Not-Disturb and Keep-Awake state live without a second notification server
 * or idle inhibitor. Toggling in one surface updates the others on the next file
 * event, and the state survives a daemon restart.
 */
Singleton {
    id: root

    property alias dnd: adapter.dnd
    property alias keepAwake: adapter.keepAwake
    property alias awakeLid: adapter.awakeLid
    property alias awakeMins: adapter.awakeMins
    property alias awakeCustom: adapter.awakeCustom
    property alias awakeEnd: adapter.awakeEnd
    property alias awakeFrom: adapter.awakeFrom
    property alias awakeUntil: adapter.awakeUntil
    property alias awakePresets: adapter.awakePresets
    property alias clockTab: adapter.clockTab
    property alias swStart: adapter.swStart
    property alias swAccum: adapter.swAccum
    property alias swLaps: adapter.swLaps
    property alias tmDur: adapter.tmDur
    property alias tmTotal: adapter.tmTotal
    property alias tmEnd: adapter.tmEnd
    property alias tmLeft: adapter.tmLeft
    property alias worldZones: adapter.worldZones
    property alias time12h: adapter.time12h
    property alias clockSeconds: adapter.clockSeconds
    property alias showGlyphs: adapter.showGlyphs
    property alias paletteMode: adapter.paletteMode
    property alias wallpaperDir: adapter.wallpaperDir
    property alias randomScope: adapter.randomScope
    property alias uiScale: adapter.uiScale
    property alias reduceMotion: adapter.reduceMotion
    property alias manualHue: adapter.manualHue
    property alias manualDark: adapter.manualDark
    property alias manualSat: adapter.manualSat
    property alias uiFont: adapter.uiFont
    property alias pillOpacity: adapter.pillOpacity
    property alias pillBlur: adapter.pillBlur
    property alias topGap: adapter.topGap
    property alias appGap: adapter.appGap
    property alias recordCountdown: adapter.recordCountdown
    property alias recordDir: adapter.recordDir
    property alias recordFps: adapter.recordFps
    property alias recordQuality: adapter.recordQuality
    property alias recordCursor: adapter.recordCursor
    property alias recordMic: adapter.recordMic
    property alias recordDesktop: adapter.recordDesktop
    property alias recordClearedBefore: adapter.recordClearedBefore
    property alias weatherCity: adapter.weatherCity
    property alias musicViz: adapter.musicViz
    property alias nightLightMode: adapter.nightLightMode
    property alias nightLightTemp: adapter.nightLightTemp
    property alias nightLightOnMin: adapter.nightLightOnMin
    property alias nightLightOffMin: adapter.nightLightOffMin
    property alias osdOff: adapter.osdOff
    property alias osdTime: adapter.osdTime
    property alias notifSecs: adapter.notifSecs
    property alias notifMuted: adapter.notifMuted

    property bool selfWrite: false

    Timer {
        id: writeTimer
        interval: 20
        onTriggered: {
            file.writeAdapter();
            echoTimer.restart();
        }
    }

    Timer {
        id: echoTimer
        interval: 400
        onTriggered: root.selfWrite = false
    }

    FileView {
        id: file
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/lumen/flags.json"
        blockLoading: true
        watchChanges: true
        printErrors: false

        /**
         * Several fields often change in one go (a keep-awake start sets its span
         * and the switch together). Writing per field let the watcher reload a
         * half-written file over the newer values, so changes coalesce into one
         * write and the watcher's echo of our own write is ignored.
         */
        onFileChanged: if (!root.selfWrite) reload()
        onAdapterUpdated: {
            root.selfWrite = true;
            writeTimer.restart();
        }
        onLoadFailed: function(error) {
            if (error === FileViewError.FileNotFound)
                writeAdapter();
        }

        JsonAdapter {
            id: adapter
            property bool dnd: false
            property bool keepAwake: false
            /** Lid while keep-awake is on: "awake" holds the lid switch, "sleep" lets a closed lid suspend as usual. */
            property string awakeLid: "sleep"
            /** Session length in minutes for the next start; 0 runs until switched off. */
            property int awakeMins: 30
            /** Last custom length picked on the scrub, kept apart so the chips never clobber it. */
            property int awakeCustom: 90
            /** What a timed session does at zero: "off" just ends it, "sleep" suspends, "poweroff" shuts down. */
            property string awakeEnd: "off"
            /** Epoch ms the running session started and ends at; awakeUntil 0 means untimed. */
            property real awakeFrom: 0
            property real awakeUntil: 0
            /** Clock page tab: "stopwatch", "timer" or "world". */
            property string clockTab: "stopwatch"
            /** Stopwatch: epoch ms of the running stretch's start (0 = stopped), time banked before it, and lap marks as total ms. */
            property real swStart: 0
            property real swAccum: 0
            property var swLaps: []
            /** Timer: the length set for the next run, the length of the current run, its end while running (0 = not running) and what's left while paused. */
            property real tmDur: 300000
            property real tmTotal: 0
            property real tmEnd: 0
            property real tmLeft: 0
            /** World clock cities as IANA zone names, in display order. */
            property var worldZones: ["Europe/London", "America/New_York", "Asia/Tokyo"]
            /** Saved one-tap sessions: { name, lid, mins, end }. Seeded once; an emptied list stays empty. */
            property var awakePresets: [
                { name: "Download", lid: "awake", mins: 120, end: "sleep" },
                { name: "Reading", lid: "sleep", mins: 60, end: "off" },
                { name: "Overnight", lid: "awake", mins: 240, end: "poweroff" }
            ]
            property bool time12h: false
            property bool clockSeconds: false
            property bool showGlyphs: true
            property string paletteMode: "static"
            /** Explicit wallpaper folder override. Empty means autodetect: the dir wallpaper.sh last resolved (lumen-wallpaper-dir state file), then $HOME/Pictures/Wallpapers. */
            property string wallpaperDir: ""
            /** Super+B random target: "all" repaints every monitor, "cursor" only the one under the pointer. */
            property string randomScope: "all"
            property real uiScale: 1.0
            property bool reduceMotion: false
            property int manualHue: 30
            property bool manualDark: true
            property real manualSat: 0.5
            property string uiFont: ""
            property real pillOpacity: 1.0
            property bool pillBlur: false
            /** Top margin as a fraction of the shipped 8px. 0 sits the pill flush to the screen edge. */
            property real topGap: 1.0
            /** Pill-to-window band as a fraction of the shipped 12px. 0 tucks the windows flush under the pill. */
            property real appGap: 1.0
            property int recordCountdown: 5
            property string recordDir: ""
            property int recordFps: 60
            property string recordQuality: "high"
            property bool recordCursor: true
            property bool recordMic: true
            property bool recordDesktop: true
            property real recordClearedBefore: 0
            property string weatherCity: ""
            property bool musicViz: true
            property string nightLightMode: "off"
            property int nightLightTemp: 4000
            property int nightLightOnMin: 1260
            property int nightLightOffMin: 450
            /** Pill flashes switched off: volume, brightness, battery, workspace, record, play (play and pause) and song. */
            property var osdOff: []
            /** Multiplier on how long every pill flash stays. */
            property real osdTime: 1.0
            /** Seconds a notification card stays in the pill; low urgency gets two thirds of it. */
            property real notifSecs: 6
            /** App names whose notifications skip the pill and only land in the inbox. */
            property var notifMuted: []
        }
    }
}
