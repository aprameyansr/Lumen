pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import "Singletons"

/**
 * 覚 KEEP AWAKE surface. A typographic read-out of the session on top (the
 * countdown as the hero, an "until … then …" subline and a thin time meter the
 * seam docks to), then the session controls as settings rows: the on/off
 * toggle, add-time chips while a timed session runs, what a closed lid does,
 * how long to run (chips plus a custom scrub) and what happens at zero. Below,
 * one-tap presets that apply and start a session, with a "save current" form.
 * Every row is on the keyboard row registry: arrows move and adjust, Enter
 * activates, Delete removes the focused preset. State lives in Flags through
 * the Awake singleton, so the pill's eye icon and this surface never disagree.
 */
SettingsSurface {
    id: root

    implicitHeight: content.implicitHeight

    property bool formOpen: false
    property string formName: ""

    readonly property var durChips: [0, 30, 60, 120, 240, 480]
    readonly property var lidVals: ["sleep", "awake"]
    readonly property var endVals: ["off", "sleep", "poweroff"]

    function openForm() {
        root.formName = "";
        root.formOpen = true;
        /** The save row hides under the form; hand the seam to the name box so it doesn't linger over the label. */
        root.kbIndex = -1;
        root.focusRowItem = nameSeam;
    }

    function closeForm() {
        root.formOpen = false;
        if (root.focusRowItem === nameSeam)
            root.focusRowItem = null;
        root.forceActiveFocus();
    }

    function saveForm() {
        if (Awake.savePreset(root.formName))
            root.closeForm();
    }

    /** Delete key: drop the keyboard-focused preset row, if one is focused. */
    function deleteFocused() {
        var it = root.focusRowItem;
        if (it && it.presetIndex !== undefined && it.presetIndex >= 0)
            Awake.deletePreset(it.presetIndex);
    }

    onActiveChanged: if (!active) formOpen = false
    onFormOpenChanged: if (formOpen) Qt.callLater(nameField.forceActiveFocus)

    function presetSub(p) {
        var lid = p.lid === "sleep" ? "Lid sleeps" : "Lid stays on";
        if (p.mins <= 0)
            return lid + " · until turned off";
        return lid + " · " + Awake.durLabel(p.mins) + " · then " + Awake.endLabels[p.end];
    }

    rows: {
        var r = [{ item: toggleRow, kind: "toggle", get: function () { return Awake.on; }, set: function (v) { if (v !== Awake.on) Awake.toggle(); } }];
        if (Awake.timed)
            r.push({ item: extendRow, kind: "action", run: function () { Awake.extend(15); } });
        r.push({ item: lidRow, kind: "seg", vals: root.lidVals, get: function () { return Flags.awakeLid; }, set: function (v) { Flags.awakeLid = v; } });
        r.push({ item: durRow, kind: "seg", vals: root.durChips, get: function () { return Flags.awakeMins; }, set: function (v) { Awake.setMins(v); } });
        r.push({ item: customRow, kind: "scrub", bump: function (d) { customScrub.bump(d); }, run: function () { Awake.setMins(Flags.awakeCustom); } });
        r.push({ item: endRow, kind: "seg", vals: root.endVals, get: function () { return Flags.awakeEnd; }, set: function (v) { Flags.awakeEnd = v; } });
        void presetRepeater.count;
        for (var i = 0; i < presetRepeater.count; i++) {
            var it = presetRepeater.itemAt(i);
            if (!it)
                continue;
            (function (row) {
                r.push({ item: row, kind: "action", run: function () { Awake.applyPreset(row.preset); } });
            })(it);
        }
        if (!root.formOpen)
            r.push({ item: saveRow, kind: "action", run: function () { root.openForm(); } });
        return r;
    }

    /** Enter on the custom row picks the custom length, same as a click on it. */
    function kbActivate() {
        if (kbIndex < 0)
            return;
        var r = rows[kbIndex];
        if (r.item === customRow)
            r.run();
        else if (r.kind === "toggle")
            r.set(!r.get());
        else if (r.kind === "seg")
            segCycle(r, 1);
        else if (r.kind === "action")
            r.run();
    }

    /**
     * Where the seam rests when no row is focused: the head of the time meter,
     * like the charge head on the battery card. mapToItem isn't reactive, so the
     * voids force re-eval across the morph and as the countdown runs.
     */
    /**
     * Per-frame fill while the surface is open, read straight off the wall
     * clock, so the bar and the seam docked on its head glide together instead
     * of stepping on the singleton's one-second tick (the seam would trail each
     * step by its glide). Idle when closed or untimed.
     */
    property real liveNow: Date.now()
    readonly property real liveFrac: (Awake.timed && Awake.until > Awake.from)
        ? Math.max(0, Math.min(1, (Awake.until - liveNow) / (Awake.until - Awake.from))) : 0

    FrameAnimation {
        running: root.active && Awake.timed
        onTriggered: root.liveNow = Date.now()
    }

    readonly property point meterHead: {
        void root.width;
        void root.height;
        void root.liveFrac;
        void meter.width;
        void meter.visible;
        return meter.mapToItem(root, meter.width * root.liveFrac, meter.height / 2);
    }

    ameForm: rowFocused ? "rowseam" : (Awake.timed ? "seam" : "off")
    amePoint: rowFocused ? rowPoint : meterHead

    component GroupLabel: Text {
        topPadding: 10 * root.s
        bottomPadding: 4 * root.s
        leftPadding: 12 * root.s
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: 8.5 * root.s
        font.weight: Font.Bold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 1.2 * root.s
    }

    Column {
        id: content
        z: 100
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0

        /** ── header: kanji + title, live state on the right ── */
        Item {
            width: parent.width
            height: 22 * root.s

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8 * root.s

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Flags.showGlyphs
                    text: "覚"
                    color: Theme.cream
                    font.family: Theme.fontJp
                    font.weight: Font.Medium
                    font.pixelSize: 16 * root.s
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "KEEP AWAKE"
                    color: Theme.subtle
                    font.family: Theme.font
                    font.pixelSize: 10 * root.s
                    font.weight: Font.DemiBold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1.6 * root.s
                }
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: !Awake.on ? "Off" : (Awake.timed ? Awake.clock(Awake.remainingMs) + " left" : "On")
                color: Awake.on ? Theme.flameGlow : Theme.dim
                font.family: Theme.font
                font.pixelSize: 9.5 * root.s
                font.weight: Font.Bold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.1 * root.s
                font.features: { "tnum": 1 }
            }
        }

        /** ── live subline, only while a session runs ── */
        Column {
            width: parent.width
            visible: Awake.on
            topPadding: 8 * root.s
            bottomPadding: Awake.timed ? 8 * root.s : 0
            spacing: 0

            Text {
                width: parent.width
                text: (Awake.timed
                        ? "Until " + Awake.wall(Awake.until) + ", then " + Awake.endLabels[Flags.awakeEnd]
                        : "Until you turn it off")
                color: Awake.on ? Theme.flameCore : Theme.subtle
                font.family: Theme.font
                font.pixelSize: 11 * root.s
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
        }

        Rectangle {
            id: meter
            visible: Awake.timed
            width: parent.width
            height: visible ? 3 * root.s : 0
            radius: 1.5 * root.s
            color: Theme.threadBg

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * root.liveFrac
                radius: parent.radius
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Theme.vermLit }
                    GradientStop { position: 1.0; color: Theme.flameGlow }
                }
            }
        }

        GroupLabel { text: "Session" }

        SettingsRow {
            id: toggleRow
            surface: root
            icon: "awake"
            name: "Keep awake"
            sub: "Hold off screen-off, lock and idle sleep"
            captionOnFocus: true
            LinkToggle {
                s: root.s
                on: Awake.on
                onToggled: Awake.toggle()
            }
        }

        SettingsRow {
            id: extendRow
            visible: Awake.timed
            height: visible ? implicitHeight : 0
            surface: root
            icon: "clock"
            name: "Add time"
            sub: "Pushes the end out from where it is now"
            captionOnFocus: true
            SettingsSeg {
                s: root.s
                options: [{ label: "+15m", value: 15 }, { label: "+30m", value: 30 }, { label: "+1h", value: 60 }]
                value: -1
                onPicked: (v) => Awake.extend(v)
            }
        }

        SettingsRow {
            id: lidRow
            surface: root
            icon: "suspend"
            name: "Closing the lid"
            sub: "Stays on keeps it running when shut"
            captionOnFocus: true
            SettingsSeg {
                s: root.s
                options: [{ label: "Sleeps", value: "sleep" }, { label: "Stays on", value: "awake" }]
                value: Flags.awakeLid
                onPicked: (v) => Flags.awakeLid = v
            }
        }

        SettingsRow {
            id: durRow
            surface: root
            icon: "stopwatch"
            name: "Run for"
            sub: Awake.on ? "Picking one restarts the clock from now" : "∞ runs until you turn it off"
            captionOnFocus: true
            SettingsSeg {
                s: root.s
                options: root.durChips.map(function (m) { return { label: Awake.durLabel(m), value: m }; })
                value: Flags.awakeMins
                onPicked: (v) => Awake.setMins(v)
            }
        }

        SettingsRow {
            id: customRow
            surface: root
            readonly property bool picked: Flags.awakeMins === Flags.awakeCustom && root.durChips.indexOf(Flags.awakeMins) < 0
            icon: "clock"
            name: "Custom length"
            sub: "Drag, or tap − / +. Enter uses it"
            captionOnFocus: true

            Row {
                spacing: 8 * root.s

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 5 * root.s
                    height: 5 * root.s
                    radius: width / 2
                    color: Theme.flameGlow
                    opacity: customRow.picked ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                }

                ScrubValue {
                    id: customScrub
                    anchors.verticalCenter: parent.verticalCenter
                    s: root.s
                    from: 5
                    to: 720
                    step: 5
                    value: Flags.awakeCustom
                    fmt: (v) => Awake.durLabel(v)
                    onEdited: (v) => {
                        Flags.awakeCustom = v;
                        Awake.setMins(v);
                    }
                }
            }
        }

        SettingsRow {
            id: endRow
            surface: root
            icon: "shutdown"
            name: "When time's up"
            sub: Flags.awakeMins > 0 ? "You get a heads-up a minute before" : "Only applies to a timed session"
            captionOnFocus: true
            last: true
            opacity: Flags.awakeMins > 0 || Awake.timed ? 1 : 0.55
            SettingsSeg {
                s: root.s
                options: [{ label: "Turn off", value: "off" }, { label: "Sleep", value: "sleep" }, { label: "Shut down", value: "poweroff" }]
                value: Flags.awakeEnd
                onPicked: (v) => Flags.awakeEnd = v
            }
        }

        GroupLabel { text: "Presets" }

        SettingsRow {
            visible: (Flags.awakePresets || []).length === 0
            height: visible ? implicitHeight : 0
            surface: root
            name: "No presets yet"
            sub: "Set up a session above, then save it here"
            last: true
        }

        Repeater {
            id: presetRepeater
            model: Flags.awakePresets || []

            SettingsRow {
                id: prow
                required property var modelData
                required property int index
                readonly property var preset: modelData
                readonly property int presetIndex: index
                readonly property bool live: Awake.on && Awake.presetMatches(modelData)
                surface: root
                icon: modelData.lid === "sleep" ? "suspend" : "awake"
                name: modelData.name
                sub: root.presetSub(modelData)
                last: index === presetRepeater.count - 1

                Row {
                    spacing: 10 * root.s

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: prow.live
                        text: "ACTIVE"
                        color: Theme.flameGlow
                        font.family: Theme.font
                        font.pixelSize: 8.5 * root.s
                        font.weight: Font.Bold
                        font.letterSpacing: 1.1 * root.s
                    }

                    Item {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 14 * root.s
                        height: 14 * root.s
                        opacity: (prow.focused || delArea.containsMouse) ? 1 : 0.35
                        Behavior on opacity { NumberAnimation { duration: Motion.fast } }

                        GlyphIcon {
                            anchors.fill: parent
                            name: "trash"
                            color: delArea.containsMouse ? Theme.vermLit : Theme.iconDim
                            stroke: 1.7
                        }

                        MouseArea {
                            id: delArea
                            anchors.fill: parent
                            anchors.margins: -6 * root.s
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Awake.deletePreset(prow.presetIndex)
                        }
                    }
                }
            }
        }

        /** ── save current: dashed add button, or the inline name form ── */
        Item {
            width: parent.width
            height: 10 * root.s
        }

        Item {
            id: saveRow
            visible: !root.formOpen
            width: parent.width
            height: visible ? 34 * root.s : 0
            readonly property bool focused: root.focusRowItem === saveRow

            HoverHandler {
                onHoveredChanged: root.reportRowHover(saveRow, hovered)
            }

            Canvas {
                id: dash
                anchors.fill: parent
                property color stroke: Qt.alpha(Theme.vermLit, (saveArea.containsMouse || saveRow.focused) ? 0.7 : 0.36)
                onStrokeChanged: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    var r = 9 * root.s;
                    var w = width;
                    var h = height;
                    var p = 0.5;
                    ctx.lineWidth = 1;
                    ctx.strokeStyle = stroke;
                    ctx.setLineDash([4 * root.s, 4 * root.s]);
                    ctx.beginPath();
                    ctx.moveTo(p + r, p);
                    ctx.lineTo(w - p - r, p);
                    ctx.arcTo(w - p, p, w - p, p + r, r);
                    ctx.lineTo(w - p, h - p - r);
                    ctx.arcTo(w - p, h - p, w - p - r, h - p, r);
                    ctx.lineTo(p + r, h - p);
                    ctx.arcTo(p, h - p, p, h - p - r, r);
                    ctx.lineTo(p, p + r);
                    ctx.arcTo(p, p, p + r, p, r);
                    ctx.stroke();
                }
            }

            Row {
                anchors.centerIn: parent
                spacing: 6 * root.s

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "+"
                    color: Theme.vermLit
                    font.family: Theme.font
                    font.pixelSize: 14 * root.s
                    font.weight: Font.Bold
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Save current as preset"
                    color: Theme.vermLit
                    font.family: Theme.font
                    font.pixelSize: 11 * root.s
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.5 * root.s
                }
            }

            MouseArea {
                id: saveArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openForm()
            }
        }

        Column {
            id: form
            visible: root.formOpen
            width: parent.width
            spacing: 10 * root.s

            Item {
                width: parent.width
                height: 40 * root.s

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 14 * root.s
                    anchors.top: parent.top
                    text: "PRESET NAME"
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 8.5 * root.s
                    font.weight: Font.Medium
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1 * root.s
                }

                Text {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    text: root.presetSub({ lid: Flags.awakeLid, mins: Flags.awakeMins, end: Flags.awakeEnd })
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 8.5 * root.s
                    font.weight: Font.Medium
                }

                /** Seam anchor: the row-seam column at the left, centred on the name box. */
                Item {
                    id: nameSeam
                    anchors.left: parent.left
                    anchors.top: nameBox.top
                    anchors.bottom: nameBox.bottom
                    width: 1
                }

                Rectangle {
                    id: nameBox
                    anchors.left: parent.left
                    anchors.leftMargin: 14 * root.s
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 26 * root.s
                    radius: 8 * root.s
                    color: Theme.frameBg
                    border.width: 1
                    border.color: nameField.activeFocus ? Qt.alpha(Theme.vermLit, 0.45) : Theme.hairSoft

                    TextField {
                        id: nameField
                        anchors.left: parent.left
                        anchors.leftMargin: 11 * root.s
                        anchors.right: parent.right
                        anchors.rightMargin: 11 * root.s
                        anchors.verticalCenter: parent.verticalCenter
                        background: null
                        padding: 0
                        color: Theme.cream
                        font.family: Theme.font
                        font.pixelSize: 11.5 * root.s
                        placeholderText: "Movie night"
                        placeholderTextColor: Theme.faint
                        selectByMouse: true
                        selectionColor: Theme.verm
                        maximumLength: 24
                        text: root.formName
                        onTextEdited: root.formName = text
                        Keys.onPressed: (e) => {
                            if (e.key === Qt.Key_Escape) { root.closeForm(); e.accepted = true; }
                            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { root.saveForm(); e.accepted = true; }
                        }
                    }
                }
            }

            Text {
                width: parent.width
                visible: (Flags.awakePresets || []).some(function (p) { return p.name.toLowerCase() === root.formName.trim().toLowerCase(); })
                text: "Replaces the preset with this name"
                color: Theme.flameGlow
                font.family: Theme.font
                font.pixelSize: 10 * root.s
                font.weight: Font.DemiBold
            }

            Item {
                width: parent.width
                height: 30 * root.s

                Rectangle {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: cancelLabel.implicitWidth + 24 * root.s
                    height: 28 * root.s
                    radius: 8 * root.s
                    color: cancelArea.containsMouse ? Theme.frameBg : "transparent"
                    border.width: 1
                    border.color: Theme.hairSoft

                    Text {
                        id: cancelLabel
                        anchors.centerIn: parent
                        text: "Cancel"
                        color: Theme.subtle
                        font.family: Theme.font
                        font.pixelSize: 10.5 * root.s
                        font.weight: Font.DemiBold
                        font.letterSpacing: 0.3 * root.s
                    }

                    MouseArea {
                        id: cancelArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closeForm()
                    }
                }

                Rectangle {
                    readonly property bool ready: root.formName.trim().length > 0
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: saveLabel.implicitWidth + 30 * root.s
                    height: 28 * root.s
                    radius: 8 * root.s
                    opacity: ready ? 1 : 0.45
                    color: Qt.alpha(Theme.onGlow, saveBtnArea.containsMouse && ready ? 0.24 : 0.16)
                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                    Text {
                        id: saveLabel
                        anchors.centerIn: parent
                        text: "Save preset"
                        color: Theme.cream
                        font.family: Theme.font
                        font.pixelSize: 10.5 * root.s
                        font.weight: Font.Bold
                        font.letterSpacing: 0.3 * root.s
                    }

                    MouseArea {
                        id: saveBtnArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: parent.ready ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: root.saveForm()
                    }
                }
            }
        }
    }
}
