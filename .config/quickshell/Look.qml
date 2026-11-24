pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "lib/luaSettings.js" as LuaSettings
import "Singletons"

/**
 * 飾 LOOK sub-surface: edits the window-decoration knobs that live in
 * decoration.lua and writes each change straight back to its source so the choice
 * survives a restart. Window gaps, rounding and border size, the two opacity
 * fields and the blur block all rewrite the Lua and reload Hyprland so the change
 * lands at once. Blur fields are rewritten scoped to the `blur` block, since
 * `enabled` is shared with the sibling `shadow` block. The border colours are
 * sourced from the palette pipeline and never touched here. Reached from the
 * settings index; morphs back on the back chevron.
 */
SettingsSurface {
    id: root

    implicitHeight: content.implicitHeight

    /**
     * Row registry, rebound whenever a group folds or a dependent toggle flips so
     * keyboard navigation never lands on a hidden line. Scrub rows expose a bump
     * that steps their ScrubValue one increment.
     */
    rows: {
        var r = [];
        r.push(root.headEntry(winGrp));
        if (winGrp.open) {
            r.push({
                item: gapsInRow,
                kind: "scrub",
                bump: function (d) {
                    gapsInScrub.bump(d);
                }
            });
            r.push({
                item: gapsOutRow,
                kind: "scrub",
                bump: function (d) {
                    gapsOutScrub.bump(d);
                }
            });
            r.push({
                item: roundRow,
                kind: "scrub",
                bump: function (d) {
                    roundScrub.bump(d);
                }
            });
            r.push({
                item: roundPowRow,
                kind: "scrub",
                bump: function (d) {
                    roundPowScrub.bump(d);
                }
            });
            r.push({
                item: borderRow,
                kind: "scrub",
                bump: function (d) {
                    borderScrub.bump(d);
                }
            });
            r.push({
                item: resizeRow,
                kind: "toggle",
                get: function () {
                    return root.resizeOnBorder;
                },
                set: function (v) {
                    root.resizeOnBorder = v;
                    root.writeDeco("resize_on_border", v ? "true" : "false");
                }
            });
            r.push({
                item: layoutRow,
                kind: "seg",
                vals: ["dwindle", "master"],
                get: function () {
                    return root.layout;
                },
                set: function (v) {
                    root.layout = v;
                    root.writeDeco("layout", "\"" + v + "\"");
                }
            });
        }
        r.push(root.headEntry(nightGrp));
        if (nightGrp.open) {
            r.push({
                item: nlModeRow,
                kind: "seg",
                vals: ["off", "on", "scheduled"],
                get: function () {
                    return Flags.nightLightMode;
                },
                set: function (v) {
                    NightLight.setMode(v);
                }
            });
            if (Flags.nightLightMode !== "off")
                r.push({
                    item: nlTempRow,
                    kind: "scrub",
                    bump: function (d) {
                        nlTempScrub.bump(d);
                    }
                });
            if (Flags.nightLightMode === "scheduled") {
                r.push({
                    item: nlOnRow,
                    kind: "scrub",
                    bump: function (d) {
                        nlOnScrub.bump(d);
                    }
                });
                r.push({
                    item: nlOffRow,
                    kind: "scrub",
                    bump: function (d) {
                        nlOffScrub.bump(d);
                    }
                });
            }
        }
        r.push(root.headEntry(shadowGrp));
        if (shadowGrp.open) {
            r.push({
                item: shEnRow,
                kind: "toggle",
                get: function () {
                    return root.shadowOn;
                },
                set: function (v) {
                    root.shadowOn = v;
                    root.writeShadow("enabled", v ? "true" : "false");
                }
            });
            if (root.shadowOn) {
                r.push({
                    item: shRangeRow,
                    kind: "scrub",
                    bump: function (d) {
                        shRangeScrub.bump(d);
                    }
                });
                r.push({
                    item: shPowRow,
                    kind: "scrub",
                    bump: function (d) {
                        shPowScrub.bump(d);
                    }
                });
            }
        }
        r.push(root.headEntry(blurGrp));
        if (blurGrp.open) {
            r.push({
                item: blEnRow,
                kind: "toggle",
                get: function () {
                    return root.blurOn;
                },
                set: function (v) {
                    root.blurOn = v;
                    root.writeBlur("enabled", v ? "true" : "false");
                }
            });
            if (root.blurOn) {
                r.push({
                    item: blSizeRow,
                    kind: "scrub",
                    bump: function (d) {
                        blSizeScrub.bump(d);
                    }
                });
                r.push({
                    item: blPassRow,
                    kind: "scrub",
                    bump: function (d) {
                        blPassScrub.bump(d);
                    }
                });
                r.push({
                    item: blVibRow,
                    kind: "scrub",
                    bump: function (d) {
                        blVibScrub.bump(d);
                    }
                });
                r.push({
                    item: blNoiseRow,
                    kind: "scrub",
                    bump: function (d) {
                        blNoiseScrub.bump(d);
                    }
                });
            }
        }
        r.push(root.headEntry(opGrp));
        if (opGrp.open) {
            r.push({
                item: opActRow,
                kind: "scrub",
                bump: function (d) {
                    opActScrub.bump(d);
                }
            });
            r.push({
                item: opInactRow,
                kind: "scrub",
                bump: function (d) {
                    opInactScrub.bump(d);
                }
            });
        }
        r.push(root.headEntry(pillGrp));
        if (pillGrp.open) {
            r.push({
                item: pillGapRow,
                kind: "scrub",
                bump: function (d) {
                    pillGapScrub.bump(d);
                }
            });
            r.push({
                item: appGapRow,
                kind: "scrub",
                bump: function (d) {
                    appGapScrub.bump(d);
                }
            });
            r.push({
                item: pillOpRow,
                kind: "scrub",
                bump: function (d) {
                    pillOpScrub.bump(d);
                }
            });
            r.push({
                item: pillBlurRow,
                kind: "toggle",
                get: function () {
                    return Flags.pillBlur;
                },
                set: function (v) {
                    Flags.pillBlur = v;
                    root.applyPillBlur(v);
                }
            });
            r.push({
                item: pillHRow,
                kind: "scrub",
                bump: function (d) {
                    pillHScrub.bump(d);
                }
            });
            r.push({
                item: pillRoundRow,
                kind: "scrub",
                bump: function (d) {
                    pillRoundScrub.bump(d);
                }
            });
            r.push({
                item: idleWRow,
                kind: "scrub",
                bump: function (d) {
                    idleWScrub.bump(d);
                }
            });
            r.push({
                item: shadowPillRow,
                kind: "toggle",
                get: function () {
                    return Flags.pillShadow;
                },
                set: function (v) {
                    Flags.pillShadow = v;
                }
            });
            r.push({
                item: borderPillRow,
                kind: "toggle",
                get: function () {
                    return Flags.pillBorder;
                },
                set: function (v) {
                    Flags.pillBorder = v;
                }
            });
            r.push({
                item: sheenRow,
                kind: "toggle",
                get: function () {
                    return Flags.pillSheen;
                },
                set: function (v) {
                    Flags.pillSheen = v;
                }
            });
            r.push({
                item: springRow,
                kind: "seg",
                vals: ["soft", "snappy"],
                get: function () {
                    return Flags.springFeel;
                },
                set: function (v) {
                    Flags.springFeel = v;
                }
            });
            r.push({
                item: expandRow,
                kind: "seg",
                vals: ["hover", "click"],
                get: function () {
                    return Flags.expandMode;
                },
                set: function (v) {
                    Flags.expandMode = v;
                }
            });
            r.push({
                item: openDelayRow,
                kind: "scrub",
                bump: function (d) {
                    openDelayScrub.bump(d);
                }
            });
            r.push({
                item: closeDelayRow,
                kind: "scrub",
                bump: function (d) {
                    closeDelayScrub.bump(d);
                }
            });
        }
        r.push(root.headEntry(wsGrp));
        if (wsGrp.open) {
            r.push({
                item: wsStyleRow,
                kind: "seg",
                vals: ["dots", "numbers", "names"],
                get: function () {
                    return Flags.wsStyle;
                },
                set: function (v) {
                    Flags.wsStyle = v;
                }
            });
            r.push({
                item: wsShowRow,
                kind: "seg",
                vals: ["occupied", "all"],
                get: function () {
                    return Flags.wsShow;
                },
                set: function (v) {
                    Flags.wsShow = v;
                }
            });
            r.push({
                item: wsScrollRow,
                kind: "toggle",
                get: function () {
                    return Flags.wsScroll;
                },
                set: function (v) {
                    Flags.wsScroll = v;
                }
            });
        }
        return r;
    }

    property string note: ""

    readonly property string decoPath: Quickshell.env("HOME") + "/.config/hypr/modules/decoration.lua"
    readonly property string pillBlurRule: 'hl.layer_rule({ name = "pill-blur", match = { namespace = "pill" }, blur = true, ignore_alpha = 0.5 })\n'

    property int gapsIn: 6
    property int gapsOut: 12
    property int rounding: 12
    property int roundingPower: 4
    property int borderSize: 2
    property bool resizeOnBorder: true
    property string layout: "dwindle"
    property bool blurOn: true
    property int blurSize: 8
    property int blurPasses: 3
    property real blurVibrancy: 0.17
    property real blurNoise: 0.01
    property bool shadowOn: true
    property int shadowRange: 12
    property int shadowRenderPower: 3
    property real activeOpacity: 1.0
    property real inactiveOpacity: 1.0

    readonly property var layoutOptions: [
        {
            label: "Dwindle",
            value: "dwindle"
        },
        {
            label: "Master",
            value: "master"
        }
    ]

    property string decoText: ""

    /** Per-field values captured on each open; the ScrubValue undo glyphs revert to these. */
    property var base: ({})

    onActiveChanged: {
        if (active) {
            decoFile.reload();
            seed();
        } else {
            focusRowItem = null;
            kbIndex = -1;
        }
    }

    /**
     * Seeds every control from the live decoration.lua. Numbers fall back to the
     * shipped defaults when a field is missing so a partially hand-edited config
     * never leaves a control blank. Blur fields read from the `blur` block so a
     * field name shared with the `shadow` block resolves correctly.
     */
    function seed() {
        root.decoText = decoFile.text();
        var t = root.decoText;

        var gi = parseInt(LuaSettings.getField(t, "gaps_in"), 10);
        root.gapsIn = isNaN(gi) ? 6 : gi;
        var go = parseInt(LuaSettings.getField(t, "gaps_out"), 10);
        root.gapsOut = isNaN(go) ? 12 : go;
        var rd = parseInt(LuaSettings.getField(t, "rounding"), 10);
        root.rounding = isNaN(rd) ? 12 : rd;
        var rp = parseInt(LuaSettings.getField(t, "rounding_power"), 10);
        root.roundingPower = isNaN(rp) ? 4 : rp;
        var bs = parseInt(LuaSettings.getField(t, "border_size"), 10);
        root.borderSize = isNaN(bs) ? 2 : bs;
        root.resizeOnBorder = LuaSettings.getField(t, "resize_on_border") === "true";
        var lo = LuaSettings.getField(t, "layout");
        root.layout = lo.length > 0 ? lo : "dwindle";

        root.blurOn = LuaSettings.getBlockField(t, "blur", "enabled") === "true";
        var bz = parseInt(LuaSettings.getBlockField(t, "blur", "size"), 10);
        root.blurSize = isNaN(bz) ? 8 : bz;
        var bp = parseInt(LuaSettings.getBlockField(t, "blur", "passes"), 10);
        root.blurPasses = isNaN(bp) ? 3 : bp;
        var vb = parseFloat(LuaSettings.getBlockField(t, "blur", "vibrancy"));
        root.blurVibrancy = isNaN(vb) ? 0.17 : vb;
        var nz = parseFloat(LuaSettings.getBlockField(t, "blur", "noise"));
        root.blurNoise = isNaN(nz) ? 0.01 : nz;

        root.shadowOn = LuaSettings.getBlockField(t, "shadow", "enabled") === "true";
        var sr = parseInt(LuaSettings.getBlockField(t, "shadow", "range"), 10);
        root.shadowRange = isNaN(sr) ? 12 : sr;
        var sp = parseInt(LuaSettings.getBlockField(t, "shadow", "render_power"), 10);
        root.shadowRenderPower = isNaN(sp) ? 3 : sp;

        var ao = parseFloat(LuaSettings.getField(t, "active_opacity"));
        root.activeOpacity = isNaN(ao) ? 1.0 : ao;
        var io = parseFloat(LuaSettings.getField(t, "inactive_opacity"));
        root.inactiveOpacity = isNaN(io) ? 1.0 : io;

        Flags.pillBlur = LuaSettings.hasNamedRule(t, "pill-blur");

        root.base = {
            gapsIn: root.gapsIn,
            gapsOut: root.gapsOut,
            rounding: root.rounding,
            roundingPower: root.roundingPower,
            borderSize: root.borderSize,
            blurSize: root.blurSize,
            blurPasses: root.blurPasses,
            blurVibrancy: root.blurVibrancy,
            blurNoise: root.blurNoise,
            shadowRange: root.shadowRange,
            shadowRenderPower: root.shadowRenderPower,
            activeOpacity: root.activeOpacity,
            inactiveOpacity: root.inactiveOpacity,
            pillOpacity: Flags.pillOpacity,
            pillHeight: Flags.pillHeight,
            pillRounding: Flags.pillRounding,
            idleWidth: Flags.idleWidth,
            openDelay: Flags.openDelay,
            closeDelay: Flags.closeDelay,
            topGap: Flags.topGap,
            appGap: Flags.appGap,
            nlTemp: Flags.nightLightTemp,
            nlOnMin: Flags.nightLightOnMin,
            nlOffMin: Flags.nightLightOffMin
        };
    }

    /** Minutes-since-midnight rendered as HH:MM for the schedule scrubs. */
    function fmtClock(v) {
        var h = Math.floor(v / 60);
        var m = v % 60;
        return h + ":" + (m < 10 ? "0" + m : m);
    }

    readonly property var nightModeOptions: [
        {
            label: "Off",
            value: "off"
        },
        {
            label: "On",
            value: "on"
        },
        {
            label: "Scheduled",
            value: "scheduled"
        }
    ]

    /**
     * Rewrites one top-level decoration.lua field to `literal` (already formatted
     * by the caller) and reloads Hyprland so the change takes effect at once.
     */
    function writeDeco(name, literal) {
        var res = LuaSettings.setField(root.decoText, name, literal);
        if (!res.ok)
            return;
        root.decoText = res.text;
        decoWriter.setText(res.text);
        reloadTimer.restart();
    }

    /**
     * Same as writeDeco, but for the two opacity fields. A plain reload re-reads
     * the file yet only animates windows on their next focus change, so a window
     * that was inactive when the value changed keeps its stale alpha. Pushing the
     * value through hl.config hits Hyprland's REFRESH_WINDOW_STATES path, which
     * recomputes every existing window's active/inactive alpha at once. Sends both
     * fields so lowering one then restoring the other never leaves a window stuck,
     * and the push fires even when the value lands back on 1.0.
     */
    function writeOpacity(name, literal) {
        writeDeco(name, literal);
        opacityRefresh.command = ["hyprctl", "eval", "hl.config({ decoration = { active_opacity = " + root.activeOpacity.toFixed(2) + ", inactive_opacity = " + root.inactiveOpacity.toFixed(2) + " } })"];
        opacityRefresh.running = true;
    }

    /**
     * Rewrites one field inside the `blur` block to `literal` and reloads
     * Hyprland. Scoping to the block keeps `enabled` from hitting the sibling
     * `shadow` block's `enabled` first.
     */
    function writeBlur(name, literal) {
        var res = LuaSettings.setBlockField(root.decoText, "blur", name, literal);
        if (!res.ok)
            return;
        root.decoText = res.text;
        decoWriter.setText(res.text);
        reloadTimer.restart();
    }

    /**
     * Rewrites one field inside the `shadow` block to `literal` and reloads
     * Hyprland. Scoped to the block so `enabled` lands on shadow, not the sibling
     * `blur` block.
     */
    function writeShadow(name, literal) {
        var res = LuaSettings.setBlockField(root.decoText, "shadow", name, literal);
        if (!res.ok)
            return;
        root.decoText = res.text;
        decoWriter.setText(res.text);
        reloadTimer.restart();
    }

    /**
     * Adds or removes the pill-blur layer_rule in decoration.lua and reloads
     * Hyprland so the frosted-glass effect behind the pill turns on or off at
     * once. The rule lives in the Lua source (the live config parser rejects a
     * runtime `layerrule` keyword), so it has to be written, not pushed.
     */
    function applyPillBlur(on) {
        var t = root.decoText;
        var res;
        if (on) {
            if (LuaSettings.hasNamedRule(t, "pill-blur"))
                return;
            res = LuaSettings.addNamedRule(t, root.pillBlurRule);
        } else {
            res = LuaSettings.removeNamedRule(t, "pill-blur");
        }
        if (!res.ok)
            return;
        root.decoText = res.text;
        decoWriter.setText(res.text);
        reloadTimer.restart();
    }

    FileView {
        id: decoFile
        path: root.decoPath
        blockLoading: true
        printErrors: false
    }

    FileView {
        id: decoWriter
        path: root.decoPath
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
        id: opacityRefresh
        command: []
    }

    /**
     * Seam placement for this page: a fixed gap left of the focused line's name
     * text (it used to sit on the text). A row centres it on its highlight box;
     * a heading, which has no box, on its text. Rows and headings expose
     * `seamTarget`; text starts at `textInset` to leave room.
     */
    readonly property real textInset: 16 * root.s
    amePoint: {
        void root.width;
        void root.height;
        var it = root.focusRowItem;
        if (!it || !it.seamTarget)
            return root.rowPoint;
        void it.height;
        var t = it.seamTarget;
        var x = t.mapToItem(root, (t.leftPadding || 0) - 7 * root.s, 0).x;
        var y = it.seamOnText ? t.mapToItem(root, 0, (t.topPadding || 0) + t.contentHeight / 2).y : it.mapToItem(root, 0, it.height / 2).y;
        return Qt.point(x, y);
    }

    component GroupLabel: Text {
        leftPadding: root.textInset
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
     * Collapsible settings group: a tappable header (the group label plus a
     * chevron) over a body of rows that animates between zero and its content
     * height, so a long tab shows only the group headers until one is opened.
     * `open` is the initial state; tapping the header toggles it.
     */
    /**
     * One group open at a time, so the page never grows past the screen (several
     * open groups used to push the pill off the bottom with no way to scroll).
     */
    property string openGroup: "Window"

    /** Keyboard entry for a group heading: Enter folds it open or shut. */
    function headEntry(g) {
        return {
            item: g.header,
            kind: "action",
            run: function () {
                g.toggle();
            }
        };
    }

    component Group: Column {
        id: grp
        property string title: ""
        readonly property bool open: root.openGroup === grp.title
        readonly property alias header: hdr
        default property alias rows: body.data

        function toggle() {
            root.openGroup = grp.open ? "" : grp.title;
        }

        width: parent ? parent.width : 0
        spacing: 0

        Item {
            id: hdr
            readonly property Item seamTarget: gl
            readonly property bool seamOnText: true
            width: parent.width
            height: gl.implicitHeight

            HoverHandler {
                onHoveredChanged: root.reportRowHover(hdr, hovered)
            }

            GroupLabel {
                id: gl
                text: grp.title
            }

            GlyphIcon {
                anchors.right: parent.right
                anchors.verticalCenter: gl.verticalCenter
                width: 15 * root.s
                height: 15 * root.s
                name: "chevron-down"
                color: root.focusRowItem === hdr ? Theme.cream : Theme.faint
                stroke: 2.0
                rotation: grp.open ? 0 : -90
                Behavior on rotation {
                    NumberAnimation {
                        duration: Motion.fast
                        easing.type: Easing.OutCubic
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: grp.toggle()
            }
        }

        Item {
            width: parent.width
            height: grp.open ? body.implicitHeight : 0
            clip: true
            Behavior on height {
                NumberAnimation {
                    duration: Motion.fast
                    easing.type: Easing.OutCubic
                }
            }

            Column {
                id: body
                width: parent.width
            }
        }
    }

    /**
     * One settings line. At rest it is a label + control row; hovering or
     * keyboard-focusing the row folds its grey caption open below the label so a
     * long tab stays compact by default. `collapsed` drops the whole row to zero
     * height with the same height animation, used by the blur and shadow rows that
     * depend on a toggle. The row feeds the surface registry: hover moves the soul
     * seam and a click anywhere on the line drives its control via activateRow.
     */
    component FieldRow: Item {
        id: frow
        property string label: ""
        property string caption: ""
        property bool collapsed: false
        default property alias control: ctrl.data

        readonly property bool focused: root.focusRowItem === frow
        readonly property Item seamTarget: lbl
        readonly property bool expanded: !frow.collapsed && (fhover.hovered || frow.focused)
        readonly property real rowH: 30 * root.s
        readonly property real capH: 14 * root.s

        width: parent ? parent.width : 0
        height: frow.collapsed ? 0 : (frow.rowH + (frow.expanded ? frow.capH : 0))
        clip: true
        Behavior on height {
            NumberAnimation {
                duration: Motion.fast
                easing.type: Easing.OutCubic
            }
        }

        HoverHandler {
            id: fhover
            onHoveredChanged: if (!frow.collapsed)
                root.reportRowHover(frow, hovered)
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
            onClicked: root.activateRow(frow)
        }

        Column {
            anchors.left: parent.left
            anchors.leftMargin: root.textInset
            anchors.right: ctrl.left
            anchors.rightMargin: 12 * root.s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2 * root.s

            Text {
                id: lbl
                width: parent.width
                elide: Text.ElideRight
                text: frow.label
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 12.5 * root.s
                font.weight: Font.Medium
            }

            Text {
                width: parent.width
                elide: Text.ElideRight
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
            glyph: "飾"
            title: "LOOK"
            showBack: true
        }

        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 12 * root.s
            anchors.rightMargin: 12 * root.s
            spacing: 0

            Group {
                id: winGrp
                title: "Window"

                FieldRow {
                    id: gapsInRow
                    label: "Gaps inner"
                    caption: "Space between tiled windows"
                    ScrubValue {
                        id: gapsInScrub
                        s: root.s
                        value: root.gapsIn
                        openValue: root.base.gapsIn
                        from: 0
                        to: 40
                        step: 1
                        unit: "px"
                        onEdited: v => {
                            root.gapsIn = v;
                            root.writeDeco("gaps_in", String(v));
                        }
                    }
                }

                FieldRow {
                    id: gapsOutRow
                    label: "Gaps outer"
                    caption: "Space to the screen edge"
                    ScrubValue {
                        id: gapsOutScrub
                        s: root.s
                        value: root.gapsOut
                        openValue: root.base.gapsOut
                        from: 0
                        to: 60
                        step: 1
                        unit: "px"
                        onEdited: v => {
                            root.gapsOut = v;
                            root.writeDeco("gaps_out", String(v));
                        }
                    }
                }

                FieldRow {
                    id: roundRow
                    label: "Rounding"
                    caption: "Corner radius in pixels"
                    ScrubValue {
                        id: roundScrub
                        s: root.s
                        value: root.rounding
                        openValue: root.base.rounding
                        from: 0
                        to: 30
                        step: 1
                        unit: "px"
                        onEdited: v => {
                            root.rounding = v;
                            root.writeDeco("rounding", String(v));
                        }
                    }
                }

                FieldRow {
                    id: roundPowRow
                    label: "Rounding power"
                    caption: "Higher bends corners to a squircle"
                    ScrubValue {
                        id: roundPowScrub
                        s: root.s
                        value: root.roundingPower
                        openValue: root.base.roundingPower
                        from: 1
                        to: 10
                        step: 1
                        onEdited: v => {
                            root.roundingPower = v;
                            root.writeDeco("rounding_power", String(v));
                        }
                    }
                }

                FieldRow {
                    id: borderRow
                    label: "Border size"
                    caption: "Window outline thickness"
                    ScrubValue {
                        id: borderScrub
                        s: root.s
                        value: root.borderSize
                        openValue: root.base.borderSize
                        from: 0
                        to: 8
                        step: 1
                        unit: "px"
                        onEdited: v => {
                            root.borderSize = v;
                            root.writeDeco("border_size", String(v));
                        }
                    }
                }

                FieldRow {
                    id: resizeRow
                    label: "Resize on border"
                    caption: "Drag a window edge to resize"
                    LinkToggle {
                        s: root.s
                        on: root.resizeOnBorder
                        onToggled: {
                            root.resizeOnBorder = !root.resizeOnBorder;
                            root.writeDeco("resize_on_border", root.resizeOnBorder ? "true" : "false");
                        }
                    }
                }

                FieldRow {
                    id: layoutRow
                    label: "Layout"
                    caption: "Tiling layout for new windows"
                    SettingsSeg {
                        s: root.s
                        options: root.layoutOptions
                        value: root.layout
                        onPicked: v => {
                            root.layout = v;
                            root.writeDeco("layout", "\"" + v + "\"");
                        }
                    }
                }
            }

            Group {
                id: nightGrp
                title: "Night light"

                FieldRow {
                    id: nlModeRow
                    label: "Mode"
                    caption: "Off, always warm, or auto by time"
                    SettingsSeg {
                        s: root.s
                        options: root.nightModeOptions
                        value: Flags.nightLightMode
                        onPicked: v => NightLight.setMode(v)
                    }
                }

                FieldRow {
                    id: nlTempRow
                    label: "Temperature"
                    caption: "Lower is warmer"
                    collapsed: Flags.nightLightMode === "off"
                    ScrubValue {
                        id: nlTempScrub
                        s: root.s
                        value: Flags.nightLightTemp
                        openValue: root.base.nlTemp
                        from: 2200
                        to: 6000
                        step: 100
                        unit: "K"
                        onEdited: v => NightLight.setTemp(v)
                    }
                }

                FieldRow {
                    id: nlOnRow
                    label: "On at"
                    caption: "Warm tint starts"
                    collapsed: Flags.nightLightMode !== "scheduled"
                    ScrubValue {
                        id: nlOnScrub
                        s: root.s
                        value: Flags.nightLightOnMin
                        openValue: root.base.nlOnMin
                        from: 0
                        to: 1425
                        step: 15
                        fmt: root.fmtClock
                        onEdited: v => NightLight.setOnMin(v)
                    }
                }

                FieldRow {
                    id: nlOffRow
                    label: "Off at"
                    caption: "Back to neutral"
                    collapsed: Flags.nightLightMode !== "scheduled"
                    ScrubValue {
                        id: nlOffScrub
                        s: root.s
                        value: Flags.nightLightOffMin
                        openValue: root.base.nlOffMin
                        from: 0
                        to: 1425
                        step: 15
                        fmt: root.fmtClock
                        onEdited: v => NightLight.setOffMin(v)
                    }
                }
            }

            Group {
                id: shadowGrp
                title: "Shadow"

                FieldRow {
                    id: shEnRow
                    label: "Enabled"
                    caption: "Drop shadow under windows"
                    LinkToggle {
                        s: root.s
                        on: root.shadowOn
                        onToggled: {
                            root.shadowOn = !root.shadowOn;
                            root.writeShadow("enabled", root.shadowOn ? "true" : "false");
                        }
                    }
                }

                FieldRow {
                    id: shRangeRow
                    label: "Range"
                    caption: "How far the shadow spreads"
                    collapsed: !root.shadowOn
                    ScrubValue {
                        id: shRangeScrub
                        s: root.s
                        value: root.shadowRange
                        openValue: root.base.shadowRange
                        from: 0
                        to: 50
                        step: 1
                        unit: "px"
                        onEdited: v => {
                            root.shadowRange = v;
                            root.writeShadow("range", String(v));
                        }
                    }
                }

                FieldRow {
                    id: shPowRow
                    label: "Render power"
                    caption: "Shadow falloff sharpness"
                    collapsed: !root.shadowOn
                    ScrubValue {
                        id: shPowScrub
                        s: root.s
                        value: root.shadowRenderPower
                        openValue: root.base.shadowRenderPower
                        from: 1
                        to: 4
                        step: 1
                        onEdited: v => {
                            root.shadowRenderPower = v;
                            root.writeShadow("render_power", String(v));
                        }
                    }
                }
            }

            Group {
                id: blurGrp
                title: "Blur"

                FieldRow {
                    id: blEnRow
                    label: "Enabled"
                    caption: "Blur behind transparent windows"
                    LinkToggle {
                        s: root.s
                        on: root.blurOn
                        onToggled: {
                            root.blurOn = !root.blurOn;
                            root.writeBlur("enabled", root.blurOn ? "true" : "false");
                        }
                    }
                }

                FieldRow {
                    id: blSizeRow
                    label: "Strength"
                    caption: "Blur radius"
                    collapsed: !root.blurOn
                    ScrubValue {
                        id: blSizeScrub
                        s: root.s
                        value: root.blurSize
                        openValue: root.base.blurSize
                        from: 1
                        to: 20
                        step: 1
                        unit: "px"
                        onEdited: v => {
                            root.blurSize = v;
                            root.writeBlur("size", String(v));
                        }
                    }
                }

                FieldRow {
                    id: blPassRow
                    label: "Passes"
                    caption: "More passes, smoother blur"
                    collapsed: !root.blurOn
                    ScrubValue {
                        id: blPassScrub
                        s: root.s
                        value: root.blurPasses
                        openValue: root.base.blurPasses
                        from: 1
                        to: 5
                        step: 1
                        onEdited: v => {
                            root.blurPasses = v;
                            root.writeBlur("passes", String(v));
                        }
                    }
                }

                FieldRow {
                    id: blVibRow
                    label: "Vibrancy"
                    caption: "Color saturation behind the blur"
                    collapsed: !root.blurOn
                    ScrubValue {
                        id: blVibScrub
                        s: root.s
                        value: root.blurVibrancy
                        openValue: root.base.blurVibrancy
                        from: 0
                        to: 1
                        step: 0.01
                        decimals: 2
                        onEdited: v => {
                            root.blurVibrancy = v;
                            root.writeBlur("vibrancy", v.toFixed(2));
                        }
                    }
                }

                FieldRow {
                    id: blNoiseRow
                    label: "Noise"
                    caption: "Grain mixed into the blur"
                    collapsed: !root.blurOn
                    ScrubValue {
                        id: blNoiseScrub
                        s: root.s
                        value: root.blurNoise
                        openValue: root.base.blurNoise
                        from: 0
                        to: 0.2
                        step: 0.01
                        decimals: 2
                        onEdited: v => {
                            root.blurNoise = v;
                            root.writeBlur("noise", v.toFixed(2));
                        }
                    }
                }
            }

            Group {
                id: opGrp
                title: "Opacity"

                FieldRow {
                    id: opActRow
                    label: "Active window"
                    caption: "Focused window transparency"
                    ScrubValue {
                        id: opActScrub
                        s: root.s
                        value: root.activeOpacity
                        openValue: root.base.activeOpacity
                        from: 0.5
                        to: 1.0
                        step: 0.05
                        decimals: 2
                        onEdited: v => {
                            root.activeOpacity = v;
                            root.writeOpacity("active_opacity", v.toFixed(2));
                        }
                    }
                }

                FieldRow {
                    id: opInactRow
                    label: "Inactive window"
                    caption: "Unfocused window transparency"
                    ScrubValue {
                        id: opInactScrub
                        s: root.s
                        value: root.inactiveOpacity
                        openValue: root.base.inactiveOpacity
                        from: 0.5
                        to: 1.0
                        step: 0.05
                        decimals: 2
                        onEdited: v => {
                            root.inactiveOpacity = v;
                            root.writeOpacity("inactive_opacity", v.toFixed(2));
                        }
                    }
                }
            }

            Group {
                id: pillGrp
                title: "Pill"

                FieldRow {
                    id: pillGapRow
                    label: "Pill gap"
                    caption: "Space above the pill. Lower pulls windows up with it."
                    ScrubValue {
                        id: pillGapScrub
                        s: root.s
                        value: Flags.topGap
                        openValue: root.base.topGap
                        from: 0
                        to: 2
                        step: 0.1
                        decimals: 1
                        onEdited: v => Flags.topGap = v
                    }
                }

                FieldRow {
                    id: appGapRow
                    label: "App gap"
                    caption: "Space under the pill. Lower pulls windows up."
                    ScrubValue {
                        id: appGapScrub
                        s: root.s
                        value: Flags.appGap
                        openValue: root.base.appGap
                        from: 0
                        to: 2
                        step: 0.1
                        decimals: 1
                        onEdited: v => Flags.appGap = v
                    }
                }

                FieldRow {
                    id: pillOpRow
                    label: "Pill opacity"
                    caption: "How see-through the pill sits"
                    ScrubValue {
                        id: pillOpScrub
                        s: root.s
                        value: Flags.pillOpacity
                        openValue: root.base.pillOpacity
                        from: 0.55
                        to: 1.0
                        step: 0.05
                        decimals: 2
                        onEdited: v => Flags.pillOpacity = v
                    }
                }

                FieldRow {
                    id: pillBlurRow
                    label: "Pill blur"
                    caption: "Frosts behind the pill. Needs opacity under 100%."
                    LinkToggle {
                        s: root.s
                        on: Flags.pillBlur
                        onToggled: {
                            Flags.pillBlur = !Flags.pillBlur;
                            root.applyPillBlur(Flags.pillBlur);
                        }
                    }
                }

                FieldRow {
                    id: pillHRow
                    label: "Height"
                    caption: "Resting pill height"
                    ScrubValue {
                        id: pillHScrub
                        s: root.s
                        value: Flags.pillHeight
                        openValue: root.base.pillHeight
                        from: 24
                        to: 64
                        step: 1
                        decimals: 0
                        unit: "px"
                        onEdited: v => Flags.pillHeight = v
                    }
                }

                FieldRow {
                    id: pillRoundRow
                    label: "Rounding"
                    caption: "Corner radius, up to fully round"
                    ScrubValue {
                        id: pillRoundScrub
                        s: root.s
                        value: Flags.pillRounding
                        openValue: root.base.pillRounding
                        from: 0
                        to: 32
                        step: 1
                        decimals: 0
                        unit: "px"
                        onEdited: v => Flags.pillRounding = v
                    }
                }

                FieldRow {
                    id: idleWRow
                    label: "Idle width"
                    caption: "Narrowest the resting pill gets"
                    ScrubValue {
                        id: idleWScrub
                        s: root.s
                        value: Flags.idleWidth
                        openValue: root.base.idleWidth
                        from: 100
                        to: 320
                        step: 5
                        decimals: 0
                        unit: "px"
                        onEdited: v => Flags.idleWidth = v
                    }
                }

                FieldRow {
                    id: shadowPillRow
                    label: "Shadow"
                    caption: "Drop shadow under the pill"
                    LinkToggle {
                        s: root.s
                        on: Flags.pillShadow
                        onToggled: Flags.pillShadow = !Flags.pillShadow
                    }
                }

                FieldRow {
                    id: borderPillRow
                    label: "Border"
                    caption: "Hairline around the pill"
                    LinkToggle {
                        s: root.s
                        on: Flags.pillBorder
                        onToggled: Flags.pillBorder = !Flags.pillBorder
                    }
                }

                FieldRow {
                    id: sheenRow
                    label: "Sheen"
                    caption: "Highlight along the top edge"
                    LinkToggle {
                        s: root.s
                        on: Flags.pillSheen
                        onToggled: Flags.pillSheen = !Flags.pillSheen
                    }
                }

                FieldRow {
                    id: springRow
                    label: "Spring feel"
                    caption: "How the pill reshapes"
                    SettingsSeg {
                        s: root.s
                        options: [
                            {
                                label: "Soft",
                                value: "soft"
                            },
                            {
                                label: "Snappy",
                                value: "snappy"
                            }
                        ]
                        value: Flags.springFeel
                        onPicked: v => Flags.springFeel = v
                    }
                }

                FieldRow {
                    id: expandRow
                    label: "Expand on"
                    caption: "What opens the icon row"
                    SettingsSeg {
                        s: root.s
                        options: [
                            {
                                label: "Hover",
                                value: "hover"
                            },
                            {
                                label: "Click",
                                value: "click"
                            }
                        ]
                        value: Flags.expandMode
                        onPicked: v => Flags.expandMode = v
                    }
                }

                FieldRow {
                    id: openDelayRow
                    label: "Open delay"
                    caption: "Wait before the hover row opens"
                    ScrubValue {
                        id: openDelayScrub
                        s: root.s
                        value: Flags.openDelay
                        openValue: root.base.openDelay
                        from: 0
                        to: 1000
                        step: 50
                        decimals: 0
                        unit: "ms"
                        onEdited: v => Flags.openDelay = v
                    }
                }

                FieldRow {
                    id: closeDelayRow
                    label: "Close delay"
                    caption: "Wait before it folds after you leave"
                    ScrubValue {
                        id: closeDelayScrub
                        s: root.s
                        value: Flags.closeDelay
                        openValue: root.base.closeDelay
                        from: 0
                        to: 2000
                        step: 50
                        decimals: 0
                        unit: "ms"
                        onEdited: v => Flags.closeDelay = v
                    }
                }
            }

            Group {
                id: wsGrp
                title: "Workspaces"

                FieldRow {
                    id: wsStyleRow
                    label: "Style"
                    caption: "In the hover row"
                    SettingsSeg {
                        s: root.s
                        options: [
                            {
                                label: "Dots",
                                value: "dots"
                            },
                            {
                                label: "Numbers",
                                value: "numbers"
                            },
                            {
                                label: "Names",
                                value: "names"
                            }
                        ]
                        value: Flags.wsStyle
                        onPicked: v => Flags.wsStyle = v
                    }
                }

                FieldRow {
                    id: wsShowRow
                    label: "Show"
                    caption: "Or every one up to the last"
                    SettingsSeg {
                        s: root.s
                        options: [
                            {
                                label: "Occupied",
                                value: "occupied"
                            },
                            {
                                label: "All",
                                value: "all"
                            }
                        ]
                        value: Flags.wsShow
                        onPicked: v => Flags.wsShow = v
                    }
                }

                FieldRow {
                    id: wsScrollRow
                    label: "Scroll to switch"
                    caption: "Mouse wheel over the workspaces"
                    LinkToggle {
                        s: root.s
                        on: Flags.wsScroll
                        onToggled: Flags.wsScroll = !Flags.wsScroll
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
