pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "lib/luaSettings.js" as LuaSettings
import "Singletons"

/**
 * 操 INPUT sub-surface: edits the pointer, keyboard and cursor settings that live
 * in the Hyprland Lua modules, writing each change straight back to its source so
 * the choice survives a restart. Pointer and keyboard preferences rewrite input.lua
 * and reload Hyprland. Cleaning Mode applies only to the current session.
 * Cursor size and theme apply live through `hyprctl setcursor` with no reload,
 * and persist by rewriting the XCURSOR/HYPRCURSOR env lines and the autostart
 * setcursor call. The theme list is scanned from the installed icon themes that
 * carry a `cursors/` folder. Reached from the settings index; morphs back on the
 * back chevron.
 */
SettingsSurface {
    id: root

    implicitHeight: content.implicitHeight

    /**
     * Row registry; scrub rows expose a bump that steps their ScrubValue one
     * increment. The layout row's vals gain the current layout at the end when it
     * is not in the curated list, so an exotic layout shows as-is and a click
     * wraps around to the start of the list.
     */
    rows: [
        {
            item: sensRow,
            kind: "scrub",
            bump: function (d) {
                sensScrub.bump(d);
            }
        },
        {
            item: accelRow,
            kind: "seg",
            vals: ["flat", "adaptive"],
            get: function () {
                return root.accelProfile;
            },
            set: function (v) {
                root.accelProfile = v;
                root.writeInputField("accel_profile", "\"" + v + "\"");
            }
        },
        {
            item: layoutRow,
            kind: "seg",
            vals: root.kbLayoutVals,
            get: function () {
                return root.kbLayout;
            },
            set: function (v) {
                root.setKbLayout(v);
            }
        },
        {
            item: rateRow,
            kind: "scrub",
            bump: function (d) {
                rateScrub.bump(d);
            }
        },
        {
            item: delayRow,
            kind: "scrub",
            bump: function (d) {
                delayScrub.bump(d);
            }
        },
        {
            item: numlockRow,
            kind: "toggle",
            get: function () {
                return root.numlockOn;
            },
            set: function (v) {
                root.numlockOn = v;
                root.writeInputField("numlock_by_default", v ? "true" : "false");
            }
        },
        {
            item: sizeRow,
            kind: "scrub",
            bump: function (d) {
                sizeScrub.bump(d);
            }
        },
        {
            item: themeRow,
            kind: "toggle",
            get: function () {
                return root.themeOpen;
            },
            set: function (v) {
                root.themeOpen = v;
            }
        }
    ]

    property string note: ""

    readonly property string inputPath: Quickshell.env("HOME") + "/.config/hypr/modules/input.lua"
    readonly property string envPath: Quickshell.env("HOME") + "/.config/hypr/modules/env.lua"
    readonly property string autostartPath: Quickshell.env("HOME") + "/.config/hypr/modules/autostart.lua"

    property real sensitivity: 0
    property string accelProfile: "flat"
    property string kbLayout: "de"
    property int repeatRate: 25
    property int repeatDelay: 600
    property bool numlockOn: false
    property int cursorSize: 24
    property string cursorTheme: "Bibata-Modern-Ice"
    property var cursorThemes: []
    property bool themeOpen: false

    property string inputText: ""
    property string envText: ""
    property string autostartText: ""

    /** Per-field values captured on each open; the ScrubValue undo glyphs revert to these. */
    property var base: ({})

    readonly property var accelOptions: [
        {
            label: "Flat",
            value: "flat"
        },
        {
            label: "Adaptive",
            value: "adaptive"
        }
    ]

    readonly property var kbLayouts: ["de", "us", "gb", "fr", "es", "it", "tr"]
    readonly property var kbLayoutVals: kbLayouts.indexOf(kbLayout) >= 0 ? kbLayouts : kbLayouts.concat([kbLayout])

    onActiveChanged: {
        if (active) {
            inputFile.reload();
            envFile.reload();
            autostartFile.reload();
            seed();
            themeProc.running = true;
        } else {
            themeOpen = false;
            focusRowItem = null;
            kbIndex = -1;
        }
    }

    /**
     * Seeds every control from the live source files. Numbers fall back to the
     * defaults when a field is missing so a partially hand-edited config never
     * leaves a control blank.
     */
    function seed() {
        root.inputText = inputFile.text();
        root.envText = envFile.text();
        root.autostartText = autostartFile.text();

        const inp = root.inputText;
        const sens = parseFloat(LuaSettings.getField(inp, "sensitivity"));
        root.sensitivity = isNaN(sens) ? 0 : sens;
        const ap = LuaSettings.getField(inp, "accel_profile");
        root.accelProfile = ap.length > 0 ? ap : "flat";
        const kl = LuaSettings.getField(inp, "kb_layout");
        root.kbLayout = kl.length > 0 ? kl : "de";
        const rr = parseInt(LuaSettings.getField(inp, "repeat_rate"), 10);
        root.repeatRate = isNaN(rr) ? 25 : rr;
        const rd = parseInt(LuaSettings.getField(inp, "repeat_delay"), 10);
        root.repeatDelay = isNaN(rd) ? 600 : rd;
        root.numlockOn = LuaSettings.getField(inp, "numlock_by_default") === "true";

        const env = root.envText;
        const cs = parseInt(LuaSettings.getEnv(env, "XCURSOR_SIZE"), 10);
        root.cursorSize = isNaN(cs) ? 24 : cs;
        const ct = LuaSettings.getEnv(env, "XCURSOR_THEME");
        root.cursorTheme = ct.length > 0 ? ct : "Bibata-Modern-Ice";

        root.base = {
            sensitivity: root.sensitivity,
            repeatRate: root.repeatRate,
            repeatDelay: root.repeatDelay,
            cursorSize: root.cursorSize
        };
    }

    /**
     * Rewrites one input.lua field to `literal` (already formatted by the caller)
     * and reloads Hyprland so the change takes effect at once.
     */
    function writeInputField(name, literal) {
        const res = LuaSettings.setField(root.inputText, name, literal);
        if (!res.ok)
            return;
        root.inputText = res.text;
        inputWriter.setText(res.text);
        reloadTimer.restart();
    }

    function setKbLayout(v) {
        root.kbLayout = v;
        root.writeInputField("kb_layout", "\"" + v + "\"");
    }

    /**
     * Applies a cursor theme/size pair live via `hyprctl setcursor`, then persists
     * it by rewriting the XCURSOR/HYPRCURSOR env lines and the autostart setcursor
     * call. No Hyprland reload is needed for the cursor.
     */
    function applyCursor(theme, size) {
        setcursorProc.theme = theme;
        setcursorProc.size = size;
        setcursorProc.running = true;

        let env = root.envText;
        const sizeText = String(size);
        for (const [key, value] of [["XCURSOR_THEME", theme], ["XCURSOR_SIZE", sizeText], ["HYPRCURSOR_SIZE", sizeText]])
            env = LuaSettings.setEnv(env, key, value).text;
        if (env !== root.envText) {
            root.envText = env;
            envWriter.setText(env);
        }

        const auto = LuaSettings.setCursorLine(root.autostartText, theme, size);
        if (auto.ok) {
            root.autostartText = auto.text;
            autostartWriter.setText(auto.text);
        }
    }

    FileView {
        id: inputFile
        path: root.inputPath
        blockLoading: true
        printErrors: false
    }

    FileView {
        id: inputWriter
        path: root.inputPath
        atomicWrites: true
        printErrors: false
    }

    FileView {
        id: envFile
        path: root.envPath
        blockLoading: true
        printErrors: false
    }

    FileView {
        id: envWriter
        path: root.envPath
        atomicWrites: true
        printErrors: false
    }

    FileView {
        id: autostartFile
        path: root.autostartPath
        blockLoading: true
        printErrors: false
    }

    FileView {
        id: autostartWriter
        path: root.autostartPath
        atomicWrites: true
        printErrors: false
    }

    /**
     * Reload is debounced so a scrub drag writes the file per step but reloads
     * Hyprland once, and captured so a failed reload surfaces as the inline note
     * instead of vanishing with a detached process.
     */
    Timer {
        id: reloadTimer
        interval: 250
        repeat: false
        onTriggered: reloadProc.running = true
    }

    Process {
        id: reloadProc
        command: ["sh", "-c", "sleep 0.3; hyprctl reload"]
        onExited: function (exitCode) {
            root.note = exitCode === 0 ? "" : "Hyprland reload failed. The change is saved but not applied.";
        }
    }

    Process {
        id: setcursorProc
        property string theme: ""
        property int size: 24
        command: ["hyprctl", "setcursor", theme, String(size)]
    }

    Process {
        id: themeProc
        command: ["sh", "-c", "{ printf '%s\\n' \"$HOME/.icons\" \"$HOME/.local/share/icons\" /usr/share/icons; printf '%s' \"${XDG_DATA_DIRS:-/usr/local/share:/usr/share}\" | tr ':' '\\n' | sed 's#/*$#/icons#'; } | sort -u | while IFS= read -r d; do [ -d \"$d\" ] || continue; for t in \"$d\"/*/; do [ -d \"$t/cursors\" ] && basename \"$t\"; done; done | sort -u"]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.split("\n").filter(function (l) {
                    return l.trim().length > 0;
                });
                root.cursorThemes = lines;
            }
        }
    }

    component GroupLabel: Text {
        topPadding: 16 * root.s
        bottomPadding: 6 * root.s
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: 8.5 * root.s
        font.weight: Font.Bold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 1.2 * root.s
    }

    /**
     * One settings line. At rest it is an icon + label + control row; hovering or
     * keyboard-focusing the row folds its grey caption open below the label so
     * the tab stays compact by default. The row feeds the surface registry: hover
     * moves the soul seam and a click anywhere on the line drives its control via
     * activateRow.
     */
    /**
     * The Theme row grows when its dropdown opens, so centring the seam on the
     * whole row dropped it into the list. Pin it to the picker's top line.
     */
    amePoint: {
        void root.width;
        void root.height;
        void themePick.implicitHeight;
        if (root.focusRowItem === themeRow)
            return themeRow.mapToItem(root, 4 * root.s, themePick.rowH / 2);
        return root.rowPoint;
    }

    component FieldRow: Item {
        id: frow
        property string label: ""
        property string caption: ""
        property string icon: ""
        property bool showCaption: false
        property var pointerAction: null
        default property alias control: ctrl.data

        readonly property bool focused: root.focusRowItem === frow
        readonly property bool expanded: frow.showCaption || fhover.hovered || frow.focused
        readonly property real rowH: 30 * root.s
        readonly property real capH: 14 * root.s

        width: parent ? parent.width : 0
        height: frow.rowH + (frow.expanded ? frow.capH : 0)
        clip: true
        Behavior on height {
            NumberAnimation {
                duration: Motion.fast
                easing.type: Easing.OutCubic
            }
        }

        HoverHandler {
            id: fhover
            onHoveredChanged: root.reportRowHover(frow, hovered)
        }

        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 3 * root.s
            anchors.bottomMargin: 3 * root.s
            radius: 9 * root.s
            color: (fhover.hovered || frow.focused) ? Theme.frameBg : "transparent"
            Behavior on color {
                ColorAnimation {
                    duration: Motion.fast
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (frow.pointerAction)
                    frow.pointerAction();
                else
                    root.activateRow(frow);
            }
        }

        GlyphIcon {
            id: rowIcon
            anchors.left: parent.left
            anchors.leftMargin: 9 * root.s
            anchors.verticalCenter: parent.verticalCenter
            visible: frow.icon.length > 0
            width: 15 * root.s
            height: 15 * root.s
            name: frow.icon
            color: frow.focused ? Theme.cream : Theme.subtle
            stroke: 1.8
        }

        Column {
            anchors.left: rowIcon.visible ? rowIcon.right : parent.left
            anchors.leftMargin: 9 * root.s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2 * root.s

            Text {
                text: frow.label
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 12.5 * root.s
                font.weight: Font.Medium
            }

            Text {
                visible: frow.expanded && frow.caption.length > 0
                text: frow.caption
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 9 * root.s
                font.weight: Font.Medium
            }
        }

        Item {
            id: ctrl
            anchors.right: parent.right
            anchors.rightMargin: 9 * root.s
            anchors.verticalCenter: parent.verticalCenter
            width: childrenRect.width
            height: childrenRect.height
        }
    }

    Column {
        id: content
        z: 100
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0
        height: root.height + root.mBottom * root.s
        clip: true

        SettingsHeader {
            s: root.s
            glyph: "操"
            title: "INPUT"
            showBack: true
        }

        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 12 * root.s
            anchors.rightMargin: 12 * root.s
            spacing: 0

            GroupLabel {
                text: "Pointer"
            }

            FieldRow {
                id: sensRow
                label: "Sensitivity"
                caption: "Pointer speed offset"
                icon: "mouse"
                ScrubValue {
                    id: sensScrub
                    s: root.s
                    value: root.sensitivity
                    openValue: root.base.sensitivity
                    from: -1
                    to: 1
                    step: 0.1
                    decimals: 1
                    onEdited: v => {
                        root.sensitivity = v;
                        root.writeInputField("sensitivity", String(v));
                    }
                }
            }

            FieldRow {
                id: accelRow
                label: "Acceleration"
                caption: "How pointer speed follows motion"
                icon: "bolt"
                SettingsSeg {
                    s: root.s
                    options: root.accelOptions
                    value: root.accelProfile
                    onPicked: v => {
                        root.accelProfile = v;
                        root.writeInputField("accel_profile", "\"" + v + "\"");
                    }
                }
            }

            GroupLabel {
                text: "Keyboard"
            }

            FieldRow {
                id: layoutRow
                label: "Layout"
                caption: "Click to cycle common layouts"
                icon: "language"

                Rectangle {
                    width: layoutLbl.implicitWidth + 20 * root.s
                    height: 22 * root.s
                    radius: 9 * root.s
                    color: "transparent"
                    border.width: 1
                    border.color: Theme.hairSoft

                    Text {
                        id: layoutLbl
                        anchors.centerIn: parent
                        text: root.kbLayout
                        color: Theme.cream
                        font.family: Theme.font
                        font.pixelSize: 11 * root.s
                        font.weight: Font.DemiBold
                    }
                }
            }

            FieldRow {
                id: rateRow
                label: "Repeat rate"
                caption: "Key repeats per second when held"
                icon: "keyboard"
                ScrubValue {
                    id: rateScrub
                    s: root.s
                    value: root.repeatRate
                    openValue: root.base.repeatRate
                    from: 10
                    to: 80
                    step: 1
                    unit: "Hz"
                    onEdited: v => {
                        root.repeatRate = v;
                        root.writeInputField("repeat_rate", String(v));
                    }
                }
            }

            FieldRow {
                id: delayRow
                label: "Repeat delay"
                caption: "Hold time before a key repeats"
                icon: "stopwatch"
                ScrubValue {
                    id: delayScrub
                    s: root.s
                    value: root.repeatDelay
                    openValue: root.base.repeatDelay
                    from: 150
                    to: 1000
                    step: 25
                    unit: "ms"
                    onEdited: v => {
                        root.repeatDelay = v;
                        root.writeInputField("repeat_delay", String(v));
                    }
                }
            }

            FieldRow {
                id: numlockRow
                label: "Numlock"
                caption: "Numlock on at startup"
                icon: "lock"
                LinkToggle {
                    s: root.s
                    on: root.numlockOn
                    onToggled: {
                        root.numlockOn = !root.numlockOn;
                        root.writeInputField("numlock_by_default", root.numlockOn ? "true" : "false");
                    }
                }
            }

            FieldRow {
                label: "Cleaning Mode"
                caption: "Disables all keyboard keys for cleaning"
                icon: "keyboard"
                showCaption: true
                enabled: !KeyboardCleaning.busy
                pointerAction: () => KeyboardCleaning.toggle()

                LinkToggle {
                    s: root.s
                    on: KeyboardCleaning.active
                    onToggled: KeyboardCleaning.toggle()
                }
            }

            Text {
                width: parent.width
                leftPadding: 9 * root.s
                topPadding: 4 * root.s
                visible: text.length > 0
                text: KeyboardCleaning.error
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 10 * root.s
            }

            GroupLabel {
                text: "Cursor"
            }

            FieldRow {
                id: sizeRow
                label: "Size"
                caption: "Cursor size in pixels"
                icon: "cursor"
                ScrubValue {
                    id: sizeScrub
                    s: root.s
                    value: root.cursorSize
                    openValue: root.base.cursorSize
                    from: 12
                    to: 96
                    step: 4
                    unit: "px"
                    onEdited: v => {
                        root.cursorSize = v;
                        root.applyCursor(root.cursorTheme, v);
                    }
                }
            }

            Item {
                width: 1
                height: 8 * root.s
            }

            /**
             * DisplayPicker draws its own chip and dropdown, so the wrapper only
             * adds what the registry needs: hover for the soul seam and a
             * fall-through click that toggles the picker like the chip does.
             */
            Item {
                id: themeRow
                width: parent ? parent.width : 0
                height: themePick.implicitHeight

                HoverHandler {
                    onHoveredChanged: root.reportRowHover(themeRow, hovered)
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.activateRow(themeRow)
                }

                /** Indented so the "Theme" label clears the soul seam at the row's left edge. */
                DisplayPicker {
                    id: themePick
                    x: 16 * root.s
                    width: themeRow.width - 16 * root.s
                    s: root.s
                    label: "Theme"
                    options: root.cursorThemes.map(function (t) {
                        return {
                            label: t,
                            value: t
                        };
                    })
                    value: root.cursorTheme
                    open: root.themeOpen
                    onRequestToggle: root.themeOpen = !root.themeOpen
                    onPicked: v => {
                        root.cursorTheme = v;
                        root.themeOpen = false;
                        root.applyCursor(v, root.cursorSize);
                    }
                }
            }

            Text {
                width: parent.width
                topPadding: 8 * root.s
                visible: root.note.length > 0
                text: root.note
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 10 * root.s
                font.weight: Font.Medium
                wrapMode: Text.WordWrap
                lineHeight: 1.25
            }

            Item {
                width: 1
                height: 10 * root.s
            }
        }
    }
}
