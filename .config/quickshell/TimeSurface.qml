pragma ComponentBehavior: Bound

import QtQuick
import "Singletons"

/**
 * 時 CLOCK & WEATHER sub-surface: the pill clock's 24/12 hour format and
 * seconds, the date style (each choice previews today), the date language, the
 * calendar's first weekday and the temperature unit. Everything persists
 * through Flags. Reached from the settings index; morphs back on the back
 * chevron.
 */
SettingsSurface {
    id: root

    implicitHeight: content.implicitHeight

    readonly property var dateStyles: ["ddd d MMM", "ddd d", "d MMM", "dd.MM."]

    rows: [
        {
            item: timeRow,
            kind: "seg",
            vals: [false, true],
            get: function () {
                return Flags.time12h;
            },
            set: function (v) {
                Flags.time12h = v;
            }
        },
        {
            item: secRow,
            kind: "toggle",
            get: function () {
                return Flags.clockSeconds;
            },
            set: function (v) {
                Flags.clockSeconds = v;
            }
        },
        {
            item: dateRow,
            kind: "seg",
            vals: root.dateStyles,
            get: function () {
                return Flags.dateStyle;
            },
            set: function (v) {
                Flags.dateStyle = v;
            }
        },
        {
            item: langRow,
            kind: "seg",
            vals: ["en", "de"],
            get: function () {
                return Flags.dateLang;
            },
            set: function (v) {
                Flags.dateLang = v;
            }
        },
        {
            item: weekRow,
            kind: "seg",
            vals: [1, 0],
            get: function () {
                return Flags.weekStart;
            },
            set: function (v) {
                Flags.weekStart = v;
            }
        },
        {
            item: unitRow,
            kind: "seg",
            vals: ["c", "f"],
            get: function () {
                return Flags.weatherUnit;
            },
            set: function (v) {
                Flags.weatherUnit = v;
            }
        }
    ]

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

    Column {
        id: content
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0

        SettingsHeader {
            s: root.s
            glyph: "時"
            title: "CLOCK & WEATHER"
            showBack: true
        }

        GroupLabel {
            text: "Clock"
        }

        SettingsRow {
            id: timeRow
            surface: root
            name: "Time format"
            icon: "clock"

            SettingsSeg {
                s: root.s
                options: [
                    {
                        label: "24H",
                        value: false
                    },
                    {
                        label: "12H",
                        value: true
                    }
                ]
                value: Flags.time12h
                onPicked: v => Flags.time12h = v
            }
        }

        SettingsRow {
            id: secRow
            surface: root
            name: "Clock seconds"
            icon: "stopwatch"

            LinkToggle {
                s: root.s
                on: Flags.clockSeconds
                onToggled: Flags.clockSeconds = !Flags.clockSeconds
            }
        }

        SettingsRow {
            id: dateRow
            surface: root
            name: "Date"
            sub: "How the date under the hover clock reads"
            captionOnFocus: true
            icon: "calendar"

            SettingsSeg {
                s: root.s
                options: root.dateStyles.map(function (st) {
                    return {
                        label: Clocks.dateFor(st, Flags.dateLang, new Date()),
                        value: st
                    };
                })
                value: Flags.dateStyle
                onPicked: v => Flags.dateStyle = v
            }
        }

        SettingsRow {
            id: langRow
            surface: root
            name: "Language"
            sub: "Day and month names in the pill and calendar"
            captionOnFocus: true
            icon: "language"

            SettingsSeg {
                s: root.s
                options: [
                    {
                        label: "English",
                        value: "en"
                    },
                    {
                        label: "Deutsch",
                        value: "de"
                    }
                ]
                value: Flags.dateLang
                onPicked: v => Flags.dateLang = v
            }
        }

        SettingsRow {
            id: weekRow
            surface: root
            name: "Week starts"
            icon: "layers"
            last: true

            SettingsSeg {
                s: root.s
                options: [
                    {
                        label: "Monday",
                        value: 1
                    },
                    {
                        label: "Sunday",
                        value: 0
                    }
                ]
                value: Flags.weekStart
                onPicked: v => Flags.weekStart = v
            }
        }

        GroupLabel {
            text: "Weather"
        }

        SettingsRow {
            id: unitRow
            surface: root
            name: "Temperature"
            icon: "sun"
            last: true

            SettingsSeg {
                s: root.s
                options: [
                    {
                        label: "°C",
                        value: "c"
                    },
                    {
                        label: "°F",
                        value: "f"
                    }
                ]
                value: Flags.weatherUnit
                onPicked: v => Flags.weatherUnit = v
            }
        }

        Item {
            width: 1
            height: 6 * root.s
        }
    }
}
