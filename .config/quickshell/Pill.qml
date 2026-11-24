pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Services.Notifications
import "Singletons"

// The pill morphs in place. Its surfaces cross-fade over the resting and hover rows.
Item {
    id: pill

    property real s: 1
    property string screenName: ""
    property var barWindow
    property string surface: ""

    /**
     * Toast swipe offset and fade, written by Toast while dragging and applied
     * by the host in shell.qml.
     */
    property real swipeX: 0
    property real swipeY: 0
    property real swipeFade: 1
    Behavior on swipeFade {
        enabled: !toastLoader.active
        NumberAnimation {
            duration: Motion.standard
            easing.type: Motion.easeStandard
        }
    }
    /**
     * When the last toast leaves, a hover that began on the toast (not on the
     * plain pill) is dropped, so the pill settles back to the resting time
     * instead of opening the hover row under a pointer that only sat over the
     * toast. A real move onto the pill expands it again.
     */
    onToastActiveChanged: if (!toastActive) {
        swipeX = 0;
        swipeY = 0;
        swipeFade = 1;
        if (!hoverClean && !held)
            hoverLatch = false;
    }

    property bool hovered: false
    property bool pinned: false
    property bool forcePinned: false

    readonly property bool held: pinned || forcePinned
    /**
     * The page actually on screen. A critical notification takes the pill over
     * an open page: the page stays open (so no close tidy-up runs and every
     * dropdown, caption, focus and half-typed field survives) but its loader is
     * hidden and keys are held back, then it reappears exactly as it was.
     */
    readonly property string shownSurface: criticalToast ? "" : surface
    readonly property bool mixerOpen: surface === "mixer"
    readonly property bool soundOpen: surface === "sound"
    readonly property bool calendarOpen: surface === "calendar"
    readonly property bool clockOpen: surface === "clock"
    readonly property bool launcherOpen: surface === "launcher"
    readonly property bool emojiOpen: surface === "emoji"
    readonly property bool clipboardOpen: surface === "clipboard"
    readonly property bool wallpaperOpen: surface === "wallpaper"
    readonly property bool powerOpen: surface === "power"
    readonly property bool mediaOpen: surface === "media"
    readonly property bool linkOpen: surface === "link"
    readonly property bool wifiOpen: surface === "wifi"
    readonly property bool btOpen: surface === "bt"
    readonly property bool batteryOpen: surface === "battery"
    readonly property bool awakeOpen: surface === "awake"
    readonly property bool settingsOpen: surface === "settings"
    readonly property bool keybindsOpen: surface === "keybinds"
    readonly property bool workspacesOpen: surface === "workspaces"
    readonly property bool stashOpen: surface === "stash"
    readonly property bool spaceappsOpen: surface === "spaceapps"
    readonly property bool recorderOpen: surface === "recorder"
    readonly property bool sysmonOpen: surface === "sysmon"
    readonly property bool fileShelfOpen: surface === "file-shelf"
    readonly property bool shelfDragging: fileShelfOpen && !!ldFileShelf.page?.dragging
    readonly property var sysmonPages: ["cpu", "gpu", "mem", "net", "disk", "swap"]
    readonly property bool sysmonDetailOpen: surface.startsWith("sysmon-") && (sysmonPages.includes(surface.slice("sysmon-".length)) || surface === "sysmon-apps")
    readonly property bool appearanceOpen: surface === "appearance"
    readonly property bool displayOpen: surface === "display"
    readonly property bool inputOpen: surface === "input"
    readonly property bool lookOpen: surface === "look"
    readonly property bool animationOpen: surface === "animation"
    readonly property bool notificationsOpen: surface === "notifications"
    readonly property bool timeOpen: surface === "time"
    readonly property bool fontpickerOpen: surface === "fontpicker"
    readonly property bool vocabOpen: surface === "vocab"
    readonly property bool dictationOpen: surface === "dictation"
    readonly property bool settingsLike: settingsOpen || appearanceOpen || lookOpen || inputOpen || displayOpen || animationOpen || notificationsOpen || timeOpen || fontpickerOpen || awakeOpen || vocabOpen || dictationOpen
    readonly property bool hasMedia: Players.list.length > 0

    readonly property var netDevices: (typeof Networking !== "undefined" && Networking && Networking.devices) ? Networking.devices.values : []
    readonly property var wifiDev: netDevices.find(function (d) {
        return d && d.type === DeviceType.Wifi;
    }) || null
    readonly property bool wifiOn: (typeof Networking !== "undefined" && Networking) ? Networking.wifiEnabled : false
    readonly property var wifiNets: (wifiDev && wifiDev.networks) ? wifiDev.networks.values : []
    readonly property var wifiActive: wifiNets.find(function (n) {
        return n && n.connected;
    }) || null
    readonly property real wifiLevel: (wifiActive && wifiActive.signalStrength) || 0
    readonly property var btAdapter: (typeof Bluetooth !== "undefined" && Bluetooth) ? Bluetooth.defaultAdapter : null
    readonly property bool btOn: btAdapter ? btAdapter.enabled === true : false
    readonly property bool surfaceOpen: surface.length > 0
    property bool hoverLatch: false

    /**
     * False for the first seconds after the shell maps. Hyprland hands pointer
     * focus to a freshly mapped layer surface at the cursor's position, which
     * the window-level HoverHandler reads as a pill hover and latches the pill
     * open (issue #20). Latching only after boot settles filters that spurious
     * enter; a real hover during the window just expands late, harmlessly.
     */
    property bool bootSettled: false

    Timer {
        interval: 3000
        running: true
        onTriggered: pill.bootSettled = true
    }

    readonly property bool expanded: surfaceOpen || held || hoverLatch

    /**
     * The special workspace shown on this pill's monitor, surfaced as a plain word
     * in place of the clock so it is obvious you are looking at the minimized stash
     * or the private space rather than your real desktop. Empty in the normal case.
     */
    readonly property string specialView: {
        var ms = Hyprland.monitors.values;
        for (let i = 0; i < ms.length; i++) {
            if (ms[i] && ms[i].name === pill.screenName) {
                const o = ms[i].lastIpcObject;
                const sw = (o && o.specialWorkspace) ? o.specialWorkspace.name : "";
                if (sw && sw.indexOf("special:") === 0) {
                    const id = sw.slice("special:".length);
                    const sl = Spaces.list;
                    for (let j = 0; j < sl.length; j++)
                        if (sl[j] && sl[j].id === id)
                            return sl[j].name;
                    if (id === "minimized")
                        return "Minimized";
                    if (id === "private")
                        return "Private";
                    if (id === "stash")
                        return "Stash";
                    return id.charAt(0).toUpperCase() + id.slice(1);
                }
                return "";
            }
        }
        return "";
    }
    readonly property bool toastActive: Notifs.popups.length > 0
    /**
     * Whether the pill is held against interruptions: an open page, pinned, or
     * a hover that began on the plain pill. A hover that began on a toast or a
     * flash doesn't count, so moving onto a notification to read or click it
     * keeps it there.
     */
    property bool hoverClean: false
    readonly property bool holding: surfaceOpen || held || (hoverLatch && hoverClean) || dictateHere

    /**
     * A dictation take on this monitor. The pill stays at rest, its outline
     * untouched, and the clock row hands its footprint to the mic bars; hover,
     * flashes and toasts wait until the take is done.
     */
    readonly property bool dictateHere: Dictate.active && Dictate.mon === screenName
    readonly property bool criticalToast: Notifs.popups.some(function (p) {
        return p && p.urgency === NotificationUrgency.Critical;
    })
    readonly property bool osdActive: osd.flashing

    /**
     * Quick-record overlays belong only to the focused monitor the keybind
     * targeted, so a single chooser and a single countdown toast appear. The
     * standalone chooser is suppressed while the morphing recorder surface owns the
     * pill; the countdown toast yields to the surface too (the surface shows its
     * own in-bar countdown there).
     */
    readonly property bool quickHere: ScreenRec.quickMon === screenName
    readonly property bool quickChoosing: quickHere && ScreenRec.quickChoosing && !surfaceOpen
    readonly property bool quickCounting: quickHere && ScreenRec.counting && !recorderOpen

    /** Pill shape from Settings > Look > Pill: height 24-64, rounding capped at half the height. */
    readonly property real baseH: Math.max(24, Math.min(64, Flags.pillHeight))
    readonly property real restW: Math.max(0, Flags.idleWidth) * s
    readonly property real restH: baseH * s
    readonly property real hoverPad: 20 * s
    readonly property real hoverW: hoverRow.implicitWidth + 2 * hoverPad
    readonly property real hoverH: restH * 58 / 38
    readonly property real toastW: 342 * s
    readonly property real quickChooseW: 344 * s
    readonly property real quickChooseH: 76 * s
    readonly property real quickCountW: 150 * s
    readonly property real quickCountH: 64 * s
    readonly property real dragOverW: 300 * s
    readonly property real dragOverH: 126 * s
    readonly property real restCorner: Math.max(0, Math.min(Flags.pillRounding, baseH / 2)) * s
    readonly property real openCorner: restCorner * 22 / 18

    readonly property var surfaces: ({
            calendar: ldCalendar,
            launcher: ldLauncher,
            emoji: ldEmoji,
            clipboard: ldClip,
            wallpaper: ldWall,
            power: ldPower,
            media: ldMedia,
            sound: ldSound,
            mixer: ldMixer,
            link: ldLink,
            wifi: ldWifi,
            bt: ldBt,
            clock: ldClock,
            awake: ldAwake,
            battery: ldBattery,
            settings: ldSettings,
            keybinds: ldKeybinds,
            workspaces: ldWorkspaces,
            stash: ldStash,
            spaceapps: ldSpaceapps,
            recorder: ldRecorder,
            "file-shelf": ldFileShelf,
            sysmon: ldSysmon,
            "sysmon-apps": ldSysmonApps,
            appearance: ldAppearance,
            display: ldDisplay,
            input: ldInput,
            look: ldLook,
            animation: ldAnimation,
            time: ldTime,
            notifications: ldNotifications,
            fontpicker: ldFontpicker,
            vocab: ldVocab,
            dictation: ldDictation
        })

    function pageLoader(name) {
        if (Object.prototype.hasOwnProperty.call(surfaces, name))
            return surfaces[name];
        if (!name.startsWith("sysmon-"))
            return null;
        const index = sysmonPages.indexOf(name.slice("sysmon-".length));
        return index < 0 ? null : sysmonDetails.itemAt(index);
    }

    function pageAnchor(name) {
        const loader = pageLoader(name);
        if (!loader || !loader.showAme)
            return null;
        loader.active = true;
        return loader.item;
    }

    // Order matters when a drag, an alert and an open page overlap.
    readonly property string mode: {
        if (dragActive)
            return "dragOver";
        if (criticalToast && !(osdActive && !holding))
            return "toast";
        if (pageLoader(surface))
            return surface;
        if (dictateHere)
            return "rest";
        if (quickChoosing)
            return "quickChoose";
        if (quickCounting)
            return "quickCount";
        if (osdActive && !holding)
            return "osd";
        if (toastActive && !holding)
            return "toast";
        return expanded ? "hover" : "rest";
    }

    /** Incoming file drop surface and the current transfer status. */
    property string dragName: ""
    property string dragStage: ""
    readonly property bool dragActive: dragStage.length > 0
    property bool overInstallTarget: false
    property bool installDropAvailable: false
    property string installDropLabel: ""
    readonly property bool appImageDrop: installDropAvailable && installDropLabel.startsWith("Install AppImage")
    property int shelfStoredCount: 0
    property int shelfFailedCount: 0
    property string shelfStoredSummary: ""
    property string shelfDropSummary: ""
    property var shelfDropUrls: []
    property int shelfDropRequest: 0
    property bool installDropCandidate: false

    signal requestSurface(string name)

    /** A page replacing another holds back a beat (PillSurface.arrive) so the two never cross-fade. */
    property string lastSurface: ""
    onSurfaceChanged: {
        const item = pageAnchor(surface);
        if (item && typeof item.arrive === "function")
            item.arrive(lastSurface.length > 0);
        lastSurface = surface;
    }
    signal requestClose

    /**
     * Forward an arrow-key nudge to the open mixer's targeted fader. Returns true
     * when the mixer is open and a fader consumed the step.
     */
    function mixerStep(deltaPct) {
        return (pill.mixerOpen && ldMixer.page) ? ldMixer.page.stepFocused(deltaPct) : false;
    }

    /**
     * Move the open mixer's keyboard focus across the fader row; `dir` is +1
     * (right) or -1 (left). No-op unless the mixer is open.
     */
    function mixerFocusMove(dir) {
        if (pill.mixerOpen && ldMixer.page)
            ldMixer.page.moveFocus(dir);
    }

    /**
     * Forward an arrow-key nudge to the open recorder's focused audio fader.
     * Returns true when the recorder is open and a revealed fader consumed it.
     */
    function recorderStep(deltaPct) {
        return (pill.recorderOpen && ldRecorder.page) ? ldRecorder.page.stepFocused(deltaPct) : false;
    }

    function rowNavSurface() {
        return settingsLike ? pageLoader(surface)?.item : null;
    }

    /**
     * Move the focused settings row by `dir` (+1 down, -1 up), carrying the soul
     * seam. Returns true when a settings-family surface is open and consumed it.
     */
    function settingsMove(dir) {
        var nav = pill.rowNavSurface();
        if (!nav)
            return false;
        nav.kbMove(dir);
        return true;
    }

    /**
     * Step the focused settings row's control: a segmented choice cycles by
     * `dir`, a toggle is set on (dir > 0) or off. Returns true when consumed.
     */
    function settingsAdjust(dir) {
        var nav = pill.rowNavSurface();
        if (!nav)
            return false;
        nav.kbAdjust(dir);
        return true;
    }

    /**
     * Activate the focused settings row: a toggle flips, a nav row opens its
     * sub-surface. Returns true when a settings-family surface is open.
     */
    function settingsActivate() {
        var nav = pill.rowNavSurface();
        if (!nav)
            return false;
        nav.kbActivate();
        return true;
    }

    /**
     * Slide the open keybinds list's focused row by `dir` (+1 down, -1 up),
     * carrying the soul seam. No-op unless the keybinds surface is open.
     */
    function keybindsMove(dir) {
        if (pill.keybindsOpen && ldKeybinds.page)
            ldKeybinds.page.move(dir);
    }

    /**
     * Enter on the open keybinds surface: arm chord capture on the focused row.
     * No-op unless the keybinds surface is open.
     */
    function keybindsActivate() {
        if (pill.keybindsOpen && ldKeybinds.page)
            ldKeybinds.page.activate();
    }

    readonly property bool keybindsListening: pill.keybindsOpen && ldKeybinds.page !== null && ldKeybinds.page.listening

    /**
     * A tile was picked in the standalone quick-record chooser. Screen with several
     * monitors flips to the inline sub-choice; otherwise each source kicks off its
     * resolver (which counts down once the target is ready) and the chooser closes.
     */
    function quickChooseSource(kind) {
        if (kind === "screen") {
            if (ScreenRec.monitors.length > 1) {
                ScreenRec.quickScreenChoosing = true;
                return;
            }
            ScreenRec.prepareScreen(pill.screenName);
        } else if (kind === "window") {
            ScreenRec.prepareWindow();
        }
        ScreenRec.quickChoosing = false;
        ScreenRec.quickScreenChoosing = false;
    }

    function quickPickMonitor(name) {
        ScreenRec.quickChoosing = false;
        ScreenRec.quickScreenChoosing = false;
        ScreenRec.prepareScreen(name);
    }

    /**
     * Step the open surface back one level when its header bar is clicked: a
     * settings sub-surface returns to the index, the font picker to appearance,
     * a keybinds form to its list, and any other surface dismisses to the hover
     * pill. Empty space in the body never triggers this.
     */
    function surfaceBack() {
        if (sysmonBack())
            return;
        if (pill.vocabOpen) {
            if (!(ldVocab.page && ldVocab.page.back()))
                pill.requestSurface("dictation");
            return;
        }
        if (pill.dictationOpen) {
            pill.requestSurface("settings");
            return;
        }
        if (pill.awakeOpen && ldAwake.page && ldAwake.page.formOpen) {
            ldAwake.page.closeForm();
            return;
        }
        if (pill.keybindsOpen) {
            if (ldKeybinds.page && ldKeybinds.page.formOpen)
                ldKeybinds.page.closeForm();
            else
                pill.requestSurface("settings");
            return;
        }
        if (pill.fontpickerOpen) {
            pill.requestSurface("appearance");
            return;
        }
        if (pill.stashOpen) {
            if (ldStash.page && ldStash.page.addOpen)
                ldStash.page.closeAdd();
            else
                pill.requestSurface("workspaces");
            return;
        }
        if (pill.spaceappsOpen) {
            if (ldSpaceapps.page && ldSpaceapps.page.addOpen)
                ldSpaceapps.page.closeAdd();
            else
                pill.requestSurface("workspaces");
            return;
        }
        if (pill.workspacesOpen && ldWorkspaces.page && ldWorkspaces.page.formOpen) {
            ldWorkspaces.page.closeForm();
            return;
        }
        if (pill.appearanceOpen || pill.displayOpen || pill.inputOpen || pill.lookOpen || pill.animationOpen || pill.notificationsOpen || pill.timeOpen || pill.workspacesOpen) {
            pill.requestSurface("settings");
            return;
        }
        pill.requestClose();
    }

    /** Route a key to the open clock page; true when it used it. */
    function clockKey(k, mods) {
        return (pill.clockOpen && ldClock.page) ? ldClock.page.key(k, mods) : false;
    }

    /** Held Delete on the keep-awake surface: hold-to-wipe the keyboard-focused preset. */
    function awakeDelete() {
        if (pill.awakeOpen && ldAwake.page && !ldAwake.page.formOpen)
            ldAwake.page.deletePress();
    }
    function awakeDeleteRelease() {
        if (pill.awakeOpen && ldAwake.page)
            ldAwake.page.deleteRelease();
    }

    function fileShelfMove(direction) {
        return fileShelfOpen && ldFileShelf.page ? ldFileShelf.page.move(direction) : false;
    }

    function sysmonMove(dx, dy) {
        if (surface === "sysmon-apps")
            return dy !== 0 && ldSysmonApps.page && ldSysmonApps.page.move(dy);
        return (pill.sysmonOpen && ldSysmon.page) ? ldSysmon.page.move(dx, dy) : false;
    }

    function sysmonActivate() {
        return (pill.sysmonOpen && ldSysmon.page) ? ldSysmon.page.activate() : false;
    }

    function sysmonEscape() {
        if (!sysmonOpen && !sysmonDetailOpen)
            return false;
        hoverClean = true;
        hoverLatch = true;
        if (!hovered)
            graceTimer.restart();
        requestClose();
        return true;
    }

    function sysmonBack() {
        if (!sysmonDetailOpen)
            return false;
        requestSurface("sysmon");
        return true;
    }

    /** Esc on the vocabulary page folds an add or teach view back to the list; false on the list itself. */
    function vocabBack() {
        return (pill.vocabOpen && ldVocab.page) ? ldVocab.page.back() : false;
    }

    /** Held Shift+Delete on dictation or vocabulary: start / drop the clear-all heat. */
    function wipePress() {
        if (pill.dictationOpen)
            ldDictation.page?.wipePress();
        else if (pill.vocabOpen)
            ldVocab.page?.wipePress();
    }

    function wipeRelease() {
        if (pill.dictationOpen)
            ldDictation.page?.wipeRelease();
        else if (pill.vocabOpen)
            ldVocab.page?.wipeRelease();
    }

    /** Delete on the dictation page: drop the focused history entry. */
    function dictationDelete() {
        if (pill.dictationOpen && ldDictation.page)
            ldDictation.page.deleteFocused();
    }

    /** Delete on the vocabulary list: drop the focused word. */
    function vocabDelete() {
        if (pill.vocabOpen && ldVocab.page)
            ldVocab.page.deleteFocused();
    }

    /** Enter while teaching saves what has been heard so far; true when it did. */
    function vocabEnter() {
        if (pill.vocabOpen && ldVocab.page && ldVocab.page.view === "teach") {
            ldVocab.page.saveTeach();
            return true;
        }
        return false;
    }

    readonly property bool vocabTyping: pill.vocabOpen && ldVocab.page !== null && ldVocab.page.typing

    /** A printable key on the vocabulary list starts a search with it; true when it did. */
    function vocabType(ch) {
        if (!pill.vocabOpen || !ldVocab.page || ldVocab.page.view !== "list" || ldVocab.page.typing)
            return false;
        ldVocab.page.startSearch(ch);
        return true;
    }

    function keybindsBack() {
        if (pill.keybindsOpen && ldKeybinds.page && ldKeybinds.page.formOpen) {
            ldKeybinds.page.closeForm();
            return true;
        }
        return false;
    }

    /**
     * Slide the open wallpaper strip's focus by `dir` thumbs; +1 is right (older)
     * and -1 is left (newer). No-op unless the wallpaper surface is open.
     */
    function wallpaperMove(dir) {
        if (pill.wallpaperOpen && ldWall.page)
            ldWall.page.move(dir);
    }

    /**
     * Apply the wallpaper strip's focused thumb through wallpaper.sh. The
     * surface stays open so the pick can be iterated. No-op unless the
     * wallpaper surface is open.
     */
    function wallpaperActivate() {
        if (pill.wallpaperOpen && ldWall.page)
            ldWall.page.activate();
    }

    readonly property bool wallpaperSearching: pill.wallpaperOpen && ldWall.page !== null && ldWall.page.searching

    /**
     * Route the first printable keystroke over the open wallpaper strip into a
     * DuckDuckGo search seeded with that character. No-op unless the wallpaper
     * surface is open.
     */
    function wallpaperType(ch) {
        if (pill.wallpaperOpen && ldWall.page)
            ldWall.page.startSearch(ch);
    }

    /**
     * Slide the open power surface's keyboard focus by `dir` tiles; +1 is right
     * and -1 is left. No-op unless the power surface is open.
     */
    function powerMove(dir) {
        if (pill.powerOpen && ldPower.page)
            ldPower.page.move(dir);
    }

    /**
     * Enter pressed on the open power surface's focused tile: fires a safe tile
     * at once, latches a destructive tile's heat hold. Returns true when a tile
     * consumed the key. No-op (false) unless the power surface is open.
     */
    function powerPress() {
        return (pill.powerOpen && ldPower.page) ? ldPower.page.pressFocused() : false;
    }

    /**
     * Enter released on the open power surface: drains an unfinished destructive
     * hold so a key let go before the fill completes never confirms.
     */
    function powerHotkey(text) {
        return (pill.powerOpen && ldPower.page) ? ldPower.page.pressHotkey(text) : false;
    }

    function powerRelease() {
        if (pill.powerOpen && ldPower.page)
            ldPower.page.releaseFocused();
    }

    onSurfaceOpenChanged: if (surfaceOpen) {
        pinned = false;
        unloadIdle.stop();
        if (quickHere && ScreenRec.quickChoosing) {
            ScreenRec.quickChoosing = false;
            ScreenRec.quickScreenChoosing = false;
        }
    } else {
        unloadIdle.restart();
    }

    // Unload idle pages after two minutes. Keep preloaded and busy pages.
    Timer {
        id: unloadIdle
        interval: 120000
        onTriggered: {
            const loaders = Object.values(pill.surfaces);
            for (let index = 0; index < sysmonDetails.count; index++)
                loaders.push(sysmonDetails.itemAt(index));
            for (const loader of loaders) {
                if (loader?.active && !loader.preload && loader.item?.busy !== true)
                    loader.active = false;
            }
        }
    }

    QtObject {
        id: clock
        readonly property var now: sysClock.date
        readonly property string timeFormat: (Flags.time12h ? "h:mm" : "HH:mm") + (Flags.clockSeconds ? ":ss" : "") + (Flags.time12h ? " AP" : "")
        readonly property string hhmm: Qt.formatTime(now, timeFormat)
        readonly property string date: Clocks.dateFor(Flags.dateStyle, Flags.dateLang, now)
    }

    SystemClock {
        id: sysClock
        precision: Flags.clockSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    readonly property real targetRadius: (mode === "rest" || mode === "hover") ? restCorner : openCorner
    readonly property real morphRadius: springR.value

    readonly property size targetSize: {
        const loader = pageLoader(mode);
        if (loader) {
            // Activate the synchronous loader before reading its geometry binding.
            loader.active = true;
            return loader.morphSize;
        }
        switch (mode) {
        case "osd":
            return Qt.size(osd.desiredW, osd.desiredH);
        case "toast":
            return Qt.size(toastW, toastLoader.item ? (toastLoader.item as Item).implicitHeight + 24 * s : restH);
        case "hover":
            return Qt.size(hoverW, hoverH);
        case "quickChoose":
            return Qt.size(quickChooseW, quickChooseH);
        case "quickCount":
            return Qt.size(quickCountW, quickCountH);
        case "dragOver":
            return Qt.size(dragOverW, dragOverH);
        default:
            return Qt.size(Math.max(restW, restRow.implicitWidth + 36 * s), restH);
        }
    }
    readonly property real targetW: targetSize.width
    readonly property real targetH: targetSize.height

    /**
     * Width, height and corner ride damped springs that keep their velocity
     * when the target moves, so an interrupted morph bends toward the new shape
     * instead of restarting a curve. Rest <-> hover uses the quicker hop tuning.
     */
    readonly property var feel: Flags.springFeel === "snappy" ? ({
            hop: 0.19,
            shrink: 0.25,
            grow: 0.29,
            growDamping: 0.9
        }) : ({
            hop: 0.26,
            shrink: 0.34,
            grow: 0.4,
            growDamping: 0.82
        })

    Spring {
        id: springW
        target: pill.targetW
        response: pill.hoverHop ? pill.feel.hop : pill.feel.shrink
        growResponse: pill.hoverHop ? pill.feel.hop : pill.feel.grow
        growDamping: pill.hoverHop ? 1 : pill.feel.growDamping
    }
    Spring {
        id: springH
        target: pill.targetH
        response: springW.response
        growResponse: springW.growResponse
        growDamping: springW.growDamping
    }
    Spring {
        id: springR
        target: pill.targetRadius
        response: springW.response
    }
    Component.onCompleted: {
        springW.snap(targetW);
        springH.snap(targetH);
        springR.snap(targetRadius);
    }

    width: springW.value
    height: springH.value

    /**
     * How settled the pill is into its target geometry: 0 while the morph is far
     * away, 1 once it arrives. Content opacities key off this, not their own
     * timers, so a surface fades in as the pill reaches full size, never over a
     * half-grown pill.
     */
    readonly property real morphCloseness: {
        const d = Math.max(Math.abs(width - targetW), Math.abs(height - targetH));
        return 1 - Math.min(1, d / (110 * s));
    }

    /**
     * Gate the soul bead until the hover morph has arrived and its icons exist.
     * Fire it earlier and the bead aims at anchors that aren't laid out yet.
     * Latched so small width changes inside hover (workspace dot growing, tray
     * icons appearing) don't flicker the bead off.
     */
    property bool hoverSoulGate: false
    readonly property bool hoverArrived: mode === "hover" && morphCloseness > 0.55
    onHoverArrivedChanged: if (hoverArrived)
        hoverSoulGate = true

    /**
     * Rest and hover sit a few dozen pixels apart, so the 420ms morph is nearly
     * all settle tail on that hop and reads sluggish. Both endpoints in the
     * rest/hover pair get the shorter glide; every real surface morph keeps the
     * full duration.
     */
    property string lastMode: "rest"
    property bool hoverHop: false

    onModeChanged: {
        hoverHop = (mode === "hover" || mode === "rest") && (lastMode === "hover" || lastMode === "rest");
        lastMode = mode;
        if (mode !== "hover") {
            hoverSoulGate = false;
            soulTarget = "";
            soulWsIndex = -1;
        }
    }
    onHoverSoulGateChanged: if (hoverSoulGate)
        kanjiFlashAnim.restart()

    property string soulTarget: ""
    property int soulWsIndex: -1

    property real kanjiFlash: 0

    SequentialAnimation {
        id: kanjiFlashAnim
        NumberAnimation {
            target: pill
            property: "kanjiFlash"
            to: 1
            duration: 90
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: pill
            property: "kanjiFlash"
            to: 0
            duration: 320
            easing.type: Easing.OutCubic
        }
    }

    /**
     * True while any morph axis animates. The body's effect layer (live drop
     * shadow) re-renders its offscreen buffer at every size step, on every
     * monitor, so it is the top per-frame cost of a morph; dropping the shadow
     * mid-flight and restoring it on settle keeps the morph cheap (issue #20).
     */
    readonly property bool morphing: springW.running || springH.running || springR.running

    Rectangle {
        id: bud
        readonly property bool shown: pill.mode === "hover" && pill.hasMedia
        property real budR: (budArea.containsMouse ? 15 : 12) * pill.s
        width: budR * 2
        height: budR * 2
        radius: budR
        x: pill.width - budR
        anchors.verticalCenter: parent.verticalCenter
        visible: opacity > 0.01
        opacity: shown ? 1 : 0
        border.width: 1
        border.color: Theme.border
        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: Qt.alpha(Theme.cardTop, Flags.pillOpacity)
            }
            GradientStop {
                position: 1.0
                color: Qt.alpha(Theme.cardBot, Flags.pillOpacity)
            }
        }
        Behavior on budR {
            NumberAnimation {
                duration: Motion.fast
                easing.type: Motion.easeStandard
            }
        }
        Behavior on opacity {
            NumberAnimation {
                duration: Motion.standard
            }
        }

        Canvas {
            id: budBead
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: 3 * pill.s
            width: 18 * pill.s
            height: 18 * pill.s
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const c = width / 2;
                const R = (budArea.containsMouse ? 5.2 : 4) * pill.s;
                const hg = ctx.createRadialGradient(c - R * 0.32, c - R * 0.38, 0, c, c, R);
                hg.addColorStop(0, Theme.flameInk);
                hg.addColorStop(0.55, Theme.vermLit);
                hg.addColorStop(0.92, Theme.verm);
                hg.addColorStop(1, Theme.flameEmber);
                ctx.beginPath();
                ctx.arc(c, c, R, 0, 7);
                ctx.fillStyle = hg;
                ctx.fill();
                ctx.beginPath();
                ctx.ellipse(c - R * 0.62, c - R * 0.66, R * 0.6, R * 0.36);
                ctx.fillStyle = "rgba(255,246,240,0.6)";
                ctx.fill();
            }
        }

        MouseArea {
            id: budArea
            anchors.fill: parent
            enabled: bud.shown
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pill.requestSurface("media")
            onContainsMouseChanged: budBead.requestPaint()
        }
    }

    Rectangle {
        id: body
        anchors.fill: parent

        radius: pill.morphRadius
        border.width: Flags.pillBorder ? 1 : 0
        border.color: Theme.border
        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: Qt.alpha(Theme.cardTop, Flags.pillOpacity)
            }
            GradientStop {
                position: 1.0
                color: Qt.alpha(Theme.cardBot, Flags.pillOpacity)
            }
        }

        layer.enabled: !pill.morphing && Flags.pillShadow
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, Theme.shadowOpacity)
            shadowBlur: 0.7
            shadowVerticalOffset: 3 * pill.s
        }

        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: 1
            anchors.leftMargin: body.radius * 0.6
            anchors.rightMargin: body.radius * 0.6
            height: 1
            visible: Flags.pillSheen
            color: Theme.sheen
        }
    }

    /** Timer outline and stopwatch heartbeat on the resting pill (see PillTrace). */
    PillTrace {
        s: pill.s
        radius: pill.morphRadius
        rest: pill.mode === "rest"
    }

    /**
     * Rest anchor for Ame: the 時 kanji centre. The idle outline condenses into
     * the bead here before it moves.
     */
    readonly property point wakePoint: {
        void pill.width;
        void pill.height;
        return restKanji.mapToItem(pill, restKanji.width / 2, restKanji.height / 2);
    }

    /**
     * Bead target while hovered. soulTarget is a sticky key written by the hover
     * sources: the bead parks on the last focused dot or icon and glides to the
     * next, so crossing a gap between targets doesn't snap it back to the active
     * workspace. Pill geometry is voided so the anchor follows the hover morph,
     * the point stays live.
     */
    readonly property point soulPoint: {
        void pill.width;
        void pill.height;
        const drop = 12 * pill.s;
        if (soulTarget === "wifi")
            return wifiIcon.mapToItem(pill, wifiIcon.width / 2, wifiIcon.height + drop * 0.55);
        if (soulTarget === "bt")
            return btIcon.mapToItem(pill, btIcon.width / 2, btIcon.height + drop * 0.55);
        if (soulTarget === "weather")
            return weatherGlance.mapToItem(pill, weatherGlance.width / 2, weatherGlance.height + drop * 0.55);
        if (soulTarget === "awake")
            return awakeIcon.mapToItem(pill, awakeIcon.width / 2, awakeIcon.height + drop * 0.55);
        if (soulTarget === "battery")
            return batteryIcon.mapToItem(pill, batteryIcon.width / 2, batteryIcon.height + drop * 0.55);
        if (soulTarget === "inbox")
            return inboxIcon.mapToItem(pill, inboxIcon.width / 2, inboxIcon.height + drop * 0.55);
        if (soulTarget === "sound")
            return soundIcon.mapToItem(pill, soundIcon.width / 2, soundIcon.height + drop * 0.55);
        if (soulTarget === "mixer")
            return mixerIcon.mapToItem(pill, mixerIcon.width / 2, mixerIcon.height + drop * 0.55);
        if (soulTarget === "power")
            return powerIcon.mapToItem(pill, powerIcon.width / 2, powerIcon.height + drop * 0.55);
        if (soulTarget === "settings")
            return settingsIcon.mapToItem(pill, settingsIcon.width / 2, settingsIcon.height + drop * 0.55);
        if (soulTarget === "recorder")
            return recorderIcon.mapToItem(pill, recorderIcon.width / 2, recorderIcon.height + drop * 0.55);
        if (soulTarget === "file-shelf")
            return fileShelfIcon.mapToItem(pill, fileShelfIcon.width / 2, fileShelfIcon.height + drop * 0.55);
        if (soulTarget === "sysmon")
            return sysmonIcon.mapToItem(pill, sysmonIcon.width / 2, sysmonIcon.height + drop * 0.55);
        if (soulTarget === "ws" && soulWsIndex >= 0) {
            void ws.activeName;
            void ws.width;
            const p = ws.mapToItem(pill, ws.slotCenterX(soulWsIndex), ws.height / 2);
            return Qt.point(p.x, p.y + drop);
        }
        return ws.mapToItem(pill, ws.activeDotPoint.x, ws.activeDotPoint.y + drop);
    }

    /**
     * Which open surface owns Ame's anchor. Each surface exports its own
     * `ameForm`/`amePoint`; the pill picks the open surface's `ame` from the
     * descriptor and maps it. Null = nothing open (or a surface with no anchor,
     * e.g. wallpaper), so Ame falls back to the pill's own hover/wake anchor.
     */
    readonly property var ameSurface: pageAnchor(shownSurface)

    Ame {
        id: ame
        anchors.fill: parent
        s: pill.s
        heat: (pill.powerOpen && ldPower.page) ? ldPower.page.holdProgress : 0
        wake: pill.wakePoint
        wickDir: pill.powerOpen ? 1 : -1
        form: pill.ameSurface ? pill.ameSurface.ameForm : ((pill.dragStage === "hover" && pill.appImageDrop) || (pill.mode === "hover" && pill.hoverSoulGate) ? "soul" : "off")
        point: pill.ameSurface ? Qt.point(pill.ameSurface.x + pill.ameSurface.amePoint.x, pill.ameSurface.y + pill.ameSurface.amePoint.y) : (pill.dragStage === "hover" && pill.appImageDrop ? dragOverView.dropPoint : pill.mode === "hover" ? pill.soulPoint : pill.wakePoint)
    }

    /**
     * Extra input width past the pill's right edge while the media bud sticks
     * out there, so the window mask covers the bud's outer half. pill.hovered is
     * fed by a window-level HoverHandler in shell.qml: pointer events only exist
     * inside the input mask, so "window hovered" means "pointer over the pill (or
     * bud)". That sidesteps the per-item hover flicker the child MouseAreas and
     * the centred width morph would otherwise cause.
     */
    readonly property real inputPadRight: bud.shown ? bud.budR + 2 * s : 0

    onHoveredChanged: {
        if (hovered) {
            hoverClean = mode === "rest" || mode === "hover";
            graceTimer.stop();
            /** Click mode expands only through a tap (the pin); hover mode after the open delay. */
            if (bootSettled && Flags.expandMode !== "click") {
                if (Flags.openDelay > 0)
                    openTimer.restart();
                else
                    hoverLatch = true;
            }
        } else {
            openTimer.stop();
            graceTimer.restart();
        }
    }

    Timer {
        id: openTimer
        interval: Math.max(0, Flags.openDelay)
        onTriggered: if (pill.hovered)
            pill.hoverLatch = true
    }

    Timer {
        id: graceTimer
        interval: Math.max(0, Flags.closeDelay)
        onTriggered: {
            if (pill.morphCloseness < 0.95) {
                graceTimer.restart();
                return;
            }
            pill.hoverLatch = false;
        }
    }

    TapHandler {
        enabled: !pill.surfaceOpen
        gesturePolicy: TapHandler.WithinBounds
        onTapped: pill.pinned = !pill.pinned
    }

    property var installQueue: []

    function localPath(url) {
        var s = String(url);
        s = s.replace(/^file:\/\/(?:localhost)?(?=\/)/i, "");
        try {
            return decodeURIComponent(s);
        } catch (_error) {
            return s;
        }
    }

    readonly property var dropExt: /\.(appimage|deb|rpm|flatpakref|zip|tgz|txz|tbz2|ttf|otf|png|jpe?g|webp)$|\.(pkg\.)?tar\.(gz|xz|bz2|zst)$/i

    function installablePaths(localUrls) {
        return localUrls.map(url => pill.localPath(url)).filter(path => pill.dropExt.test(path));
    }

    function localFileUrls(urls) {
        return Array.from(urls, String).filter(url => /^file:\/\/(?:localhost)?\//i.test(url));
    }

    property bool installedAny: false
    property bool installedApp: false
    property bool installFailed: false
    property string installKind: "app"
    property string installAction: "new"
    property string installLine: ""
    property string installProto: ""
    property string installPct: ""
    property int installSeconds: 0

    function runNextInstall() {
        if (pill.installQueue.length === 0) {
            pill.dragStage = pill.installedAny ? "done" : "fail";
            (pill.installedAny ? dropDoneTimer : dropBadTimer).restart();
            return;
        }
        var next = pill.installQueue.shift();
        pill.dragName = next.substring(next.lastIndexOf("/") + 1).replace(pill.dropExt, "");
        pill.installLine = "";
        pill.installProto = "";
        pill.installPct = "";
        installProc.command = ["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/app-install.sh", "install", next];
        installProc.running = true;
    }

    /**
     * Streams installer stdout instead of collecting it: slow backends (flatpak
     * runtime pulls, pacman) narrate their steps, and the drop face mirrors the
     * newest line live. The machine-readable result is the one tab-separated
     * kind-prefixed line, fished out of the stream as it passes.
     */
    Process {
        id: installProc
        stdout: SplitParser {
            onRead: data => {
                var seg = data.split("\r").pop().replace(/\x1b\[[0-9;]*[a-zA-Z]/g, "").trim();
                if (seg.length === 0)
                    return;
                if (/^(app|native|font|wallpaper)\t/.test(seg)) {
                    pill.installProto = seg;
                } else {
                    pill.installLine = seg;
                    const pct = seg.match(/(\d{1,3})\s*%/);
                    if (pct && Number(pct[1]) <= 100)
                        pill.installPct = pct[1] + "%";
                }
            }
        }
        onExited: exitCode => {
            if (exitCode === 0 && pill.installProto.length > 0) {
                pill.installedAny = true;
                const parts = pill.installProto.split("\t");
                pill.installKind = parts[0];
                pill.installAction = parts[2];
                if (parts[0] === "app" || parts[0] === "native")
                    pill.installedApp = true;
                if (parts[0] === "font" && parts.length >= 4)
                    droppedFont.source = "file://" + parts[3];
            } else {
                pill.installFailed = true;
            }
            pill.runNextInstall();
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: pill.dragStage === "installing"
        onTriggered: pill.installSeconds++
    }

    /**
     * Registers a just-dropped font in this running process; the fontconfig
     * cache alone only reaches apps started later. Ready -> the font picker's
     * family list refreshes and the new face shows up without a restart.
     */
    FontLoader {
        id: droppedFont
        onStatusChanged: if (status === FontLoader.Ready)
            Theme.refreshFonts()
    }

    Timer {
        id: dropDoneTimer
        interval: 1100
        onTriggered: {
            pill.dragStage = "";
            if (pill.shelfStoredCount > 0) {
                pill.shelfStoredCount = 0;
                pill.requestSurface("file-shelf");
            } else if (pill.installedApp) {
                pill.requestSurface("launcher");
            }
        }
    }

    Timer {
        id: dropBadTimer
        interval: 1300
        onTriggered: {
            pill.dragStage = "";
        }
    }

    function installDropAt(x, y) {
        if (!installDropAvailable || pill.morphCloseness < 0.9)
            return false;
        const target = appImageDrop ? shelfInstallTarget : classicInstallTarget;
        return target.contains(target.mapFromItem(dropTarget, x, y));
    }

    function shelfItemSummary(files, folders) {
        const parts = [];
        if (folders > 0)
            parts.push(folders + (folders === 1 ? " folder" : " folders"));
        if (files > 0)
            parts.push(files + (files === 1 ? " file" : " files"));
        return parts.join(", ");
    }

    Process {
        id: shelfInspect
        property int request: 0

        function inspectLatest() {
            if (running || request === pill.shelfDropRequest || pill.dragStage !== "hover")
                return;
            request = pill.shelfDropRequest;
            command = ["python3", "-B", Quickshell.shellDir + "/lib/file_shelf.py", "inspect"].concat(pill.shelfDropUrls);
            running = true;
        }

        stdout: StdioCollector {
            onStreamFinished: {
                if (shelfInspect.request !== pill.shelfDropRequest || pill.dragStage !== "hover")
                    return;
                try {
                    const info = JSON.parse(text);
                    pill.shelfDropSummary = pill.shelfItemSummary(info.files, info.folders);
                    pill.installDropAvailable = pill.installDropCandidate && info.files === pill.shelfDropUrls.length;
                    if (pill.shelfDropUrls.length > 1 && pill.shelfDropSummary)
                        pill.dragName = pill.shelfDropSummary;
                } catch (_error) {}
            }
        }
        onExited: Qt.callLater(shelfInspect.inspectLatest)
    }

    Connections {
        target: FileShelf
        function onStored(files, folders, failures) {
            if (pill.dragStage !== "storing")
                return;
            const count = files + folders;
            pill.shelfStoredCount = count;
            pill.shelfStoredSummary = pill.shelfItemSummary(files, folders);
            pill.shelfFailedCount = failures;
            pill.dragStage = count > 0 ? "stored" : "store-failed";
            (count > 0 ? dropDoneTimer : dropBadTimer).restart();
        }
    }

    DropArea {
        id: dropTarget
        anchors.fill: parent
        enabled: !pill.surfaceOpen && !["installing", "storing", "done", "stored"].includes(pill.dragStage)
        keys: ["text/uri-list"]
        onEntered: drag => {
            const files = pill.localFileUrls(drag.urls);
            if (!(drag.supportedActions & Qt.CopyAction) || files.length === 0) {
                drag.accepted = false;
                return;
            }
            drag.accept(Qt.CopyAction);
            dropBadTimer.stop();
            dropDoneTimer.stop();
            const paths = pill.installablePaths(files);
            pill.installDropAvailable = false;
            pill.installDropCandidate = paths.length === drag.urls.length;
            pill.shelfDropSummary = "";
            pill.shelfDropUrls = files;
            pill.shelfDropRequest++;
            pill.installDropLabel = paths.every(path => /\.appimage$/i.test(path)) ? (paths.length === 1 ? "Install AppImage" : "Install AppImages") : paths.every(path => /\.(png|jpe?g|webp)$/i.test(path)) ? "Set wallpaper" : "Install";
            pill.overInstallTarget = false;
            pill.dragName = files.length === 1 ? pill.localPath(files[0]).replace(/\/+$/, "").split("/").pop() : files.length + " items";
            pill.dragStage = "hover";
            shelfInspect.inspectLatest();
        }
        onPositionChanged: drag => {
            if (pill.dragStage === "hover")
                pill.overInstallTarget = pill.installDropAt(drag.x, drag.y);
        }
        onExited: if (pill.dragStage === "hover")
            pill.dragStage = ""
        onDropped: drop => {
            if (pill.dragStage !== "hover")
                return;
            const urls = pill.localFileUrls(drop.urls);
            const paths = pill.installablePaths(urls);
            drop.accept(Qt.CopyAction);
            pill.installedApp = false;
            pill.shelfStoredCount = 0;
            pill.shelfFailedCount = 0;
            if (!(pill.overInstallTarget && paths.length === drop.urls.length && pill.installDropAt(drop.x, drop.y))) {
                pill.dragStage = "storing";
                if (!FileShelf.store(urls)) {
                    pill.dragStage = "store-failed";
                    dropBadTimer.restart();
                }
                return;
            }
            pill.dragStage = "installing";
            pill.installedAny = false;
            pill.installFailed = false;
            pill.installKind = "app";
            pill.installAction = "new";
            pill.installSeconds = 0;
            pill.installQueue = paths;
            pill.runNextInstall();
        }
    }

    /** The two drop targets share the pill's existing progress and result states. */
    Item {
        id: dragOverView
        anchors.fill: parent
        anchors.margins: 11 * pill.s
        enabled: pill.mode === "dragOver"
        opacity: pill.mode === "dragOver" ? Math.pow(pill.morphCloseness, 1.2) : 0
        visible: opacity > 0.01

        Behavior on opacity {
            NumberAnimation {
                duration: Motion.standard
                easing.type: Motion.easeStandard
            }
        }

        readonly property color accent: (pill.dragStage === "store-failed" || pill.dragStage === "fail") ? "#e0533f" : Theme.vermLit
        readonly property real brLen: 15 * pill.s
        readonly property real brThick: 2 * pill.s

        Repeater {
            model: [[0, 0], [1, 0], [0, 1], [1, 1]]
            delegate: Item {
                id: corner
                required property var modelData
                readonly property bool rightSide: modelData[0] === 1
                readonly property bool bottomSide: modelData[1] === 1
                x: rightSide ? dragOverView.width - dragOverView.brLen : 0
                y: bottomSide ? dragOverView.height - dragOverView.brLen : 0
                width: dragOverView.brLen
                height: dragOverView.brLen

                Rectangle {
                    width: dragOverView.brLen
                    height: dragOverView.brThick
                    radius: dragOverView.brThick / 2
                    color: dragOverView.accent
                    anchors.top: corner.bottomSide ? undefined : parent.top
                    anchors.bottom: corner.bottomSide ? parent.bottom : undefined
                    anchors.left: corner.rightSide ? undefined : parent.left
                    anchors.right: corner.rightSide ? parent.right : undefined
                }
                Rectangle {
                    width: dragOverView.brThick
                    height: dragOverView.brLen
                    radius: dragOverView.brThick / 2
                    color: dragOverView.accent
                    anchors.top: corner.bottomSide ? undefined : parent.top
                    anchors.bottom: corner.bottomSide ? parent.bottom : undefined
                    anchors.left: corner.rightSide ? undefined : parent.left
                    anchors.right: corner.rightSide ? parent.right : undefined
                }
            }
        }

        Rectangle {
            id: classicInstallTarget
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 4 * pill.s
            height: 27 * pill.s
            radius: 7 * pill.s
            visible: pill.dragStage === "hover" && !pill.appImageDrop && pill.installDropAvailable
            color: pill.overInstallTarget ? Qt.alpha(Theme.onGlow, 0.19) : Theme.frameBg

            Text {
                anchors.centerIn: parent
                text: pill.installDropLabel
                color: pill.overInstallTarget ? Theme.cream : Theme.subtle
                font.family: Theme.font
                font.pixelSize: 11 * pill.s
                font.weight: Font.DemiBold
            }
        }

        readonly property point dropPoint: {
            void pill.width;
            void pill.height;
            const card = pill.overInstallTarget ? shelfInstallTarget : shelfStoreTarget;
            return card.mapToItem(pill, card.width / 2, card.height + 5 * pill.s);
        }

        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: pill.dragStage === "hover" && pill.appImageDrop
            spacing: 9 * pill.s

            Text {
                width: parent.width
                text: pill.dragName
                textFormat: Text.PlainText
                elide: Text.ElideMiddle
                horizontalAlignment: Text.AlignHCenter
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 12 * pill.s
                font.weight: Font.DemiBold
            }

            Row {
                width: parent.width
                height: 55 * pill.s
                spacing: 7 * pill.s

                FileDropCard {
                    id: shelfStoreTarget
                    s: pill.s
                    width: (parent.width - parent.spacing) / 2
                    height: parent.height
                    title: "Store on shelf"
                    detail: "Temporary copy"
                    icon: "shelf"
                    current: !pill.overInstallTarget
                }
                FileDropCard {
                    id: shelfInstallTarget
                    s: pill.s
                    width: (parent.width - parent.spacing) / 2
                    height: parent.height
                    title: pill.installDropLabel
                    detail: "Add to launcher"
                    icon: "download"
                    current: pill.overInstallTarget
                }
            }
        }

        Column {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: classicInstallTarget.visible ? -12 * pill.s : 0
            visible: pill.dragStage !== "hover" || !pill.appImageDrop
            width: parent.width - 44 * pill.s
            spacing: 7 * pill.s

            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 26 * pill.s
                height: 26 * pill.s

                GlyphIcon {
                    anchors.fill: parent
                    stroke: 2
                    color: dragOverView.accent
                    name: (pill.dragStage === "store-failed" || pill.dragStage === "fail") ? "close" : (pill.dragStage === "installing" || pill.dragStage === "storing" ? "reboot" : (pill.dragStage === "done" || pill.dragStage === "stored" ? "check" : "shelf"))

                    RotationAnimation on rotation {
                        running: pill.dragStage === "installing" || pill.dragStage === "storing"
                        loops: Animation.Infinite
                        from: 0
                        to: 360
                        duration: 900
                    }
                    onNameChanged: if (name !== "reboot")
                        rotation = 0
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: {
                    switch (pill.dragStage) {
                    case "storing":
                        return "Storing " + (pill.shelfDropSummary || "items") + "…";
                    case "stored":
                        return "Stored " + pill.shelfStoredSummary;
                    case "store-failed":
                        return "Couldn’t store files";
                    case "fail":
                        return "Install failed";
                    case "installing":
                        {
                            const progress = pill.installPct ? " " + pill.installPct : "";
                            if (pill.installSeconds < 3)
                                return "Installing" + progress;
                            const minutes = Math.floor(pill.installSeconds / 60);
                            const seconds = String(pill.installSeconds % 60).padStart(2, "0");
                            return "Installing" + progress + "  " + minutes + ":" + seconds;
                        }
                    case "done":
                        if (pill.installFailed)
                            return "Installed, some failed";
                        if (!pill.installedApp && pill.installKind === "wallpaper")
                            return "Wallpaper set";
                        if (!pill.installedApp && pill.installKind === "font")
                            return "Font installed";
                        if (pill.installAction === "updated")
                            return "Updated";
                        if (pill.installAction === "reinstalled")
                            return "Reinstalled";
                        return "Installed";
                    default:
                        return "Store " + (pill.shelfDropSummary || "items");
                    }
                }
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 13 * pill.s
                font.weight: Font.Medium
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: (pill.dragStage === "store-failed" || (pill.dragStage === "stored" && pill.shelfFailedCount > 0)) && FileShelf.error ? FileShelf.error : pill.dragStage === "stored" && pill.shelfDropUrls.length > 1 ? "" : pill.dragStage === "installing" && pill.installLine.length > 0 ? pill.installLine : pill.dragName
                textFormat: Text.PlainText
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 11 * pill.s
                elide: Text.ElideMiddle
                maximumLineCount: 1
            }
        }
    }

    Item {
        id: rest
        anchors.fill: parent
        opacity: ((pill.expanded && !(pill.dictateHere && pill.mode === "rest")) || pill.dragActive || pill.mode === "toast" || pill.mode === "osd" || pill.mode === "quickChoose" || pill.mode === "quickCount") ? 0 : Math.pow(pill.morphCloseness, 1.5)
        visible: opacity > 0.01
        Behavior on opacity {
            NumberAnimation {
                duration: pill.mode === "rest" ? Motion.fast : Math.round(260 * Motion.mult)
            }
        }

        DictateBars {
            anchors.centerIn: restRow
            width: restRow.width
            height: pill.height
            s: pill.s
            visible: pill.dictateHere || opacity > 0.01
            opacity: pill.dictateHere ? 1 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: Motion.standard
                    easing.type: Motion.easeStandard
                }
            }
        }

        Row {
            id: restRow
            anchors.centerIn: parent
            spacing: 9 * pill.s
            opacity: pill.dictateHere ? 0 : 1
            scale: pill.dictateHere ? 0.92 : 1
            Behavior on opacity {
                NumberAnimation {
                    duration: Motion.standard
                    easing.type: Motion.easeStandard
                }
            }
            Behavior on scale {
                NumberAnimation {
                    duration: Motion.standard
                    easing.type: Motion.easeStandard
                }
            }
            Item {
                id: restKanji
                visible: pill.specialView === ""
                anchors.verticalCenter: parent.verticalCenter
                width: kanjiFill.implicitWidth
                height: kanjiFill.implicitHeight

                /** Audio leaving the speakers flips the clock glyph over to the live waveform. */
                readonly property bool barsOn: Flags.musicViz && Cava.active

                Text {
                    anchors.fill: parent
                    opacity: (Flags.showGlyphs && !restKanji.barsOn) ? 1 : 0
                    text: kanjiFill.text
                    color: "transparent"
                    font: kanjiFill.font
                    style: Text.Outline
                    styleColor: Qt.alpha(Theme.vermLit, Math.min(1, (pill.mode === "rest" || !pill.hoverSoulGate ? 0.5 : 0) + pill.kanjiFlash))
                    Behavior on opacity {
                        NumberAnimation {
                            duration: Motion.standard
                            easing.type: Motion.easeStandard
                        }
                    }
                }

                Text {
                    id: kanjiFill
                    opacity: (Flags.showGlyphs && !restKanji.barsOn) ? 1 : 0
                    text: "時"
                    color: Theme.cream
                    font.family: Theme.fontJp
                    font.weight: Font.Medium
                    font.pixelSize: 15 * pill.s
                    Behavior on opacity {
                        NumberAnimation {
                            duration: Motion.standard
                            easing.type: Motion.easeStandard
                        }
                    }
                }

                GlyphIcon {
                    anchors.centerIn: parent
                    opacity: (!Flags.showGlyphs && !restKanji.barsOn) ? 1 : 0
                    width: 17 * pill.s
                    height: 17 * pill.s
                    name: "clock"
                    color: Theme.cream
                    stroke: 1.7
                    Behavior on opacity {
                        NumberAnimation {
                            duration: Motion.standard
                            easing.type: Motion.easeStandard
                        }
                    }
                }

                MusicBars {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: kanjiFill.baseline
                    s: pill.s
                    opacity: restKanji.barsOn ? 1 : 0
                    scale: restKanji.barsOn ? 1 : 0.7
                    Behavior on opacity {
                        NumberAnimation {
                            duration: Motion.standard
                            easing.type: Motion.easeStandard
                        }
                    }
                    Behavior on scale {
                        NumberAnimation {
                            duration: Motion.standard
                            easing.type: Motion.easeStandard
                        }
                    }
                }
            }
            Text {
                visible: pill.specialView === ""
                anchors.verticalCenter: parent.verticalCenter
                text: clock.hhmm
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 16 * pill.s
                font.weight: Font.DemiBold
                font.features: {
                    "tnum": 1
                }
            }
            Text {
                visible: pill.specialView !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: pill.specialView
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 16 * pill.s
                font.weight: Font.DemiBold
            }
        }
    }

    Item {
        id: hover
        anchors.fill: parent
        opacity: pill.mode === "hover" ? Math.pow(pill.morphCloseness, 1.2) : 0
        visible: true
        Behavior on opacity {
            NumberAnimation {
                duration: pill.mode === "hover" ? Motion.fast : 40
            }
        }

        readonly property bool live: pill.mode === "hover"

        Row {
            id: hoverRow
            anchors.centerIn: parent
            spacing: 20 * pill.s

            Workspaces {
                id: ws
                anchors.verticalCenter: parent.verticalCenter
                width: implicitWidth
                screenName: pill.screenName
                s: pill.s
                style: Flags.wsStyle
                show: Flags.wsShow
                scroll: Flags.wsScroll
                gap: 8 * pill.s
                enabled: hover.live
                onHoverIndexChanged: if (hoverIndex >= 0) {
                    pill.soulTarget = "ws";
                    pill.soulWsIndex = hoverIndex;
                }
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: 22 * pill.s
                color: Theme.hair
            }

            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: hoverClock.implicitWidth
                height: hoverClock.implicitHeight

                Column {
                    id: hoverClock
                    anchors.centerIn: parent
                    spacing: 2 * pill.s
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: clock.hhmm
                        color: Theme.cream
                        font.family: Theme.font
                        font.pixelSize: 18 * pill.s
                        font.weight: Font.DemiBold
                        font.features: {
                            "tnum": 1
                        }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: clock.date
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 8.5 * pill.s
                        font.weight: Font.Medium
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 1.6 * pill.s
                    }
                }

                MouseArea {
                    anchors.centerIn: parent
                    width: hoverClock.implicitWidth + 22 * pill.s
                    height: hoverClock.implicitHeight + 10 * pill.s
                    enabled: hover.live
                    cursorShape: Qt.PointingHandCursor
                    onClicked: pill.requestSurface("clock")
                }
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: 22 * pill.s
                color: Theme.hair
            }

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12 * pill.s

                Row {
                    id: weatherGlance
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Weather.ready
                    spacing: 5 * pill.s

                    HoverHandler {
                        cursorShape: Qt.PointingHandCursor
                        enabled: hover.live
                        onHoveredChanged: if (hovered)
                            pill.soulTarget = "weather"
                    }
                    TapHandler {
                        enabled: hover.live
                        onTapped: pill.requestSurface("calendar")
                    }

                    GlyphIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 16 * pill.s
                        height: 16 * pill.s
                        name: Weather.glyphFor(Weather.codeNow, Weather.isDay)
                        color: Theme.subtle
                        stroke: 1.8
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Weather.tempNow + "°"
                        color: Theme.subtle
                        font.family: Theme.font
                        font.pixelSize: 12.5 * pill.s
                        font.weight: Font.Medium
                        font.features: {
                            "tnum": 1
                        }
                    }
                }

                MinimizedTray {
                    id: minimized
                    anchors.verticalCenter: parent.verticalCenter
                    s: pill.s
                    screenName: pill.screenName
                    enabled: hover.live
                    visible: count > 0
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: minimized.count > 0
                    width: 1
                    height: 14 * pill.s
                    color: Theme.hair
                    opacity: 0.7
                }

                Tray {
                    anchors.verticalCenter: parent.verticalCenter
                    s: pill.s
                    barWindow: pill.barWindow
                    enabled: hover.live
                }

                Item {
                    id: dndIcon
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Flags.dnd
                    width: 16 * pill.s
                    height: 16 * pill.s

                    Shape {
                        id: dndShape

                        width: 16
                        height: 16
                        scale: pill.s
                        transformOrigin: Item.TopLeft
                        x: dndShape.boundingRect.width > 0 ? dndIcon.width / 2 - (dndShape.boundingRect.x + dndShape.boundingRect.width / 2) * pill.s : (dndIcon.width - 16 * pill.s) / 2
                        y: dndShape.boundingRect.height > 0 ? dndIcon.height / 2 - (dndShape.boundingRect.y + dndShape.boundingRect.height / 2) * pill.s : (dndIcon.height - 16 * pill.s) / 2
                        preferredRendererType: Shape.CurveRenderer

                        ShapePath {
                            strokeColor: Theme.vermLit
                            strokeWidth: 1.5
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            joinStyle: ShapePath.RoundJoin
                            startX: 5.2
                            startY: 12.2
                            PathLine {
                                x: 12.2
                                y: 12.2
                            }
                            PathLine {
                                x: 12.2
                                y: 7.2
                            }
                            PathCubic {
                                control1X: 12.2
                                control1Y: 5.4
                                control2X: 11.2
                                control2Y: 4.0
                                x: 9.5
                                y: 3.5
                            }
                        }
                        ShapePath {
                            strokeColor: Theme.vermLit
                            strokeWidth: 1.5
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            startX: 6.8
                            startY: 13.6
                            PathLine {
                                x: 9.2
                                y: 13.6
                            }
                        }
                        ShapePath {
                            strokeColor: Theme.vermLit
                            strokeWidth: 1.6
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            startX: 3.2
                            startY: 2.8
                            PathLine {
                                x: 13.0
                                y: 13.4
                            }
                        }
                    }
                }

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 12 * pill.s

                    Item {
                        id: wifiIcon
                        anchors.verticalCenter: parent.verticalCenter
                        visible: pill.wifiDev !== null
                        width: 15 * pill.s
                        height: 15 * pill.s

                        WifiGlyph {
                            anchors.centerIn: parent
                            s: pill.s
                            level: pill.wifiLevel
                            on: pill.wifiOn
                            stroke: 1.7
                        }

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6 * pill.s
                            hoverEnabled: true
                            enabled: hover.live
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: e => {
                                if (e.button === Qt.RightButton) {
                                    if (typeof Networking !== "undefined" && Networking)
                                        Networking.wifiEnabled = !Networking.wifiEnabled;
                                    return;
                                }
                                pill.requestSurface("wifi");
                            }
                            onContainsMouseChanged: if (containsMouse)
                                pill.soulTarget = "wifi"
                        }
                    }

                    Item {
                        id: btIcon
                        anchors.verticalCenter: parent.verticalCenter
                        visible: pill.btAdapter !== null
                        width: 15 * pill.s + (btLowPct.visible ? btLowPct.implicitWidth + 4 * pill.s : 0)
                        height: 15 * pill.s

                        GlyphIcon {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: 15 * pill.s
                            height: 15 * pill.s
                            name: "bluetooth"
                            color: btArea.containsMouse ? Theme.cream : (Peripherals.connectedCount > 0 ? Theme.vermLit : (pill.btOn ? Theme.iconDim : Qt.alpha(Theme.iconDim, 0.4)))
                            stroke: 1.7
                        }

                        Text {
                            id: btLowPct
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            visible: Peripherals.lowestPct >= 0 && Peripherals.lowestPct <= Peripherals.lowAt
                            text: Peripherals.lowestPct + "%"
                            color: Theme.vermLit
                            font.family: Theme.font
                            font.pixelSize: 11 * pill.s
                            font.weight: Font.DemiBold
                            font.features: {
                                "tnum": 1
                            }
                        }

                        MouseArea {
                            id: btArea
                            anchors.fill: parent
                            anchors.margins: -6 * pill.s
                            hoverEnabled: true
                            enabled: hover.live
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: e => {
                                if (e.button === Qt.RightButton) {
                                    if (pill.btAdapter)
                                        pill.btAdapter.enabled = !pill.btAdapter.enabled;
                                    return;
                                }
                                pill.requestSurface("bt");
                            }
                            onContainsMouseChanged: if (containsMouse)
                                pill.soulTarget = "bt"
                        }
                    }

                    Item {
                        id: fileShelfIcon
                        anchors.verticalCenter: parent.verticalCenter
                        width: 17 * pill.s
                        height: width

                        GlyphIcon {
                            anchors.fill: parent
                            name: "shelf"
                            color: shelfArea.containsMouse ? Theme.cream : FileShelf.entries.length ? Theme.vermLit : Theme.iconDim
                            stroke: 1.7
                        }
                        MouseArea {
                            id: shelfArea
                            anchors.fill: parent
                            anchors.margins: -5 * pill.s
                            hoverEnabled: true
                            enabled: hover.live
                            cursorShape: Qt.PointingHandCursor
                            onClicked: pill.requestSurface("file-shelf")
                            onContainsMouseChanged: if (containsMouse)
                                pill.soulTarget = "file-shelf"
                        }
                        Tooltip {
                            s: pill.s
                            placement: "below"
                            title: "File shelf"
                            show: shelfArea.containsMouse
                        }
                    }

                    Item {
                        id: batteryIcon
                        anchors.verticalCenter: parent.verticalCenter
                        visible: Battery.present
                        width: battPct.implicitWidth
                        height: 17 * pill.s

                        Text {
                            id: battPct
                            anchors.centerIn: parent
                            text: Battery.pct + "%"
                            color: Battery.low ? Theme.vermLit : (Battery.charging ? Theme.flameGlow : Theme.subtle)
                            font.family: Theme.font
                            font.pixelSize: 13 * pill.s
                            font.weight: Battery.charging ? Font.DemiBold : Font.Medium
                            font.features: {
                                "tnum": 1
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6 * pill.s
                            hoverEnabled: true
                            enabled: hover.live
                            cursorShape: Qt.PointingHandCursor
                            onClicked: pill.requestSurface("battery")
                            onContainsMouseChanged: if (containsMouse)
                                pill.soulTarget = "battery"
                        }
                    }
                }

                Item {
                    id: inboxIcon
                    anchors.verticalCenter: parent.verticalCenter
                    width: 17 * pill.s
                    height: 17 * pill.s

                    GlyphIcon {
                        anchors.fill: parent
                        name: "inbox"
                        color: inboxArea.containsMouse ? Theme.cream : Theme.iconDim
                        stroke: 1.7
                    }

                    Rectangle {
                        visible: Notifs.unread > 0
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.topMargin: -2 * pill.s
                        anchors.rightMargin: -2 * pill.s
                        width: 5 * pill.s
                        height: 5 * pill.s
                        radius: width / 2
                        color: Theme.flameGlow
                    }

                    MouseArea {
                        id: inboxArea
                        anchors.fill: parent
                        anchors.margins: -6 * pill.s
                        hoverEnabled: true
                        enabled: hover.live
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pill.requestSurface("link")
                        onContainsMouseChanged: if (containsMouse)
                            pill.soulTarget = "inbox"
                    }
                }

                Item {
                    id: mixerIcon
                    anchors.verticalCenter: parent.verticalCenter
                    width: 17 * pill.s
                    height: 17 * pill.s

                    GlyphIcon {
                        anchors.fill: parent
                        name: "mixer"
                        color: mixerArea.containsMouse ? Theme.cream : Theme.iconDim
                        stroke: 1.7
                    }

                    MouseArea {
                        id: mixerArea
                        anchors.fill: parent
                        anchors.margins: -6 * pill.s
                        hoverEnabled: true
                        enabled: hover.live
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pill.requestSurface("mixer")
                        onContainsMouseChanged: if (containsMouse)
                            pill.soulTarget = "mixer"
                    }
                }

                Item {
                    id: soundIcon
                    anchors.verticalCenter: parent.verticalCenter
                    width: 17 * pill.s
                    height: 17 * pill.s

                    GlyphIcon {
                        anchors.fill: parent
                        name: "music"
                        color: soundArea.containsMouse ? Theme.cream : (Sound.eq ? Theme.vermLit : Theme.iconDim)
                        stroke: 1.7
                    }

                    MouseArea {
                        id: soundArea
                        anchors.fill: parent
                        anchors.margins: -6 * pill.s
                        hoverEnabled: true
                        enabled: hover.live
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pill.requestSurface("sound")
                        onContainsMouseChanged: if (containsMouse)
                            pill.soulTarget = "sound"
                    }
                }

                Item {
                    id: awakeIcon
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16 * pill.s
                    height: 16 * pill.s

                    GlyphIcon {
                        anchors.fill: parent
                        name: "awake"
                        color: awakeArea.containsMouse ? Theme.cream : (Awake.on ? Theme.vermLit : Theme.iconDim)
                        stroke: 1.7
                    }

                    MouseArea {
                        id: awakeArea
                        anchors.fill: parent
                        anchors.margins: -6 * pill.s
                        hoverEnabled: true
                        enabled: hover.live
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: e => {
                            if (e.button === Qt.RightButton) {
                                Awake.toggle();
                                return;
                            }
                            pill.requestSurface("awake");
                        }
                        onContainsMouseChanged: if (containsMouse)
                            pill.soulTarget = "awake"
                    }
                }

                Item {
                    id: sysmonIcon
                    anchors.verticalCenter: parent.verticalCenter
                    width: 17 * pill.s
                    height: 17 * pill.s

                    GlyphIcon {
                        anchors.fill: parent
                        name: "monitor"
                        color: sysmonArea.containsMouse ? Theme.cream : Theme.iconDim
                        stroke: 1.7
                    }

                    MouseArea {
                        id: sysmonArea
                        anchors.fill: parent
                        anchors.margins: -6 * pill.s
                        hoverEnabled: true
                        enabled: hover.live
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pill.requestSurface("sysmon")
                        onContainsMouseChanged: if (containsMouse)
                            pill.soulTarget = "sysmon"
                    }
                }

                Item {
                    id: recorderIcon
                    anchors.verticalCenter: parent.verticalCenter
                    width: 17 * pill.s
                    height: 17 * pill.s

                    GlyphIcon {
                        anchors.fill: parent
                        visible: !ScreenRec.recording
                        name: "video"
                        color: recorderArea.containsMouse ? Theme.cream : Theme.iconDim
                        stroke: 1.7
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        visible: ScreenRec.recording
                        width: 12 * pill.s
                        height: 12 * pill.s
                        radius: width / 2
                        color: Theme.verm
                        SequentialAnimation on opacity {
                            running: ScreenRec.recording
                            loops: Animation.Infinite
                            NumberAnimation {
                                to: 0.4
                                duration: 500
                                easing.type: Easing.InOutSine
                            }
                            NumberAnimation {
                                to: 1
                                duration: 500
                                easing.type: Easing.InOutSine
                            }
                        }
                    }

                    MouseArea {
                        id: recorderArea
                        anchors.fill: parent
                        anchors.margins: -6 * pill.s
                        hoverEnabled: true
                        enabled: hover.live
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: e => {
                            if (e.button === Qt.RightButton) {
                                if (ScreenRec.recording)
                                    ScreenRec.stop();
                                return;
                            }
                            pill.requestSurface("recorder");
                        }
                        onDoubleClicked: e => {
                            if (e.button === Qt.LeftButton && ScreenRec.recording)
                                ScreenRec.stop();
                        }
                        onContainsMouseChanged: if (containsMouse)
                            pill.soulTarget = "recorder"
                    }
                }

                Item {
                    id: settingsIcon
                    anchors.verticalCenter: parent.verticalCenter
                    width: 17 * pill.s
                    height: 17 * pill.s

                    GlyphIcon {
                        anchors.fill: parent
                        name: "cog"
                        color: settingsArea.containsMouse ? Theme.cream : Theme.iconDim
                        stroke: 1.6
                    }

                    MouseArea {
                        id: settingsArea
                        anchors.fill: parent
                        anchors.margins: -6 * pill.s
                        hoverEnabled: true
                        enabled: hover.live
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pill.requestSurface("settings")
                        onContainsMouseChanged: if (containsMouse)
                            pill.soulTarget = "settings"
                    }
                }

                Item {
                    id: powerIcon
                    anchors.verticalCenter: parent.verticalCenter
                    width: 17 * pill.s
                    height: 17 * pill.s

                    GlyphIcon {
                        anchors.fill: parent
                        name: "shutdown"
                        color: powerArea.containsMouse ? Theme.cream : Theme.iconDim
                        stroke: 1.7
                    }

                    MouseArea {
                        id: powerArea
                        anchors.fill: parent
                        anchors.margins: -6 * pill.s
                        hoverEnabled: true
                        enabled: hover.live
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pill.requestSurface("power")
                        onContainsMouseChanged: if (containsMouse)
                            pill.soulTarget = "power"
                    }
                }
            }
        }
    }

    // Give the mixer time to discover PipeWire devices before the first open.
    Timer {
        interval: 2500
        running: true
        onTriggered: {
            for (const loader of Object.values(pill.surfaces)) {
                if (loader.preload)
                    loader.active = true;
            }
        }
    }

    PillPageLoader {
        id: ldMixer
        host: pill
        readonly property Mixer page: item as Mixer
        preload: true
        morphSize: Qt.size(93 * Math.max(4, page?.faderCount ?? 0) * pill.s, 214 * pill.s)

        sourceComponent: Mixer {
            s: pill.s
            open: pill.mixerOpen
            morphCloseness: pill.morphCloseness
        }
    }

    PillPageLoader {
        id: ldCalendar
        host: pill
        readonly property Calendar page: item as Calendar
        pageWidth: ((page?.implicitWidth ?? 0) > 0 ? page.implicitWidth : 282 * pill.s) + 36 * pill.s
        heightPadding: 32 * pill.s

        sourceComponent: Calendar {
            s: pill.s
            open: pill.calendarOpen
            morphCloseness: pill.morphCloseness
            onRequestSurface: name => pill.requestSurface(name)
        }
    }

    PillPageLoader {
        id: ldClock
        host: pill
        readonly property ClockSurface page: item as ClockSurface
        pageWidth: 380 * pill.s

        sourceComponent: ClockSurface {
            s: pill.s
            open: pill.clockOpen
            morphCloseness: pill.morphCloseness
            onRequestClose: pill.requestClose()
            onRequestSurface: name => pill.requestSurface(name)
        }
    }

    PillPageLoader {
        id: ldLauncher
        host: pill
        morphSize: Qt.size(360 * pill.s, 332 * pill.s)

        sourceComponent: Launcher {
            s: pill.s
            open: pill.launcherOpen
            morphCloseness: pill.morphCloseness
            onRequestClose: pill.requestClose()
        }
    }

    PillPageLoader {
        id: ldEmoji
        host: pill
        morphSize: Qt.size(360 * pill.s, 332 * pill.s)

        sourceComponent: EmojiPicker {
            s: pill.s
            open: pill.emojiOpen
            morphCloseness: pill.morphCloseness
            onRequestClose: pill.requestClose()
        }
    }
    PillPageLoader {
        id: ldClip
        host: pill
        morphSize: Qt.size(360 * pill.s, 332 * pill.s)

        sourceComponent: Clipboard {
            s: pill.s
            open: pill.clipboardOpen
            morphCloseness: pill.morphCloseness
            onRequestClose: pill.requestClose()
        }
    }

    PillPageLoader {
        id: ldWall
        host: pill
        readonly property Wallpaper page: item as Wallpaper
        morphSize: Qt.size(720 * pill.s, 172 * pill.s)
        showAme: false

        sourceComponent: Wallpaper {
            s: pill.s
            open: pill.wallpaperOpen
            morphCloseness: pill.morphCloseness
            onRequestClose: pill.requestClose()
        }
    }

    PillPageLoader {
        id: ldPower
        host: pill
        readonly property Power page: item as Power
        morphSize: Qt.size(330 * pill.s, 150 * pill.s)

        sourceComponent: Power {
            s: pill.s
            open: pill.powerOpen
            morphCloseness: pill.morphCloseness
            onRequestClose: pill.requestClose()
        }
    }

    PillPageLoader {
        id: ldMedia
        host: pill
        preload: true
        morphSize: Qt.size((Players.pickable.length > 1 ? 460 : 390) * pill.s, 150 * pill.s)

        sourceComponent: Media {
            s: pill.s
            open: pill.mediaOpen
            morphCloseness: pill.morphCloseness
            onRequestClose: pill.requestClose()
            onRequestSurface: name => pill.requestSurface(name)
        }
    }

    PillPageLoader {
        id: ldLink
        host: pill
        readonly property Link page: item as Link
        preload: true
        pageWidth: page?.desiredW ?? 0
        heightPadding: 26 * pill.s

        sourceComponent: Link {
            s: pill.s
            open: pill.linkOpen
            morphCloseness: pill.morphCloseness
            onRequestClose: pill.requestClose()
        }
    }

    PillPageLoader {
        id: ldWifi
        host: pill
        pageWidth: 272 * pill.s
        heightPadding: 26 * pill.s

        sourceComponent: WifiSurface {
            s: pill.s
            open: pill.wifiOpen
            morphCloseness: pill.morphCloseness
            onRequestClose: pill.requestClose()
        }
    }

    PillPageLoader {
        id: ldBt
        host: pill
        pageWidth: 286 * pill.s
        heightPadding: 26 * pill.s

        sourceComponent: BtSurface {
            s: pill.s
            open: pill.btOpen
            morphCloseness: pill.morphCloseness
            onRequestClose: pill.requestClose()
        }
    }

    PillPageLoader {
        id: ldAwake
        host: pill
        readonly property AwakeSurface page: item as AwakeSurface

        sourceComponent: AwakeSurface {
            s: pill.s
            open: pill.awakeOpen
            morphCloseness: pill.morphCloseness
            onRequestClose: pill.requestClose()
        }
    }

    PillPageLoader {
        id: ldSound
        host: pill
        pageWidth: 400 * pill.s
        heightPadding: 34 * pill.s

        sourceComponent: SoundSurface {
            s: pill.s
            open: pill.soundOpen
            morphCloseness: pill.morphCloseness
            onRequestClose: pill.requestClose()
            onRequestSurface: name => pill.requestSurface(name)
        }
    }

    PillPageLoader {
        id: ldBattery
        host: pill
        pageWidth: 316 * pill.s
        heightPadding: 26 * pill.s

        sourceComponent: BatterySurface {
            s: pill.s
            open: pill.batteryOpen
            morphCloseness: pill.morphCloseness
            onRequestClose: pill.requestClose()
        }
    }

    PillPageLoader {
        id: ldSettings
        host: pill

        sourceComponent: Settings {
            s: pill.s
            open: pill.settingsOpen
            morphCloseness: pill.morphCloseness
            onRequestClose: pill.requestClose()
            onRequestSurface: name => pill.requestSurface(name)
        }
    }

    PillPageLoader {
        id: ldKeybinds
        host: pill
        readonly property Keybinds page: item as Keybinds
        pageWidth: 460 * pill.s

        sourceComponent: Keybinds {
            s: pill.s
            open: pill.keybindsOpen
            morphCloseness: pill.morphCloseness
            onRequestClose: pill.requestClose()
        }
    }

    PillPageLoader {
        id: ldWorkspaces
        host: pill
        readonly property WorkspacesSurface page: item as WorkspacesSurface

        sourceComponent: WorkspacesSurface {
            s: pill.s
            open: pill.workspacesOpen
            morphCloseness: pill.morphCloseness
            onRequestClose: pill.requestClose()
            onRequestSurface: name => pill.requestSurface(name)
        }
    }

    PillPageLoader {
        id: ldStash
        host: pill
        readonly property Stash page: item as Stash

        sourceComponent: Stash {
            s: pill.s
            open: pill.stashOpen
            morphCloseness: pill.morphCloseness
            onRequestClose: pill.requestClose()
        }
    }

    PillPageLoader {
        id: ldSpaceapps
        host: pill
        readonly property SpaceApps page: item as SpaceApps

        sourceComponent: SpaceApps {
            s: pill.s
            open: pill.spaceappsOpen
            morphCloseness: pill.morphCloseness
            onRequestClose: pill.requestClose()
        }
    }

    PillPageLoader {
        id: ldRecorder
        host: pill
        readonly property Recorder page: item as Recorder
        pageWidth: 384 * pill.s
        heightPadding: 33 * pill.s

        sourceComponent: Recorder {
            s: pill.s
            screenName: pill.screenName
            open: pill.recorderOpen
            morphCloseness: pill.morphCloseness
            onRequestClose: pill.requestClose()
        }
    }

    PillPageLoader {
        id: ldSysmon
        host: pill
        readonly property SysmonSurface page: item as SysmonSurface
        heightPadding: 33 * pill.s

        sourceComponent: SysmonSurface {
            s: pill.s
            open: pill.sysmonOpen
            morphCloseness: pill.morphCloseness
            onRequestDetail: key => pill.requestSurface("sysmon-" + key)
            onRequestClose: pill.requestClose()
        }
    }

    PillPageLoader {
        id: ldFileShelf
        host: pill
        readonly property FileShelfSurface page: item as FileShelfSurface
        pageWidth: 352 * pill.s
        heightPadding: 30 * pill.s

        sourceComponent: FileShelfSurface {
            s: pill.s
            open: pill.fileShelfOpen
            morphCloseness: pill.morphCloseness
        }
    }

    PillPageLoader {
        id: ldSysmonApps
        host: pill
        readonly property SysmonApps page: item as SysmonApps
        pageWidth: 536 * pill.s
        heightPadding: 33 * pill.s

        sourceComponent: SysmonApps {
            s: pill.s
            open: pill.surface === "sysmon-apps"
            morphCloseness: pill.morphCloseness
            onRequestClose: pill.sysmonEscape()
        }
    }

    Repeater {
        id: sysmonDetails
        model: pill.sysmonPages

        PillPageLoader {
            id: detailLoader
            host: pill
            required property string modelData

            heightPadding: 33 * pill.s

            sourceComponent: SysmonDetail {
                s: pill.s
                page: detailLoader.modelData
                open: pill.surface === "sysmon-" + page
                morphCloseness: pill.morphCloseness
                onRequestClose: pill.requestClose()
            }
        }
    }

    PillPageLoader {
        id: ldAppearance
        host: pill

        sourceComponent: Appearance {
            s: pill.s
            open: pill.appearanceOpen
            morphCloseness: pill.morphCloseness
            onRequestClose: pill.requestClose()
            onRequestSurface: name => pill.requestSurface(name)
        }
    }

    PillPageLoader {
        id: ldDisplay
        host: pill

        sourceComponent: Display {
            s: pill.s
            open: pill.displayOpen
            morphCloseness: pill.morphCloseness
            onRequestClose: pill.requestClose()
            onRequestSurface: name => pill.requestSurface(name)
        }
    }

    PillPageLoader {
        id: ldInput
        host: pill

        sourceComponent: Input {
            s: pill.s
            open: pill.inputOpen
            morphCloseness: pill.morphCloseness
            onRequestClose: pill.requestClose()
            onRequestSurface: name => pill.requestSurface(name)
        }
    }

    PillPageLoader {
        id: ldLook
        host: pill

        sourceComponent: Look {
            s: pill.s
            open: pill.lookOpen
            morphCloseness: pill.morphCloseness
            onRequestClose: pill.requestClose()
            onRequestSurface: name => pill.requestSurface(name)
        }
    }

    PillPageLoader {
        id: ldAnimation
        host: pill

        sourceComponent: AnimationSurface {
            s: pill.s
            open: pill.animationOpen
            morphCloseness: pill.morphCloseness
            onRequestClose: pill.requestClose()
            onRequestSurface: name => pill.requestSurface(name)
        }
    }

    PillPageLoader {
        id: ldTime
        host: pill

        sourceComponent: TimeSurface {
            s: pill.s
            open: pill.timeOpen
            morphCloseness: pill.morphCloseness
            onRequestClose: pill.requestClose()
            onRequestSurface: name => pill.requestSurface(name)
        }
    }

    PillPageLoader {
        id: ldNotifications
        host: pill

        sourceComponent: NotificationsSurface {
            s: pill.s
            open: pill.notificationsOpen
            morphCloseness: pill.morphCloseness
            onRequestClose: pill.requestClose()
            onRequestSurface: name => pill.requestSurface(name)
        }
    }

    PillPageLoader {
        id: ldDictation
        host: pill
        readonly property Dictation page: item as Dictation

        sourceComponent: Dictation {
            s: pill.s
            open: pill.dictationOpen
            morphCloseness: pill.morphCloseness
            onRequestClose: pill.requestClose()
            onRequestSurface: name => pill.requestSurface(name)
        }
    }

    PillPageLoader {
        id: ldVocab
        host: pill
        readonly property Vocab page: item as Vocab

        sourceComponent: Vocab {
            s: pill.s
            open: pill.vocabOpen
            morphCloseness: pill.morphCloseness
            onRequestClose: pill.requestClose()
            onRequestSurface: name => pill.requestSurface(name)
        }
    }

    PillPageLoader {
        id: ldFontpicker
        host: pill
        pageWidth: 360 * pill.s

        sourceComponent: FontPicker {
            s: pill.s
            open: pill.fontpickerOpen
            morphCloseness: pill.morphCloseness
            onRequestClose: pill.requestClose()
        }
    }

    Osd {
        id: osd
        anchors.fill: parent
        anchors.topMargin: 12 * pill.s
        anchors.leftMargin: 18 * pill.s
        anchors.rightMargin: 18 * pill.s
        anchors.bottomMargin: 12 * pill.s
        s: pill.s
        screenName: pill.screenName
        suppressed: pill.holding
        expanded: pill.expanded
        enabled: pill.mode === "osd"
        /**
         * Fades in with the pill's own opening, like the other morph modes. On
         * the way out it dissolves over the first part of the shrink (the
         * clipped rows narrow away with the pill) instead of vanishing at once.
         */
        opacity: pill.mode === "osd" ? Math.pow(pill.morphCloseness, 1.3) : 0
        visible: opacity > 0.01
        Behavior on opacity {
            NumberAnimation {
                duration: pill.mode === "osd" ? 60 : 240
                easing.type: Easing.OutCubic
            }
        }
    }

    Loader {
        id: toastLoader
        active: pill.toastActive
        anchors.fill: parent
        anchors.topMargin: 12 * pill.s
        anchors.leftMargin: 16 * pill.s
        anchors.rightMargin: 16 * pill.s
        anchors.bottomMargin: 12 * pill.s
        enabled: pill.mode === "toast"
        opacity: pill.mode === "toast" ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity {
            NumberAnimation {
                duration: Motion.standard
                easing.type: Motion.easeStandard
            }
        }

        sourceComponent: Item {
            implicitHeight: toastContent.implicitHeight

            Toast {
                id: toastContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                s: pill.s
                live: pill.mode === "toast"
                host: pill
                notif: Notifs.popups.length > 0 ? Notifs.popups[Notifs.popups.length - 1] : null
            }

            Text {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                visible: Notifs.popups.length > 1
                text: "+" + (Notifs.popups.length - 1)
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 9 * pill.s
                font.weight: Font.DemiBold
            }
        }
    }

    /**
     * Standalone quick-record source chooser. Driven by the SUPER+D keybind with
     * no recorder surface open: it grows the pill on the focused monitor only
     * (mode "quickChoose") and offers the same Screen and Window / Region picks as
     * the surface. Screen with one monitor resolves at once; several monitors flip
     * to the inline sub-choice. A pick fires ScreenRec.prepareScreen / prepareWindow
     * → targetReady → the central countdown, then closes.
     */
    Item {
        anchors.fill: parent
        anchors.margins: 6 * pill.s
        enabled: pill.mode === "quickChoose"
        opacity: pill.mode === "quickChoose" ? Math.pow(pill.morphCloseness, 1.3) : 0
        visible: opacity > 0.01
        Behavior on opacity {
            NumberAnimation {
                duration: Motion.standard
                easing.type: Motion.easeStandard
            }
        }

        Row {
            id: quickSources
            anchors.fill: parent
            visible: !ScreenRec.quickScreenChoosing
            spacing: 6 * pill.s

            Repeater {
                model: [
                    {
                        kind: "screen",
                        label: "Screen",
                        glyph: "monitor"
                    },
                    {
                        kind: "window",
                        label: "Window / Region",
                        glyph: "video"
                    }
                ]

                Rectangle {
                    id: qSrcTile
                    required property var modelData
                    width: (quickSources.width - 6 * pill.s) / 2
                    height: parent.height
                    radius: 11 * pill.s
                    color: qSrcArea.containsMouse ? Qt.alpha(Theme.vermLit, 0.16) : Theme.tileBg
                    border.width: 1
                    border.color: qSrcArea.containsMouse ? Qt.alpha(Theme.vermLit, 0.5) : Theme.border
                    Behavior on color {
                        ColorAnimation {
                            duration: Motion.fast
                        }
                    }

                    Row {
                        anchors.centerIn: parent
                        spacing: 8 * pill.s

                        GlyphIcon {
                            width: 16 * pill.s
                            height: 16 * pill.s
                            name: qSrcTile.modelData.glyph
                            color: qSrcArea.containsMouse ? Theme.vermLit : Theme.iconDim
                            stroke: 1.7
                        }
                        Text {
                            height: 16 * pill.s
                            verticalAlignment: Text.AlignVCenter
                            text: qSrcTile.modelData.label
                            color: qSrcArea.containsMouse ? Theme.cream : Theme.subtle
                            font.family: Theme.font
                            font.pixelSize: 11 * pill.s
                            font.weight: Font.Bold
                        }
                    }

                    MouseArea {
                        id: qSrcArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pill.quickChooseSource(qSrcTile.modelData.kind)
                    }
                }
            }
        }

        ListView {
            id: quickScreens
            anchors.fill: parent
            anchors.rightMargin: 22 * pill.s
            visible: ScreenRec.quickScreenChoosing
            orientation: ListView.Horizontal
            spacing: 6 * pill.s
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: ScreenRec.monitors

            delegate: Rectangle {
                id: qMonTile
                required property var modelData
                width: 152 * pill.s
                height: quickScreens.height
                radius: 11 * pill.s
                color: qMonArea.containsMouse ? Qt.alpha(Theme.vermLit, 0.16) : Theme.tileBg
                border.width: 1
                border.color: qMonArea.containsMouse ? Qt.alpha(Theme.vermLit, 0.5) : Theme.border
                Behavior on color {
                    ColorAnimation {
                        duration: Motion.fast
                    }
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 2 * pill.s

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: qMonTile.modelData.name
                        color: Theme.cream
                        font.family: Theme.font
                        font.pixelSize: 11.5 * pill.s
                        font.weight: Font.Bold
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: qMonTile.modelData.w + " × " + qMonTile.modelData.h
                        color: Theme.subtle
                        font.family: Theme.font
                        font.pixelSize: 9.5 * pill.s
                        font.features: {
                            "tnum": 1
                        }
                    }
                }

                MouseArea {
                    id: qMonArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: pill.quickPickMonitor(qMonTile.modelData.name)
                }
            }
        }

        WheelScroller {
            flick: quickScreens
            s: pill.s
            anchors.fill: quickScreens
            visible: ScreenRec.quickScreenChoosing
        }

        GlyphIcon {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 5 * pill.s
            visible: ScreenRec.quickScreenChoosing
            width: 12 * pill.s
            height: 12 * pill.s
            name: "chevron-left"
            color: qBackArea.containsMouse ? Theme.cream : Theme.faint
            stroke: 2

            MouseArea {
                id: qBackArea
                anchors.fill: parent
                anchors.margins: -7 * pill.s
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: ScreenRec.quickScreenChoosing = false
            }
        }
    }

    /**
     * Standalone pre-roll countdown toast. Shown at the pill top on the focused
     * monitor when the central countdown runs and the recorder surface is closed
     * (mode "quickCount"): a big flame-glow numeral over a small "GET READY" label.
     * Tapping cancels. The surface's own in-bar countdown covers the surface case.
     */
    Item {
        id: quickCount
        anchors.fill: parent
        enabled: pill.mode === "quickCount"
        opacity: pill.mode === "quickCount" ? Math.pow(pill.morphCloseness, 1.3) : 0
        visible: opacity > 0.01
        Behavior on opacity {
            NumberAnimation {
                duration: Motion.standard
                easing.type: Motion.easeStandard
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 1 * pill.s

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: ScreenRec.countdown
                color: Theme.flameGlow
                font.family: Theme.font
                font.pixelSize: 28 * pill.s
                font.weight: Font.ExtraBold
                font.features: {
                    "tnum": 1
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "GET READY"
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 8.5 * pill.s
                font.weight: Font.Bold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.6 * pill.s
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: ScreenRec.cancel()
        }
    }
}
