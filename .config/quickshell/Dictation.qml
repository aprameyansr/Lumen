pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "Singletons"

/**
 * 声 DICTATION surface, straight off the settings index: the running word count
 * up top, then the on/off switch and the way into Vocabulary, then the history
 * of everything dictated, newest first.
 *
 * The count is kept apart from the history (Dictate.totalWords), so removing an
 * entry never takes words off it. "Typing saved" assumes ~40 wpm typing against
 * ~130 wpm speech, so it reads as an estimate.
 *
 * History rows join the row registry like any other: arrows move, Enter copies
 * the take to the clipboard (the row confirms with "Copied"), Delete or ✕
 * removes it. The list scrolls past `maxH` and keyboard focus keeps its row in
 * view.
 */
SettingsSurface {
    id: root

    implicitHeight: content.implicitHeight

    readonly property var items: Dictate.history

    /** Row registry: switch, vocabulary, then each history entry. */
    property int rowsRev: 0
    rows: {
        void root.rowsRev;
        void root.items;
        const r = [
            { item: enableRow, kind: "toggle", get: function () { return Flags.dictateEnabled; }, set: function (v) { Flags.dictateEnabled = v; } },
            { item: engineRow, kind: "seg", vals: ["whisper", "parakeet"], get: function () { return Flags.dictateEngine; }, set: function (v) { Flags.dictateEngine = v; } },
            { item: vocabRow, kind: "nav", surface: "vocab" }
        ];
        for (let i = 0; i < histRep.count; i++) {
            const it = histRep.itemAt(i);
            if (it && root.items[i])
                r.push({ item: it, kind: "action", run: (function (row) { return function () { row.copy(); }; })(it) });
        }
        return r;
    }

    /** Delete key: drop the focused history entry. */
    function deleteFocused() {
        const it = root.focusRowItem;
        if (!it || it.parent !== histCol)
            return;
        const keep = root.kbIndex;
        Dictate.removeHistory(it.entry.t);
        Qt.callLater(function () {
            root.kbIndex = Math.min(keep, root.rows.length - 1);
            root.focusRowItem = root.kbIndex >= 0 ? root.rows[root.kbIndex].item : null;
        });
    }

    function when(t) {
        const d = new Date(t);
        const now = new Date();
        const day = 86400000;
        const midnight = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
        const time = Qt.formatTime(d, Flags.time12h ? "h:mm AP" : "HH:mm");
        if (t >= midnight)
            return "Today " + time;
        if (t >= midnight - day)
            return "Yesterday " + time;
        return Qt.formatDate(d, "d MMM") + " " + time;
    }

    function fmt(n) {
        return Number(n).toLocaleString(Qt.locale("en_US"), "f", 0);
    }

    /** The seam rides the focused row through history scrolling too. */
    amePoint: {
        void root.width;
        void root.height;
        void histFlick.contentY;
        const it = root.focusRowItem;
        return it ? it.mapToItem(root, 4 * root.s, it.height / 2) : Qt.point(4 * root.s, root.height / 2);
    }

    onFocusRowItemChanged: {
        const it = root.focusRowItem;
        if (!it || it.parent !== histCol || !histFlick.interactive)
            return;
        const pad = 6 * root.s;
        const h = it.height + 30 * root.s;
        if (it.y - pad < histFlick.contentY)
            histFlick.contentY = Math.max(0, it.y - pad);
        else if (it.y + h + pad > histFlick.contentY + histFlick.height)
            histFlick.contentY = Math.min(histFlick.contentHeight - histFlick.height, it.y + h + pad - histFlick.height);
    }

    Column {
        id: content
        z: 100
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0

        SettingsHeader {
            s: root.s
            glyph: "声"
            title: "DICTATION"
            showBack: true
        }

        // ── word count ──

        Item {
            width: parent.width
            height: 62 * root.s

            Column {
                anchors.left: parent.left
                anchors.leftMargin: 9 * root.s
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0

                Text {
                    text: root.fmt(Dictate.totalWords)
                    color: Theme.cream
                    font.family: Theme.font
                    font.pixelSize: 28 * root.s
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                }
                Text {
                    text: Dictate.totalWords === 1 ? "word dictated" : "words dictated"
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 9 * root.s
                    font.weight: Font.Bold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1.2 * root.s
                }
            }

            Column {
                anchors.right: parent.right
                anchors.rightMargin: 9 * root.s
                anchors.verticalCenter: parent.verticalCenter
                spacing: 5 * root.s

                Row {
                    anchors.right: parent.right
                    spacing: 5 * root.s
                    Text {
                        text: root.fmt(Dictate.todayWords)
                        color: Theme.vermLit
                        font.family: Theme.font
                        font.pixelSize: 12.5 * root.s
                        font.weight: Font.DemiBold
                        font.features: { "tnum": 1 }
                    }
                    Text {
                        anchors.baseline: parent.children[0].baseline
                        text: "today"
                        color: Theme.subtle
                        font.family: Theme.font
                        font.pixelSize: 10.5 * root.s
                        font.weight: Font.Medium
                    }
                }
                Row {
                    anchors.right: parent.right
                    spacing: 5 * root.s
                    Text {
                        text: "≈ " + (Dictate.minutesSaved >= 60
                            ? (Math.floor(Dictate.minutesSaved / 60) + " h " + (Dictate.minutesSaved % 60) + " min")
                            : (Dictate.minutesSaved + " min"))
                        color: Theme.cream
                        font.family: Theme.font
                        font.pixelSize: 12.5 * root.s
                        font.weight: Font.DemiBold
                        font.features: { "tnum": 1 }
                    }
                    Text {
                        anchors.baseline: parent.children[0].baseline
                        text: "typing saved"
                        color: Theme.subtle
                        font.family: Theme.font
                        font.pixelSize: 10.5 * root.s
                        font.weight: Font.Medium
                    }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.hairSoft
        }

        Item { width: 1; height: 4 * root.s }

        // ── settings ──

        SettingsRow {
            id: enableRow
            surface: root
            captionOnFocus: true
            icon: "mic"
            name: "Enable dictation"
            sub: "Hold " + Dictate.keyLabel + " to talk, tap twice to lock"

            LinkToggle {
                s: root.s
                on: Flags.dictateEnabled
                onToggled: Flags.dictateEnabled = !Flags.dictateEnabled
            }
        }

        SettingsRow {
            id: engineRow
            surface: root
            captionOnFocus: true
            icon: "sparkles"
            name: "Engine"
            sub: Flags.dictateEngine === "whisper" ? "Most accurate, uses the GPU" : "Fastest, runs on the CPU"

            SettingsSeg {
                s: root.s
                options: [{ label: "Whisper", value: "whisper" }, { label: "Parakeet", value: "parakeet" }]
                value: Flags.dictateEngine
                onPicked: (v) => Flags.dictateEngine = v
            }
        }

        SettingsRow {
            id: vocabRow
            surface: root
            captionOnFocus: true
            icon: "type"
            name: "Vocabulary"
            sub: "Teach names and terms it gets wrong"
            last: true

            GlyphIcon {
                width: 16 * root.s
                height: 16 * root.s
                name: "chevron-right"
                color: root.focusRowItem === vocabRow ? Theme.cream : Theme.iconDim
                stroke: 2.2
            }
        }

        // ── history ──

        Text {
            width: parent.width
            leftPadding: 9 * root.s
            topPadding: 14 * root.s
            bottomPadding: 6 * root.s
            text: "History"
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 8.5 * root.s
            font.weight: Font.Bold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.2 * root.s
        }

        Text {
            width: parent.width
            visible: root.items.length === 0
            leftPadding: 9 * root.s
            rightPadding: 9 * root.s
            bottomPadding: 8 * root.s
            text: "Nothing dictated yet. Hold " + Dictate.keyLabel + " and talk, and it shows up here."
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 10 * root.s
            font.weight: Font.Medium
            wrapMode: Text.WordWrap
            lineHeight: 1.2
        }

        Flickable {
            id: histFlick
            readonly property real maxH: 230 * root.s
            width: parent.width
            height: Math.min(histCol.implicitHeight, maxH)
            contentHeight: histCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
            Behavior on contentY { enabled: !histFlick.moving; NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }

            Column {
                id: histCol
                width: parent.width

                Repeater {
                    id: histRep
                    model: root.items
                    onItemAdded: root.rowsRev++
                    onItemRemoved: root.rowsRev++

                    delegate: Item {
                        id: hrow
                        required property int index
                        required property var modelData
                        readonly property var entry: hrow.modelData

                        readonly property bool focused: root.focusRowItem === hrow
                        readonly property bool lit: hhover.hovered || hrow.focused
                        property bool copied: false

                        function copy() {
                            Dictate.copyText(hrow.entry.text);
                            hrow.copied = true;
                            copiedTimer.restart();
                        }

                        width: parent ? parent.width : 0
                        height: body.implicitHeight + 16 * root.s
                        Behavior on height { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }

                        Timer {
                            id: copiedTimer
                            interval: 1300
                            onTriggered: hrow.copied = false
                        }

                        HoverHandler {
                            id: hhover
                            onHoveredChanged: root.reportRowHover(hrow, hovered)
                        }

                        Rectangle {
                            anchors.fill: parent
                            anchors.topMargin: 2 * root.s
                            anchors.bottomMargin: 2 * root.s
                            radius: 9 * root.s
                            color: hrow.lit ? Theme.frameBg : "transparent"
                            Behavior on color { ColorAnimation { duration: Motion.fast } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.activateRow(hrow)
                        }

                        Column {
                            id: body
                            anchors.left: parent.left
                            anchors.leftMargin: 12 * root.s
                            anchors.right: hctl.left
                            anchors.rightMargin: 8 * root.s
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3 * root.s

                            Text {
                                width: parent.width
                                text: hrow.entry.text
                                color: Theme.cream
                                font.family: Theme.font
                                font.pixelSize: 12 * root.s
                                font.weight: Font.Medium
                                wrapMode: Text.Wrap
                                maximumLineCount: hrow.lit ? 6 : 1
                                elide: Text.ElideRight
                                lineHeight: 1.15
                            }
                            Text {
                                width: parent.width
                                text: hrow.copied ? "Copied to clipboard"
                                    : root.when(hrow.entry.t) + " · " + hrow.entry.words + (hrow.entry.words === 1 ? " word" : " words")
                                color: hrow.copied ? Theme.vermLit : Theme.faint
                                font.family: Theme.font
                                font.pixelSize: 9 * root.s
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                            }
                        }

                        Row {
                            id: hctl
                            anchors.right: parent.right
                            anchors.rightMargin: 6 * root.s
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2 * root.s
                            opacity: hrow.lit ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Motion.fast } }

                            Rectangle {
                                width: copyLabel.implicitWidth + 14 * root.s
                                height: 22 * root.s
                                radius: 6 * root.s
                                color: cpArea.containsMouse ? Qt.alpha(Theme.vermLit, 0.14) : "transparent"
                                Behavior on color { ColorAnimation { duration: Motion.fast } }

                                Text {
                                    id: copyLabel
                                    anchors.centerIn: parent
                                    text: hrow.copied ? "✓" : "Copy"
                                    color: cpArea.containsMouse || hrow.copied ? Theme.vermLit : Theme.subtle
                                    font.family: Theme.font
                                    font.pixelSize: 10.5 * root.s
                                    font.weight: Font.DemiBold
                                }

                                MouseArea {
                                    id: cpArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: hrow.lit
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: hrow.copy()
                                }
                            }

                            Rectangle {
                                width: 22 * root.s
                                height: 22 * root.s
                                radius: 6 * root.s
                                color: hrmArea.containsMouse ? Qt.alpha(Theme.verm, 0.16) : "transparent"
                                Behavior on color { ColorAnimation { duration: Motion.fast } }

                                GlyphIcon {
                                    anchors.centerIn: parent
                                    width: 11 * root.s
                                    height: 11 * root.s
                                    name: "close"
                                    color: hrmArea.containsMouse ? Theme.vermLit : Theme.iconDim
                                    stroke: 2
                                }

                                MouseArea {
                                    id: hrmArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: hrow.lit
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Dictate.removeHistory(hrow.entry.t)
                                }
                            }
                        }
                    }
                }
            }
        }

        Item { width: 1; height: 6 * root.s }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.hairSoft
        }

        Item {
            width: parent.width
            height: 20 * root.s

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 4 * root.s
                anchors.verticalCenter: parent.verticalCenter
                text: root.focusRowItem && root.focusRowItem.parent === histCol
                    ? "enter copy · del remove · esc back" : "enter open · esc back"
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 9.5 * root.s
                font.weight: Font.DemiBold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1 * root.s
            }
        }
    }
}
