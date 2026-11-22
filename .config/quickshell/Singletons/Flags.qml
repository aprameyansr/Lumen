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
    property alias dateStyle: adapter.dateStyle
    property alias dateLang: adapter.dateLang
    property alias weekStart: adapter.weekStart
    property alias weatherUnit: adapter.weatherUnit
    property alias showGlyphs: adapter.showGlyphs
    property alias dictateEnabled: adapter.dictateEnabled
    property alias dictateEngine: adapter.dictateEngine
    property alias dictateMic: adapter.dictateMic
    property alias paletteMode: adapter.paletteMode
    property alias paletteVibrancy: adapter.paletteVibrancy
    property alias appTheme: adapter.appTheme
    property alias expandMode: adapter.expandMode
    property alias openDelay: adapter.openDelay
    property alias closeDelay: adapter.closeDelay
    property alias wsStyle: adapter.wsStyle
    property alias wsShow: adapter.wsShow
    property alias wsScroll: adapter.wsScroll
    property alias pillHeight: adapter.pillHeight
    property alias pillRounding: adapter.pillRounding
    property alias idleWidth: adapter.idleWidth
    property alias pillShadow: adapter.pillShadow
    property alias pillBorder: adapter.pillBorder
    property alias pillSheen: adapter.pillSheen
    property alias springFeel: adapter.springFeel
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

    function flush() {
        file.writeAdapter();
    }

    FileView {
        id: file
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/lumen/flags.json"
        blockLoading: true
        /** Synchronous writes: an async write in flight gets joined by the next one, which reloads its older text over values set since. */
        blockWrites: true
        watchChanges: true
        printErrors: false

        /** Read the file before any binding sees the defaults. */
        Component.onCompleted: text()

        onFileChanged: reload()
        /** Several fields often change in one go (a keep-awake start sets its span and the switch together): one write per event-loop turn. */
        onAdapterUpdated: Qt.callLater(root.flush)
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
            /** Pill date: "ddd d MMM", "ddd d", "d MMM" or "dd.MM.". */
            property string dateStyle: "ddd d MMM"
            /** Date and weekday language: "en" or "de". */
            property string dateLang: "en"
            /** First calendar column: 1 Monday, 0 Sunday. */
            property int weekStart: 1
            /** Temperature unit: "c" or "f". */
            property string weatherUnit: "c"
            property bool showGlyphs: true
            /** Hold-to-talk dictation on the `dictate` global bind. */
            property bool dictateEnabled: true
            /** "whisper" (most accurate, GPU) or "parakeet" (fastest, CPU). */
            property string dictateEngine: "whisper"
            /** "builtin" (laptop mic, instant) or "default" (system mic, e.g. Bluetooth). */
            property string dictateMic: "builtin"
            property string paletteMode: "static"
            /** Dynamic palette strength: 0 muted, 0.5 natural, 1 vivid. */
            property real paletteVibrancy: 0.5
            /** GTK apps take the pill palette (lumen-palette.css next to each glass.css). */
            property bool appTheme: false
            /** "hover" expands on pointer entry, "click" only when the pill is clicked. */
            property string expandMode: "hover"
            /** Ms the pointer rests on the pill before it expands. */
            property int openDelay: 0
            /** Ms after the pointer leaves before the hover pill folds. */
            property int closeDelay: 300
            /** Workspaces as "dots", "numbers" or "names". */
            property string wsStyle: "dots"
            /** "occupied" shows ruled and live workspaces, "all" fills the gaps up to the highest. */
            property string wsShow: "occupied"
            /** Mouse wheel over the workspaces switches them. */
            property bool wsScroll: false
            /** Resting pill height in px (24 to 64). */
            property real pillHeight: 38
            /** Pill corner radius in px, capped at half the height. */
            property real pillRounding: 18
            /** Minimum resting pill width in px. */
            property real idleWidth: 160
            /** Drop shadow under the pill. */
            property bool pillShadow: true
            /** Hairline border around the pill. */
            property bool pillBorder: true
            /** Highlight line along the pill's top edge. */
            property bool pillSheen: true
            /** Pill morph springs: "soft" (a gentle overshoot when growing) or "snappy". */
            property string springFeel: "soft"
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
