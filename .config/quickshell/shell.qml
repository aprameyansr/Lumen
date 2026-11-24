//@ pragma UseQApplication

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "Singletons"

// Each monitor has a reserved strip for tiled windows and an overlay for the pill.
// The overlay's input mask expands when a page, pin, or quick chooser needs it.
ShellRoot {
    id: root

    property string openMon: ""
    property string openSurface: ""
    property string peekMon: ""

    onOpenSurfaceChanged: {
        const detail = openSurface.startsWith("sysmon-");
        if (openSurface === "sysmon" || detail) {
            Sysmon.page = detail ? openSurface.slice("sysmon-".length) : "";
            Sysmon.open = true;
        } else if (Sysmon.open) {
            Sysmon.open = false;
            Sysmon.page = "";
        }
    }

    function refresh() {
        Hyprland.refreshMonitors();
        Hyprland.refreshWorkspaces();
        Hyprland.refreshToplevels();
    }

    Component.onCompleted: {
        // Restore saved keep-awake and audio settings by instantiating the singletons.
        void Awake.on;
        void Sound.eq;
        refresh();
    }

    Connections {
        target: Quickshell

        function onReloadCompleted() {
            Quickshell.inhibitReloadPopup();

            Quickshell.execDetached(["notify-send", "-a", "Quickshell", "Quickshell", "Configuration reloaded successfully"]);
        }
    }

    PanelWindow {
        id: inhibitWin
        visible: Flags.keepAwake
        implicitWidth: 1
        implicitHeight: 1
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: "pill-inhibit"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        anchors {
            top: true
            left: true
        }
        IdleInhibitor {
            window: inhibitWin
            enabled: Flags.keepAwake
        }
    }

    // Refresh Hyprland models only for events that can affect the pill.
    readonly property var refreshEvents: ({
            workspace: true,
            workspacev2: true,
            createworkspace: true,
            createworkspacev2: true,
            destroyworkspace: true,
            destroyworkspacev2: true,
            moveworkspace: true,
            moveworkspacev2: true,
            renameworkspace: true,
            activespecial: true,
            focusedmon: true,
            focusedmonv2: true,
            openwindow: true,
            closewindow: true,
            movewindow: true,
            movewindowv2: true,
            fullscreen: true,
            monitoradded: true,
            monitoraddedv2: true,
            monitorremoved: true
        })

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (root.refreshEvents[event.name])
                root.refresh();
        }
    }

    /**
     * An empty monitor argument resolves to the focused monitor here, so the
     * keybind scripts skip their hyprctl+jq round trip and a surface open costs
     * one IPC call instead of three process spawns.
     */
    function toggleSurface(mon, surface) {
        if (!mon || mon.length === 0)
            mon = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        if (root.openMon === mon && root.openSurface === surface) {
            root.close();
            return;
        }
        root.openMon = mon;
        root.openSurface = surface;
    }

    function close() {
        root.openMon = "";
        root.openSurface = "";
    }

    function peek(mon) {
        root.peekMon = root.peekMon === mon ? "" : mon;
    }

    /** Dictation key, driveable without the bind: `qs ipc call dictate press` / `release` / `cancel`. */
    IpcHandler {
        target: "dictate"
        function press(): void {
            Dictate.press();
        }
        function release(): void {
            Dictate.release();
        }
        function cancel(): void {
            Dictate.cancel();
        }
        function settings(mon: string): void {
            root.toggleSurface(mon, "dictation");
        }
    }

    IpcHandler {
        target: "pill"
        function mixer(mon: string): void {
            root.toggleSurface(mon, "mixer");
        }
        function calendar(mon: string): void {
            root.toggleSurface(mon, "calendar");
        }
        function clock(mon: string): void {
            root.toggleSurface(mon, "clock");
        }
        function sound(mon: string): void {
            root.toggleSurface(mon, "sound");
        }
        function eq(): void {
            Sound.setEq(!Sound.eq);
        }
        function eqMode(name: string): void {
            Sound.pick(name);
        }
        function micFilter(): void {
            Sound.setDenoise(!Sound.denoise);
        }
        /** Start a timer of `minutes` on the clock page's timer; 0 cancels it. */
        function timer(minutes: string): void {
            Clocks.tmStartMinutes(Number(minutes) || 0);
        }
        function launcher(mon: string): void {
            root.toggleSurface(mon, "launcher");
        }
        function fileShelf(mon: string): void {
            root.toggleSurface(mon, "file-shelf");
        }
        function emoji(mon: string): void {
            root.toggleSurface(mon, "emoji");
        }
        function power(mon: string): void {
            root.toggleSurface(mon, "power");
        }
        function link(mon: string): void {
            root.toggleSurface(mon, "link");
        }
        function battery(mon: string): void {
            root.toggleSurface(mon, "battery");
        }
        function settings(mon: string): void {
            root.toggleSurface(mon, "settings");
        }
        function keybinds(mon: string): void {
            root.toggleSurface(mon, "keybinds");
        }
        function recorder(mon: string): void {
            root.toggleSurface(mon, "recorder");
        }
        function screenrec(mon: string): void {
            root.toggleSurface(mon, "recorder");
        }
        function record(mon: string): void {
            root.toggleSurface(mon, "recorder");
        }

        /**
         * Quick-record keybind (SUPER+D): one button cycles the whole flow with no
         * surface. Recording → stop. Counting down → cancel. A chooser already up
         * on this monitor → dismiss. Otherwise open the standalone source chooser on
         * the focused monitor `mon`, so only that pill renders it.
         */
        function quickRecord(mon: string): void {
            if (ScreenRec.recording) {
                ScreenRec.stop();
            } else if (ScreenRec.counting) {
                ScreenRec.cancel();
            } else if (ScreenRec.quickChoosing) {
                ScreenRec.quickChoosing = false;
                ScreenRec.quickScreenChoosing = false;
            } else {
                ScreenRec.quickMon = mon;
                ScreenRec.quickScreenChoosing = false;
                ScreenRec.quickChoosing = true;
            }
        }
        function dnd(mon: string): void {
            Flags.dnd = !Flags.dnd;
        }
        function awake(mon: string): void {
            root.toggleSurface(mon, "awake");
        }
        function keepAwake(mon: string): void {
            Awake.toggle();
        }
        function sysmon(mon: string): void {
            root.toggleSurface(mon, "sysmon");
        }
        function system(mon: string): void {
            root.toggleSurface(mon, "sysmon");
        }
        function clipboard(mon: string): void {
            root.toggleSurface(mon, "clipboard");
        }
        function wallpaper(mon: string): void {
            root.toggleSurface(mon, "wallpaper");
        }
        function media(mon: string): void {
            if (Players.list.length > 0)
                root.toggleSurface(mon, "media");
        }
        function peek(mon: string): void {
            root.peek(mon);
        }
        function hide(): void {
            root.close();
        }

        /** Opens any surface by name, settings sub-pages included; dev and scripting door. */
        function page(mon: string, name: string): void {
            root.toggleSurface(mon, name);
        }

        /**
         * The two halves of the SUPER+M minimize toggle, driven by the
         * minimize-toggle script which has already read the focused window. A
         * desktop window drops into the minimized stash; a window already stashed
         * comes back to the workspace it is handed, so the same key hides and
         * restores. Both target the window by address so they act on the one the
         * user pressed on, not whatever the compositor calls active afterwards.
         */
        function minimizeWindow(addr: string): void {
            Hyprland.dispatch('hl.dsp.window.move({ workspace = "special:minimized", follow = false, window = "address:' + addr + '" })');
        }
        function restoreWindow(arg: string): void {
            var p = arg.split("|");
            if (p.length < 2 || p[0].length === 0)
                return;
            Hyprland.dispatch('hl.dsp.window.move({ workspace = ' + p[1] + ', window = "address:' + p[0] + '" })');
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: reserve
            required property var modelData
            readonly property real s: modelData ? (modelData.height / 1080) * Flags.uiScale : 1
            readonly property real topGap: 8 * Flags.topGap * s
            readonly property real restHeight: 38 * s

            /** Trimming the reserved band below the pill's bottom lets windows climb, so App gap sets the pill-to-window air without touching the desktop gaps_out. */
            readonly property real reservedH: Math.max(0, restHeight + topGap - 12 * (1 - Flags.appGap) * s)

            screen: modelData
            color: "transparent"
            exclusionMode: ExclusionMode.Normal
            exclusiveZone: reservedH
            aboveWindows: true

            anchors {
                top: true
                left: true
                right: true
            }
            implicitHeight: reservedH

            mask: emptyReserve
            Region {
                id: emptyReserve
            }
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: overlay
            required property var modelData
            readonly property real s: modelData ? (modelData.height / 1080) * Flags.uiScale : 1
            readonly property real topGap: 8 * Flags.topGap * s
            readonly property string surface: root.openMon === modelData.name ? root.openSurface : ""
            readonly property bool surfaceOpen: surface.length > 0
            readonly property bool modal: surfaceOpen || pill.held || pill.quickChoosing

            readonly property bool monFullscreen: {
                const monitor = Hyprland.monitors.values.find(monitor => monitor.name === modelData.name);
                if (!monitor)
                    return false;
                if (workspaceFullscreen(monitor.activeWorkspace))
                    return true;
                const special = monitor.lastIpcObject?.specialWorkspace?.name;
                if (!special?.startsWith("special:"))
                    return false;
                const workspace = Hyprland.workspaces.values.find(workspace => workspace?.name === special);
                return workspaceFullscreen(workspace);
            }

            function workspaceFullscreen(workspace) {
                return workspace?.toplevels.values.some(window => window.lastIpcObject?.fullscreen === 2) ?? false;
            }

            readonly property bool summoned: modal || root.peekMon === modelData.name
            readonly property bool pillHidden: monFullscreen && !summoned

            onMonFullscreenChanged: if (monFullscreen) {
                if (root.openMon === modelData.name)
                    root.close();
                if (root.peekMon === modelData.name)
                    root.peekMon = "";
                pill.pinned = false;
            }

            screen: modelData
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: (surfaceOpen || pill.quickChoosing) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            WlrLayershell.namespace: "pill"

            anchors {
                top: true
                left: true
                right: true
                bottom: true
            }

            mask: modal && !pill.shelfDragging ? fullRegion : (pillHidden ? hiddenRegion : pillRegion)
            Region {
                id: hiddenRegion
            }
            Region {
                id: pillRegion
                readonly property real baseW: Math.max(pill.width, pill.targetW)
                x: slot.x + pill.x + (pill.width - baseW) / 2
                y: slot.y + pill.y
                width: baseW + pill.inputPadRight
                height: Math.max(pill.height, pill.targetH)
            }
            Region {
                id: fullRegion
                width: overlay.width
                height: overlay.height
            }

            MouseArea {
                anchors.fill: parent
                enabled: overlay.modal
                acceptedButtons: Qt.AllButtons
                onPressed: mouse => {
                    if (pill.quickChoosing) {
                        ScreenRec.quickChoosing = false;
                        ScreenRec.quickScreenChoosing = false;
                    } else if (overlay.surfaceOpen) {
                        const inside = mouse.x >= pillRegion.x && mouse.x <= pillRegion.x + pillRegion.width && mouse.y >= pillRegion.y && mouse.y <= pillRegion.y + pillRegion.height;
                        if (!inside)
                            root.close();
                        else if (mouse.y <= pillRegion.y + 40 * pill.s)
                            pill.surfaceBack();
                    } else {
                        pill.pinned = false;
                        root.peekMon = "";
                    }
                }
            }

            FocusScope {
                id: focusScope
                anchors.fill: parent
                focus: overlay.surfaceOpen || pill.quickChoosing

                HoverHandler {
                    onHoveredChanged: pill.hovered = hovered
                }
                Keys.onEscapePressed: {
                    if (pill.criticalToast)
                        return;
                    if (pill.quickChoosing) {
                        ScreenRec.quickChoosing = false;
                        ScreenRec.quickScreenChoosing = false;
                    } else if (!pill.sysmonEscape() && !pill.keybindsBack() && !pill.vocabBack()) {
                        root.close();
                    }
                }
                Keys.onUpPressed: event => moveVertical(event, -1)
                Keys.onDownPressed: event => moveVertical(event, 1)
                Keys.onLeftPressed: event => moveHorizontal(event, -1)
                Keys.onRightPressed: event => moveHorizontal(event, 1)

                function moveVertical(event, direction) {
                    if (pill.criticalToast) {
                        event.accepted = true;
                    } else if (pill.clockOpen) {
                        event.accepted = pill.clockKey(event.key, event.modifiers);
                    } else if (pill.keybindsOpen && !pill.keybindsListening) {
                        pill.keybindsMove(direction);
                        event.accepted = true;
                    } else {
                        event.accepted = pill.fileShelfMove(direction) || pill.sysmonMove(0, direction) || pill.mixerStep(-direction) || pill.recorderStep(-5 * direction) || pill.settingsMove(direction);
                    }
                }

                function moveHorizontal(event, direction) {
                    if (pill.criticalToast) {
                        event.accepted = true;
                    } else if (pill.clockOpen) {
                        event.accepted = pill.clockKey(event.key, event.modifiers);
                    } else if (pill.mixerOpen) {
                        pill.mixerFocusMove(direction);
                        event.accepted = true;
                    } else if (pill.wallpaperOpen) {
                        pill.wallpaperMove(direction);
                        event.accepted = true;
                    } else if (pill.powerOpen) {
                        pill.powerMove(direction);
                        event.accepted = true;
                    } else if (pill.sysmonOpen) {
                        event.accepted = pill.sysmonMove(direction, 0);
                    } else if (pill.recorderOpen) {
                        event.accepted = pill.recorderStep(5 * direction);
                    } else if (pill.settingsLike) {
                        pill.settingsAdjust(direction);
                        event.accepted = true;
                    }
                }

                Keys.onPressed: e => {
                    /** A critical notification covers the open page; keep keys off the hidden page until it clears. */
                    if (pill.criticalToast) {
                        e.accepted = true;
                        return;
                    }
                    if (pill.clockOpen) {
                        if (!e.isAutoRepeat && pill.clockKey(e.key, e.modifiers))
                            e.accepted = true;
                        return;
                    }
                    if (pill.wallpaperOpen && !pill.wallpaperSearching && e.text.length === 1 && e.text > " ") {
                        pill.wallpaperType(e.text);
                        e.accepted = true;
                        return;
                    }
                    if (pill.powerOpen && e.text.length === 1 && "wlsruWLSRU".indexOf(e.text) >= 0) {
                        if (!e.isAutoRepeat)
                            pill.powerHotkey(e.text);
                        e.accepted = true;
                        return;
                    }
                    /** Held Shift+Delete on dictation or vocabulary drives the clear-all heat; release drains it. */
                    if (e.key === Qt.Key_Delete && (e.modifiers & Qt.ShiftModifier) && (pill.dictationOpen || pill.vocabOpen)) {
                        if (!e.isAutoRepeat)
                            pill.wipePress();
                        e.accepted = true;
                        return;
                    }
                    /** Held Delete on keep-awake drives the focused preset's hold-to-wipe heat. */
                    if (e.key === Qt.Key_Delete && pill.awakeOpen) {
                        if (!e.isAutoRepeat)
                            pill.awakeDelete();
                        e.accepted = true;
                        return;
                    }
                    if (pill.vocabOpen && e.text.length === 1 && e.text > " " && !(e.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) && pill.vocabType(e.text)) {
                        e.accepted = true;
                        return;
                    }
                    if (e.key === Qt.Key_Delete && pill.dictationOpen) {
                        pill.dictationDelete();
                        e.accepted = true;
                        return;
                    }
                    if (e.key === Qt.Key_Delete && pill.vocabOpen) {
                        pill.vocabDelete();
                        e.accepted = true;
                        return;
                    }
                    if (e.key !== Qt.Key_Return && e.key !== Qt.Key_Enter && e.key !== Qt.Key_Space)
                        return;
                    if (pill.wallpaperOpen) {
                        if (!e.isAutoRepeat)
                            pill.wallpaperActivate();
                        e.accepted = true;
                    } else if (pill.powerOpen) {
                        if (!e.isAutoRepeat)
                            pill.powerPress();
                        e.accepted = true;
                    } else if (pill.sysmonOpen && !e.isAutoRepeat && pill.sysmonActivate()) {
                        e.accepted = true;
                    } else if (pill.vocabOpen && pill.vocabEnter()) {
                        e.accepted = true;
                    } else if (pill.settingsLike) {
                        if (!e.isAutoRepeat)
                            pill.settingsActivate();
                        e.accepted = true;
                    } else if (pill.keybindsOpen && !pill.keybindsListening) {
                        if (!e.isAutoRepeat)
                            pill.keybindsActivate();
                        e.accepted = true;
                    }
                }
                Keys.onReleased: e => {
                    if (e.isAutoRepeat)
                        return;
                    if (e.key === Qt.Key_Delete && (pill.awakeOpen || pill.dictationOpen || pill.vocabOpen)) {
                        if (pill.awakeOpen)
                            pill.awakeDeleteRelease();
                        else
                            pill.wipeRelease();
                        e.accepted = true;
                        return;
                    }
                    if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space || (e.text.length === 1 && "wlsruWLSRU".indexOf(e.text) >= 0)) && pill.powerOpen) {
                        pill.powerRelease();
                        e.accepted = true;
                    }
                }

                Item {
                    id: slot
                    readonly property real pad: 56 * overlay.s
                    readonly property bool swiping: pill.swipeX !== 0 || pill.swipeY !== 0
                    anchors.top: parent.top
                    anchors.topMargin: overlay.topGap - pad
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: pill.width + 2 * pad
                    height: pill.height + 2 * pad

                    Behavior on anchors.topMargin {
                        NumberAnimation {
                            duration: Motion.morph
                            easing.type: Motion.easeMorph
                            easing.bezierCurve: Motion.morphCurve
                        }
                    }

                    layer.enabled: swiping
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: wall
                    }

                    Item {
                        id: wall
                        width: slot.width
                        height: slot.height
                        visible: false
                        layer.enabled: true

                        Rectangle {
                            id: wallRect
                            anchors.fill: parent
                            readonly property bool sideways: pill.swipeX !== 0
                            readonly property bool leftward: pill.swipeX < 0
                            readonly property real edge: slot.pad / (sideways ? slot.width : slot.height)
                            gradient: Gradient {
                                orientation: wallRect.sideways ? Gradient.Horizontal : Gradient.Vertical
                                GradientStop {
                                    position: 0.0
                                    color: wallRect.sideways && !wallRect.leftward ? "white" : "transparent"
                                }
                                GradientStop {
                                    position: wallRect.edge
                                    color: "white"
                                }
                                GradientStop {
                                    position: 1 - wallRect.edge
                                    color: "white"
                                }
                                GradientStop {
                                    position: 1.0
                                    color: wallRect.sideways && wallRect.leftward ? "white" : "transparent"
                                }
                            }
                        }
                    }

                    Pill {
                        id: pill
                        anchors.top: parent.top
                        anchors.topMargin: slot.pad
                        anchors.horizontalCenter: parent.horizontalCenter
                        s: overlay.s
                        screenName: overlay.modelData.name
                        barWindow: overlay
                        surface: overlay.surface
                        forcePinned: root.peekMon === overlay.modelData.name

                        opacity: overlay.pillHidden ? 0 : pill.swipeFade
                        Behavior on opacity {
                            enabled: !slot.swiping
                            NumberAnimation {
                                duration: Motion.morph
                                easing.type: Motion.easeMorph
                                easing.bezierCurve: Motion.morphCurve
                            }
                        }
                        transform: [
                            Translate {
                                x: pill.swipeX
                                y: pill.swipeY
                            },
                            Translate {
                                y: overlay.pillHidden ? -(pill.height + overlay.topGap) : 0
                                Behavior on y {
                                    NumberAnimation {
                                        duration: Motion.morph
                                        easing.type: Motion.easeMorph
                                        easing.bezierCurve: Motion.morphCurve
                                    }
                                }
                            }
                        ]

                        onRequestSurface: name => root.toggleSurface(overlay.modelData.name, name)
                        onRequestClose: root.close()
                    }
                }
            }

            onSurfaceOpenChanged: if (surfaceOpen)
                focusScope.forceActiveFocus()

            Connections {
                target: pill
                function onQuickChoosingChanged() {
                    if (pill.quickChoosing)
                        focusScope.forceActiveFocus();
                }
                function onWallpaperSearchingChanged() {
                    if (!pill.wallpaperSearching && overlay.surfaceOpen)
                        focusScope.forceActiveFocus();
                }
                function onVocabTypingChanged() {
                    if (!pill.vocabTyping && overlay.surfaceOpen)
                        focusScope.forceActiveFocus();
                }
                function onKeybindsListeningChanged() {
                    if (!pill.keybindsListening && overlay.surfaceOpen)
                        focusScope.forceActiveFocus();
                }
            }
        }
    }
}
