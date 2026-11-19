pragma ComponentBehavior: Bound

import QtQuick
import "Singletons"

/**
 * 知 NOTIFICATIONS sub-surface: switches single pill flashes (play and pause,
 * new song, volume, brightness, workspace, charging, recording) on or off,
 * scales how long every flash stays, sets how long an app notification card
 * stays in the pill, and mutes chosen apps so their messages skip the pill and
 * only land in the inbox. Everything persists through Flags. Reached from the
 * settings index; morphs back on the back chevron.
 */
SettingsSurface {
    id: root

    implicitHeight: content.implicitHeight

    readonly property var osdTimes: [0.5, 0.75, 1, 1.5, 2]
    readonly property var notifTimes: {
        var base = [3, 4, 6, 8, 12];
        if (base.indexOf(Flags.notifSecs) < 0)
            base = base.concat([Flags.notifSecs]);
        return base.sort(function (a, b) { return a - b; });
    }

    function flashOn(k) {
        return (Flags.osdOff || []).indexOf(k) < 0;
    }

    function setFlash(k, on) {
        var off = (Flags.osdOff || []).filter(function (o) { return o !== k; });
        if (!on)
            off.push(k);
        Flags.osdOff = off;
    }

    function flashEntry(item, k) {
        return { item: item, kind: "toggle", get: function () { return root.flashOn(k); }, set: function (v) { root.setFlash(k, v); } };
    }

    /**
     * Keyboard row registry, top to bottom. The charging row only counts on a
     * laptop with a battery, and each app row comes from the repeater so the
     * list follows Notifs.knownApps.
     */
    rows: {
        var r = [
            flashEntry(playRow, "play"),
            flashEntry(songRow, "song"),
            flashEntry(volumeRow, "volume"),
            flashEntry(brightnessRow, "brightness"),
            flashEntry(workspaceRow, "workspace")
        ];
        if (Battery.present)
            r.push(flashEntry(batteryRow, "battery"));
        r.push(flashEntry(recordRow, "record"));
        r.push({ item: osdTimeRow, kind: "seg", vals: root.osdTimes, get: function () { return Flags.osdTime; }, set: function (v) { Flags.osdTime = v; } });
        r.push({ item: dndRow, kind: "toggle", get: function () { return Flags.dnd; }, set: function (v) { Flags.dnd = v; } });
        r.push({ item: notifSecsRow, kind: "seg", vals: root.notifTimes, get: function () { return Flags.notifSecs; }, set: function (v) { Flags.notifSecs = v; } });
        void appsRepeater.count;
        for (var i = 0; i < appsRepeater.count; i++) {
            var it = appsRepeater.itemAt(i);
            if (!it)
                continue;
            (function (row) {
                r.push({ item: row, kind: "toggle", get: function () { return !Notifs.isMuted(row.app); }, set: function (v) { Notifs.setMuted(row.app, !v); } });
            })(it);
        }
        return r;
    }

    /** Keep a keyboard-focused app row scrolled into view inside the capped list. */
    onFocusRowItemChanged: {
        var it = root.focusRowItem;
        if (!it || it.parent !== appsCol)
            return;
        if (it.y < appsFlick.contentY)
            appsFlick.contentY = it.y;
        else if (it.y + it.height > appsFlick.contentY + appsFlick.height)
            appsFlick.contentY = it.y + it.height - appsFlick.height;
    }

    component GroupLabel: Text {
        topPadding: 16 * root.s
        bottomPadding: 6 * root.s
        leftPadding: 12 * root.s
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: 8.5 * root.s
        font.weight: Font.Bold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 1.2 * root.s
    }

    component FlashRow: SettingsRow {
        id: fr
        property string kind: ""
        surface: root
        captionOnFocus: true
        LinkToggle {
            s: root.s
            on: root.flashOn(fr.kind)
            onToggled: root.setFlash(fr.kind, !root.flashOn(fr.kind))
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
            glyph: "知"
            title: "NOTIFICATIONS"
            showBack: true
        }

        GroupLabel { text: "Media" }

        FlashRow {
            id: playRow
            icon: "play"
            name: "Play and pause"
            sub: "When music starts or stops"
            kind: "play"
        }
        FlashRow {
            id: songRow
            icon: "music"
            name: "New song"
            sub: "When the track changes"
            kind: "song"
            last: true
        }

        GroupLabel { text: "Pill flashes" }

        FlashRow {
            id: volumeRow
            icon: "speaker"
            name: "Volume"
            sub: "When you change the volume or mute"
            kind: "volume"
        }
        FlashRow {
            id: brightnessRow
            icon: "sun"
            name: "Brightness"
            sub: "When the screen gets brighter or darker"
            kind: "brightness"
        }
        FlashRow {
            id: workspaceRow
            icon: "layers"
            name: "Workspace"
            sub: "The dots when you switch workspaces"
            kind: "workspace"
        }
        FlashRow {
            id: batteryRow
            visible: Battery.present
            icon: "bolt"
            name: "Charging"
            sub: "When you plug in the charger"
            kind: "battery"
        }
        FlashRow {
            id: recordRow
            icon: "record"
            name: "Screen recording"
            sub: "When a recording starts or stops"
            kind: "record"
        }

        SettingsRow {
            id: osdTimeRow
            surface: root
            captionOnFocus: true
            icon: "clock"
            name: "How long they stay"
            sub: "Scales every flash, the song card included"
            SettingsSeg {
                s: root.s
                options: root.osdTimes.map(function (v) { return { label: v + "×", value: v }; })
                value: Flags.osdTime
                onPicked: (v) => Flags.osdTime = v
            }
        }

        SettingsRow {
            id: dndRow
            surface: root
            captionOnFocus: true
            icon: "dnd"
            name: "Do not disturb"
            sub: "Also hides media, workspace, charging and recording. Volume and brightness still show."
            last: true
            LinkToggle {
                s: root.s
                on: Flags.dnd
                onToggled: Flags.dnd = !Flags.dnd
            }
        }

        GroupLabel { text: "App notifications" }

        SettingsRow {
            id: notifSecsRow
            surface: root
            captionOnFocus: true
            icon: "inbox"
            name: "Show for"
            sub: "How long a new notification stays in the pill"
            last: true
            SettingsSeg {
                s: root.s
                options: root.notifTimes.map(function (v) { return { label: v + " s", value: v }; })
                value: Flags.notifSecs
                onPicked: (v) => Flags.notifSecs = v
            }
        }

        GroupLabel { text: "Apps" }

        SettingsRow {
            visible: Notifs.knownApps.length === 0
            surface: root
            name: "No apps yet"
            sub: "Apps show up here after their first notification"
            last: true
        }

        /**
         * Muting keeps an app out of the pill; its messages still land in the
         * inbox. Capped at a few rows and scrollable so a long list never
         * stretches the pill down the screen.
         */
        Flickable {
            id: appsFlick
            visible: Notifs.knownApps.length > 0
            width: parent.width
            height: visible ? Math.min(contentHeight, 260 * root.s) : 0
            contentWidth: width
            contentHeight: appsCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: appsCol
                width: appsFlick.width
                spacing: 0

                Repeater {
                    id: appsRepeater
                    model: Notifs.knownApps

                    SettingsRow {
                        id: appRow
                        required property var modelData
                        required property int index
                        readonly property string app: String(modelData)
                        surface: root
                        name: app
                        sub: Notifs.isMuted(app) ? "Only in the inbox" : "In the pill and the inbox"
                        last: index === appsRepeater.count - 1
                        LinkToggle {
                            s: root.s
                            on: !Notifs.isMuted(appRow.app)
                            onToggled: Notifs.setMuted(appRow.app, !Notifs.isMuted(appRow.app))
                        }
                    }
                }
            }
        }

        Item { width: 1; height: 10 * root.s }
    }
}
