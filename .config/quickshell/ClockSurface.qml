pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import "Singletons"

/**
 * 刻 CLOCK surface: stopwatch, timer and world clock behind segmented tabs
 * in the header, with a calendar link beside them. Everything runs in the
 * Clocks singleton, so this page is only a view: closing it, or reloading the
 * shell, never stops a stopwatch or a timer.
 *
 * Stopwatch: the elapsed time as the hero (hundredths set small), a sweep bar
 * that fills once a minute with the seam riding its head, Start/Pause/Resume and
 * Lap/Reset, then the laps newest first with the fastest marked warm.
 * Timer: the time left as the hero (click it while idle to type a length like
 * "5", "1:30" or "1h 20m"), a bar that drains with the seam at its head, quick
 * lengths while idle or add-time chips while running, Start/Pause/Resume and
 * Reset. World: your local time, then each saved city with its offset from you
 * and a Yesterday/Tomorrow hint; "+ Add city" opens a search over the system
 * time zone database.
 *
 * Keyboard: Left/Right switch tabs. Space or Enter starts and pauses, L marks a
 * lap, R resets. On the timer, Up/Down change the length while idle and Up adds
 * a minute while running. On the world tab Up/Down move between cities, Delete
 * removes one, Enter on "+ Add city" opens the search, whose results Up/Down and
 * Enter pick from.
 */
PillSurface {
    id: root

    mTop: 15
    mLeft: 19
    mRight: 19
    mBottom: 14

    signal requestSurface(string name)

    implicitHeight: content.implicitHeight

    readonly property var tabs: ["stopwatch", "timer", "world"]
    readonly property string tab: tabs.indexOf(Flags.clockTab) >= 0 ? Flags.clockTab : "stopwatch"

    /** Per-frame wall clock while the page is open and something moves; a 1 s tick on the world tab. */
    property real liveNow: Date.now()

    FrameAnimation {
        running: root.active && ((root.tab === "stopwatch" && Clocks.swRunning) || (root.tab === "timer" && Clocks.tmRunning))
        onTriggered: root.liveNow = Date.now()
    }

    Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: root.active && root.tab === "world"
        onTriggered: root.liveNow = Date.now()
    }

    onActiveChanged: {
        root.liveNow = Date.now();
        if (!active) {
            root.searching = false;
            root.typingDur = false;
            root.worldIndex = -1;
        } else if (root.tab === "world") {
            Clocks.loadCatalogue();
        }
    }

    onTabChanged: {
        root.liveNow = Date.now();
        root.searching = false;
        root.typingDur = false;
        root.worldIndex = -1;
        if (root.tab === "world")
            Clocks.loadCatalogue();
    }

    readonly property real swElapsed: {
        void root.liveNow;
        void Flags.swStart;
        void Flags.swAccum;
        return Clocks.swElapsedAt(root.liveNow);
    }
    readonly property real tmRemain: {
        void root.liveNow;
        void Flags.tmEnd;
        void Flags.tmLeft;
        void Flags.tmDur;
        return Clocks.tmRemainAt(root.liveNow);
    }
    readonly property real tmFrac: {
        void root.liveNow;
        void Flags.tmEnd;
        void Flags.tmLeft;
        void Flags.tmTotal;
        return Clocks.tmFracAt(root.liveNow);
    }

    // ── keyboard ──

    property int worldIndex: -1
    property bool searching: false
    property int searchIndex: 0
    property bool typingDur: false
    property bool durBad: false
    property var results: []

    function switchTab(dir) {
        var i = root.tabs.indexOf(root.tab);
        Flags.clockTab = root.tabs[(i + dir + root.tabs.length) % root.tabs.length];
    }

    /** Rows the world tab's Up/Down walk: each saved city, then the add row. */
    readonly property int worldCount: (Flags.worldZones || []).length + 1

    /** Host key entry point. Returns true when the key was used. */
    function key(k, mods) {
        if (root.searching || root.typingDur) {
            if (root.searching && (k === Qt.Key_Up || k === Qt.Key_Down)) {
                const n = root.results.length;
                if (n)
                    root.searchIndex = Math.max(0, Math.min(n - 1, root.searchIndex + (k === Qt.Key_Down ? 1 : -1)));
                return true;
            }
            /** Let a text field keep Left/Right even at its ends instead of flipping tabs. */
            return k === Qt.Key_Left || k === Qt.Key_Right;
        }
        if (k === Qt.Key_Left || k === Qt.Key_Right) {
            root.switchTab(k === Qt.Key_Right ? 1 : -1);
            return true;
        }
        var go = k === Qt.Key_Space || k === Qt.Key_Return || k === Qt.Key_Enter;
        if (root.tab === "stopwatch") {
            if (go) {
                Clocks.swToggle();
                return true;
            }
            if (k === Qt.Key_L) {
                Clocks.swLap();
                return true;
            }
            if (k === Qt.Key_R) {
                if (!Clocks.swRunning)
                    Clocks.swReset();
                return true;
            }
            return false;
        }
        if (root.tab === "timer") {
            if (go) {
                Clocks.tmToggle();
                return true;
            }
            if (k === Qt.Key_R) {
                Clocks.tmReset();
                return true;
            }
            if (k === Qt.Key_Up || k === Qt.Key_Down) {
                if (Clocks.tmIdle)
                    Clocks.tmSet(Flags.tmDur + (k === Qt.Key_Up ? 60000 : -60000));
                else if (k === Qt.Key_Up)
                    Clocks.tmAdd(60000);
                return true;
            }
            return false;
        }
        // world
        var dir = k === Qt.Key_Down ? 1 : -1;
        if ((k === Qt.Key_Up || k === Qt.Key_Down) && (mods & Qt.ControlModifier) && root.worldIndex >= 0 && root.worldIndex < root.worldCount - 1) {
            const zone = Flags.worldZones[root.worldIndex];
            const to = root.worldIndex + dir;
            if (to >= 0 && to < root.worldCount - 1) {
                Clocks.moveZone(zone, dir);
                root.worldIndex = to;
            }
            return true;
        }
        if (k === Qt.Key_Up || k === Qt.Key_Down) {
            root.worldIndex = Math.max(0, Math.min(root.worldCount - 1, root.worldIndex < 0 ? 0 : root.worldIndex + (k === Qt.Key_Down ? 1 : -1)));
            return true;
        }
        if (go && root.worldIndex === root.worldCount - 1) {
            root.openSearch();
            return true;
        }
        if ((k === Qt.Key_Delete || k === Qt.Key_Backspace) && root.worldIndex >= 0 && root.worldIndex < root.worldCount - 1) {
            Clocks.removeZone(Flags.worldZones[root.worldIndex]);
            root.worldIndex = Math.min(root.worldIndex, root.worldCount - 1);
            return true;
        }
        return false;
    }

    function openSearch() {
        Clocks.loadCatalogue();
        root.results = [];
        root.searchIndex = 0;
        root.searching = true;
        Qt.callLater(searchField.forceActiveFocus);
    }

    function closeSearch() {
        root.searching = false;
        searchField.text = "";
        root.forceActiveFocus();
    }

    function pickResult(i) {
        if (i < 0 || i >= root.results.length)
            return;
        Clocks.addZone(root.results[i].zone);
        root.closeSearch();
        root.worldIndex = (Flags.worldZones || []).length - 1;
    }

    function openDurEdit() {
        if (!Clocks.tmIdle)
            return;
        durField.text = "";
        root.durBad = false;
        root.typingDur = true;
        Qt.callLater(durField.forceActiveFocus);
    }

    function commitDur() {
        var ms = Clocks.parseDur(durField.text);
        if (ms <= 0) {
            root.durBad = true;
            return;
        }
        Clocks.tmSet(ms);
        root.typingDur = false;
        root.forceActiveFocus();
    }

    // ── world helpers ──

    readonly property int localOff: {
        void root.liveNow;
        return Clocks.localOffset();
    }

    function zoneTime(zone) {
        void root.liveNow;
        var d = Clocks.zoneDate(zone, root.liveNow);
        return d ? Qt.formatTime(d, Flags.time12h ? "h:mm AP" : "HH:mm") : "…";
    }

    /** "+5:30", "−3h", "Same time", with a day hint against your local date. */
    function zoneSub(zone) {
        void root.liveNow;
        var off = Clocks.offsets[zone];
        if (off === undefined)
            return "";
        var diff = off - root.localOff;
        var label;
        if (diff === 0) {
            label = "Same time";
        } else {
            const a = Math.abs(diff);
            const h = Math.floor(a / 60);
            const m = a % 60;
            label = (diff > 0 ? "+" : "−") + h + (m ? ":" + Clocks.pad2(m) : "h") + (diff > 0 ? " ahead" : " behind");
        }
        var here = new Date(root.liveNow);
        var there = Clocks.zoneDate(zone, root.liveNow);
        if (there) {
            const dd = Math.round((new Date(there.getFullYear(), there.getMonth(), there.getDate()) - new Date(here.getFullYear(), here.getMonth(), here.getDate())) / 86400000);
            if (dd > 0)
                label += " · Tomorrow";
            else if (dd < 0)
                label += " · Yesterday";
        }
        return label;
    }

    function countryOf(zone) {
        void Clocks.catalogue;
        var hit = Clocks.catalogue.find(function (e) {
            return e.zone === zone;
        });
        return hit ? hit.country : "";
    }

    // ── seam ──

    readonly property Item focusedWorldRow: root.tab !== "world" ? null : (root.searching ? searchBox : (root.worldIndex >= 0 ? (root.worldIndex < root.worldCount - 1 ? worldRepeater.itemAt(root.worldIndex) : addRow) : null))

    ameForm: clockTabs.pointedOption ? "soul" : root.tab === "stopwatch" ? (Clocks.swIdle ? "off" : "seam") : (root.tab === "timer" ? (Clocks.tmIdle ? "off" : "seam") : (root.focusedWorldRow ? "rowseam" : "off"))

    amePoint: {
        void root.width;
        void root.height;
        void root.liveNow;
        void root.tab;
        const option = clockTabs.pointedOption;
        if (option) {
            void clockTabs.x;
            void option.x;
            return option.mapToItem(root, option.width / 2, option.height + 4 * root.s);
        }
        if (root.tab === "stopwatch") {
            void sweep.width;
            return sweep.mapToItem(root, sweep.width * ((root.swElapsed % 60000) / 60000), sweep.height / 2);
        }
        if (root.tab === "timer") {
            void meter.width;
            return meter.mapToItem(root, meter.width * root.tmFrac, meter.height / 2);
        }
        var it = root.focusedWorldRow;
        if (!it)
            return Qt.point(4 * root.s, root.height / 2);
        void it.height;
        return Qt.point(4 * root.s, it.mapToItem(root, 0, it.height / 2).y);
    }

    // ── parts ──

    component Label8: Text {
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: 8.5 * root.s
        font.weight: Font.Bold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 1.2 * root.s
    }

    /** Primary (flame tint) or secondary (outlined) action button. */
    component ActionBtn: Rectangle {
        id: btn
        property string label: ""
        property bool primary: false
        property bool can: true
        signal clicked

        height: 30 * root.s
        radius: 8 * root.s
        opacity: btn.can ? 1 : 0.4
        color: btn.primary ? Qt.alpha(Theme.onGlow, btnArea.containsMouse && btn.can ? 0.24 : 0.16) : (btnArea.containsMouse && btn.can ? Theme.frameBg : "transparent")
        border.width: btn.primary ? 0 : 1
        border.color: Theme.hairSoft
        Behavior on color {
            ColorAnimation {
                duration: Motion.fast
            }
        }

        Text {
            anchors.centerIn: parent
            text: btn.label
            color: btn.primary ? Theme.cream : Theme.subtle
            font.family: Theme.font
            font.pixelSize: 10.5 * root.s
            font.weight: btn.primary ? Font.Bold : Font.DemiBold
            font.letterSpacing: 0.3 * root.s
        }

        MouseArea {
            id: btnArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: btn.can ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (btn.can)
                btn.clicked()
        }
    }

    component Hint: Text {
        width: parent ? parent.width : 0
        topPadding: 8 * root.s
        horizontalAlignment: Text.AlignHCenter
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: 8.5 * root.s
        font.weight: Font.Medium
        font.letterSpacing: 0.3 * root.s
    }

    component Track: Rectangle {
        id: track
        property real frac: 0
        width: parent ? parent.width : 0
        height: 3 * root.s
        radius: 1.5 * root.s
        color: Theme.threadBg

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * Math.max(0, Math.min(1, track.frac))
            radius: parent.radius
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop {
                    position: 0.0
                    color: Theme.vermLit
                }
                GradientStop {
                    position: 1.0
                    color: Theme.flameGlow
                }
            }
        }
    }

    component WorldRow: Item {
        id: wrow
        property string city: ""
        property string sub: ""
        property string time: ""
        property bool local: false
        property bool focused: false
        property bool removable: false
        /** Being dragged: lifted above the list, brighter, with an accent edge. */
        property bool lifted: false
        signal removed
        signal hovered

        width: parent ? parent.width : 0
        height: 44 * root.s

        HoverHandler {
            id: wrowHover
            onHoveredChanged: if (hovered)
                wrow.hovered()
        }

        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 3 * root.s
            anchors.bottomMargin: 3 * root.s
            radius: 9 * root.s
            color: wrow.lifted ? Qt.alpha(Theme.onGlow, 0.14) : ((wrowHover.hovered || wrow.focused) ? Theme.frameBg : "transparent")
            border.width: wrow.lifted ? 1 : 0
            border.color: Qt.alpha(Theme.vermLit, 0.45)
            Behavior on color {
                ColorAnimation {
                    duration: Motion.fast
                }
            }
        }

        Column {
            anchors.left: parent.left
            anchors.leftMargin: 16 * root.s
            anchors.right: timeText.left
            anchors.rightMargin: 10 * root.s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3 * root.s

            Text {
                width: parent.width
                text: wrow.city
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 12.5 * root.s
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: wrow.sub
                color: wrow.local ? Theme.flameCore : Theme.faint
                font.family: Theme.font
                font.pixelSize: 10 * root.s
                font.weight: Font.Medium
                elide: Text.ElideRight
            }
        }

        Item {
            id: delBox
            visible: wrow.removable
            anchors.right: parent.right
            anchors.rightMargin: 10 * root.s
            anchors.verticalCenter: parent.verticalCenter
            width: 14 * root.s
            height: 14 * root.s
            opacity: (wrowHover.hovered || wrow.focused) ? (delArea.containsMouse ? 1 : 0.6) : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: Motion.fast
                }
            }

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
                onClicked: wrow.removed()
            }
        }

        /** Grip: the row can be dragged to reorder. Shown with the trash on hover or keyboard focus. */
        Grid {
            id: orderBox
            visible: wrow.removable
            anchors.right: delBox.left
            anchors.rightMargin: 12 * root.s
            anchors.verticalCenter: parent.verticalCenter
            columns: 2
            spacing: 2.5 * root.s
            opacity: (wrowHover.hovered || wrow.focused) ? 0.6 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: Motion.fast
                }
            }

            Repeater {
                model: 6
                Rectangle {
                    width: 2.6 * root.s
                    height: 2.6 * root.s
                    radius: width / 2
                    color: Theme.iconDim
                }
            }
        }

        Text {
            id: timeText
            anchors.right: wrow.removable ? orderBox.left : parent.right
            anchors.rightMargin: wrow.removable ? 12 * root.s : 10 * root.s
            anchors.verticalCenter: parent.verticalCenter
            text: wrow.time
            color: wrow.local ? Theme.flameGlow : Theme.cream
            font.family: Theme.font
            font.pixelSize: 17 * root.s
            font.weight: Font.Bold
            font.features: {
                "tnum": 1
            }
        }
    }

    Column {
        id: content
        z: 100
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0

        // ── header: title, tabs, calendar link ──
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
                    text: "刻"
                    color: Theme.cream
                    font.family: Theme.fontJp
                    font.weight: Font.Medium
                    font.pixelSize: 16 * root.s
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "CLOCK"
                    color: Theme.subtle
                    font.family: Theme.font
                    font.pixelSize: 10 * root.s
                    font.weight: Font.DemiBold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1.6 * root.s
                }
            }

            SettingsSeg {
                id: clockTabs
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                s: root.s
                options: [
                    {
                        label: "Stopwatch",
                        value: "stopwatch"
                    },
                    {
                        label: "Timer",
                        value: "timer"
                    },
                    {
                        label: "World",
                        value: "world"
                    }
                ]
                value: root.tab
                onPicked: value => Flags.clockTab = value
            }

            Item {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 16 * root.s
                height: 16 * root.s

                GlyphIcon {
                    anchors.fill: parent
                    name: "calendar"
                    color: calArea.containsMouse ? Theme.cream : Theme.iconDim
                    stroke: 1.7
                }

                MouseArea {
                    id: calArea
                    anchors.fill: parent
                    anchors.margins: -6 * root.s
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.requestSurface("calendar")
                }
            }
        }

        // ── stopwatch ──
        Column {
            visible: root.tab === "stopwatch"
            width: parent.width
            topPadding: 14 * root.s
            spacing: 0

            Row {
                spacing: 2 * root.s

                Text {
                    id: swBig
                    text: Clocks.fmtClock(root.swElapsed, false)
                    color: Clocks.swIdle ? Theme.dim : Theme.cream
                    font.family: Theme.font
                    font.pixelSize: 40 * root.s
                    font.weight: Font.Bold
                    font.letterSpacing: -1 * root.s
                    font.features: {
                        "tnum": 1
                    }
                }
                Text {
                    anchors.baseline: swBig.baseline
                    text: "." + Clocks.fmtCenti(root.swElapsed)
                    color: Clocks.swIdle ? Theme.faint : Theme.subtle
                    font.family: Theme.font
                    font.pixelSize: 20 * root.s
                    font.weight: Font.Bold
                    font.features: {
                        "tnum": 1
                    }
                }
            }

            Text {
                topPadding: 4 * root.s
                bottomPadding: 12 * root.s
                text: Clocks.swRunning ? "Running" : (Clocks.swIdle ? "Ready" : "Paused")
                color: Clocks.swRunning ? Theme.flameCore : Theme.subtle
                font.family: Theme.font
                font.pixelSize: 11 * root.s
                font.weight: Font.DemiBold
            }

            Track {
                id: sweep
                frac: (root.swElapsed % 60000) / 60000
            }

            Row {
                topPadding: 14 * root.s
                spacing: 8 * root.s
                width: parent.width

                ActionBtn {
                    width: (parent.width - 8 * root.s) * 0.6
                    primary: true
                    label: Clocks.swRunning ? "Pause" : (Clocks.swIdle ? "Start" : "Resume")
                    onClicked: Clocks.swToggle()
                }
                ActionBtn {
                    width: (parent.width - 8 * root.s) * 0.4
                    label: Clocks.swRunning ? "Lap" : "Reset"
                    can: !Clocks.swIdle
                    onClicked: Clocks.swRunning ? Clocks.swLap() : Clocks.swReset()
                }
            }

            Hint {
                text: "Space start / pause  ·  L lap  ·  R reset  ·  ← → tabs"
            }

            /** Laps, newest first; the fastest of two or more is marked warm. Capped and scrollable. */
            Item {
                visible: (Flags.swLaps || []).length > 0
                width: parent.width
                height: visible ? 10 * root.s : 0
            }

            Flickable {
                id: lapFlick
                visible: (Flags.swLaps || []).length > 0
                width: parent.width
                height: visible ? Math.min(contentHeight, 150 * root.s) : 0
                contentHeight: lapCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                readonly property var splits: {
                    var l = Flags.swLaps || [];
                    var out = [];
                    for (let i = 0; i < l.length; i++)
                        out.push(l[i] - (i ? l[i - 1] : 0));
                    return out;
                }
                readonly property real best: splits.length > 1 ? Math.min.apply(null, splits) : -1

                Column {
                    id: lapCol
                    width: parent.width

                    Repeater {
                        model: (Flags.swLaps || []).length

                        Item {
                            id: lapRow
                            required property int index
                            readonly property int lapNo: (Flags.swLaps || []).length - index
                            readonly property real split: lapFlick.splits[lapNo - 1] || 0
                            readonly property bool best: split === lapFlick.best
                            width: lapCol.width
                            height: 24 * root.s

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 4 * root.s
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Lap " + lapRow.lapNo
                                color: lapRow.best ? Theme.flameGlow : Theme.subtle
                                font.family: Theme.font
                                font.pixelSize: 11 * root.s
                                font.weight: Font.DemiBold
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.verticalCenter: parent.verticalCenter
                                text: Clocks.fmtClock(lapRow.split, false) + "." + Clocks.fmtCenti(lapRow.split)
                                color: lapRow.best ? Theme.flameGlow : Theme.cream
                                font.family: Theme.font
                                font.pixelSize: 11.5 * root.s
                                font.weight: Font.DemiBold
                                font.features: {
                                    "tnum": 1
                                }
                            }
                            Text {
                                anchors.right: parent.right
                                anchors.rightMargin: 4 * root.s
                                anchors.verticalCenter: parent.verticalCenter
                                text: Clocks.fmtClock((Flags.swLaps || [])[lapRow.lapNo - 1] || 0, false) + "." + Clocks.fmtCenti((Flags.swLaps || [])[lapRow.lapNo - 1] || 0)
                                color: Theme.faint
                                font.family: Theme.font
                                font.pixelSize: 10.5 * root.s
                                font.weight: Font.Medium
                                font.features: {
                                    "tnum": 1
                                }
                            }
                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: 1
                                color: Theme.hairSoft
                                visible: lapRow.index < (Flags.swLaps || []).length - 1
                            }
                        }
                    }
                }
            }
        }

        // ── timer ──
        Column {
            visible: root.tab === "timer"
            width: parent.width
            topPadding: 14 * root.s
            spacing: 0

            /** The hero: time left, or the set length while idle (click to type one). */
            Item {
                width: parent.width
                height: tmBig.implicitHeight

                Text {
                    id: tmBig
                    visible: !root.typingDur
                    text: Clocks.fmtClock(root.tmRemain, true)
                    color: Clocks.tmIdle ? (tmBigArea.containsMouse ? Theme.cream : Theme.subtle) : (Clocks.tmPaused ? Theme.subtle : Theme.cream)
                    font.family: Theme.font
                    font.pixelSize: 40 * root.s
                    font.weight: Font.Bold
                    font.letterSpacing: -1 * root.s
                    font.features: {
                        "tnum": 1
                    }
                    Behavior on color {
                        ColorAnimation {
                            duration: Motion.fast
                        }
                    }
                }
                MouseArea {
                    id: tmBigArea
                    visible: !root.typingDur
                    anchors.left: parent.left
                    width: tmBig.implicitWidth
                    height: parent.height
                    hoverEnabled: true
                    enabled: Clocks.tmIdle
                    cursorShape: Clocks.tmIdle ? Qt.IBeamCursor : Qt.ArrowCursor
                    onClicked: root.openDurEdit()
                }
                TextField {
                    id: durField
                    visible: root.typingDur
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    background: null
                    padding: 0
                    color: root.durBad ? Theme.vermLit : Theme.cream
                    font.family: Theme.font
                    font.pixelSize: 28 * root.s
                    font.weight: Font.Bold
                    placeholderText: "5, 1:30, 1h 20m"
                    placeholderTextColor: Theme.faint
                    selectByMouse: true
                    selectionColor: Theme.verm
                    onTextEdited: root.durBad = false
                    onAccepted: root.commitDur()
                    Keys.onEscapePressed: {
                        root.typingDur = false;
                        root.forceActiveFocus();
                    }
                    onActiveFocusChanged: if (!activeFocus)
                        root.typingDur = false
                }
            }

            Text {
                topPadding: 4 * root.s
                bottomPadding: 12 * root.s
                text: Clocks.ringing ? "Time's up" : Clocks.tmRunning ? "Ends at " + Clocks.wallTime(Flags.tmEnd) : (Clocks.tmPaused ? "Paused" : (root.typingDur ? "Enter to set, Esc to cancel" : "Click the time to type a length"))
                color: (Clocks.ringing || Clocks.tmRunning) ? Theme.flameCore : (root.durBad ? Theme.vermLit : Theme.subtle)
                font.family: Theme.font
                font.pixelSize: 11 * root.s
                font.weight: Font.DemiBold
            }

            Track {
                id: meter
                frac: root.tmFrac
            }

            Item {
                width: parent.width
                height: 40 * root.s

                SettingsSeg {
                    anchors.centerIn: parent
                    s: root.s
                    visible: Clocks.tmIdle
                    options: [1, 3, 5, 10, 15, 30, 60].map(function (m) {
                        return {
                            label: m < 60 ? m + "m" : "1h",
                            value: m * 60000
                        };
                    })
                    value: Flags.tmDur
                    onPicked: v => Clocks.tmSet(v)
                }
                SettingsSeg {
                    anchors.centerIn: parent
                    s: root.s
                    visible: !Clocks.tmIdle
                    options: [
                        {
                            label: "+30s",
                            value: 30000
                        },
                        {
                            label: "+1m",
                            value: 60000
                        },
                        {
                            label: "+5m",
                            value: 300000
                        },
                        {
                            label: "+10m",
                            value: 600000
                        }
                    ]
                    value: -1
                    onPicked: v => Clocks.tmAdd(v)
                }
            }

            Row {
                spacing: 8 * root.s
                width: parent.width

                ActionBtn {
                    width: (parent.width - 8 * root.s) * 0.6
                    primary: true
                    label: Clocks.ringing ? "Stop alarm" : (Clocks.tmRunning ? "Pause" : (Clocks.tmPaused ? "Resume" : "Start"))
                    can: Clocks.ringing || !Clocks.tmIdle || Flags.tmDur > 0
                    onClicked: Clocks.tmToggle()
                }
                ActionBtn {
                    width: (parent.width - 8 * root.s) * 0.4
                    label: "Reset"
                    can: !Clocks.tmIdle
                    onClicked: Clocks.tmReset()
                }
            }

            Hint {
                text: Clocks.tmIdle ? "Space start  ·  ↑ ↓ ±1 min  ·  ← → tabs" : "Space pause / resume  ·  ↑ +1 min  ·  R reset"
            }
        }

        // ── world ──
        Column {
            visible: root.tab === "world"
            width: parent.width
            topPadding: 12 * root.s
            spacing: 0

            WorldRow {
                city: Clocks.localZone.length ? Clocks.cityOf(Clocks.localZone) : "Local time"
                sub: "Here"
                local: true
                time: {
                    void root.liveNow;
                    return Qt.formatTime(new Date(root.liveNow), Flags.time12h ? "h:mm AP" : "HH:mm");
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.hairSoft
            }

            /**
             * Drag-and-drop reordering. Rows are rebuilt whenever the list
             * changes, which would drop a drag held by one row, so the list
             * owns it: past the drag threshold it maps the pointer to a slot and
             * moves the city there live, the highlight riding along.
             */
            Column {
                id: zoneCol
                width: parent.width
                readonly property real rowH: 44 * root.s
                /**
                 * Drag state. The list never reorders mid-drag (that rebuilt
                 * every row and made them jump): the held row follows the
                 * pointer, the rows it passes slide one slot to open a gap, and
                 * the move is committed once on release.
                 */
                property int dragFrom: -1
                property int dragTo: -1
                property real dragDy: 0
                property bool slide: true

                function offsetFor(i) {
                    var f = zoneCol.dragFrom, t = zoneCol.dragTo;
                    if (f < 0)
                        return 0;
                    if (i === f)
                        return zoneCol.dragDy;
                    if (f < t && i > f && i <= t)
                        return -zoneCol.rowH;
                    if (f > t && i >= t && i < f)
                        return zoneCol.rowH;
                    return 0;
                }

                HoverHandler {
                    cursorShape: zoneDrag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                }

                DragHandler {
                    id: zoneDrag
                    target: null
                    xAxis.enabled: false
                    onActiveChanged: {
                        var n = (Flags.worldZones || []).length;
                        if (active) {
                            zoneCol.slide = true;
                            zoneCol.dragFrom = Math.max(0, Math.min(n - 1, Math.floor(centroid.pressPosition.y / zoneCol.rowH)));
                            zoneCol.dragTo = zoneCol.dragFrom;
                            zoneCol.dragDy = 0;
                            root.worldIndex = zoneCol.dragFrom;
                            return;
                        }
                        var from = zoneCol.dragFrom, to = zoneCol.dragTo;
                        /** A real move snaps rows to rest (the list is rebuilt in the new order); a drop in place glides home. */
                        zoneCol.slide = from >= 0 && to !== from ? false : true;
                        zoneCol.dragFrom = -1;
                        zoneCol.dragTo = -1;
                        zoneCol.dragDy = 0;
                        if (from >= 0 && to !== from) {
                            Clocks.moveZoneTo(Flags.worldZones[from], to);
                            root.worldIndex = to;
                        }
                        zoneCol.slide = true;
                    }
                    onCentroidChanged: {
                        if (!active || zoneCol.dragFrom < 0)
                            return;
                        var n = (Flags.worldZones || []).length;
                        var lo = -zoneCol.dragFrom * zoneCol.rowH, hi = (n - 1 - zoneCol.dragFrom) * zoneCol.rowH;
                        zoneCol.dragDy = Math.max(lo, Math.min(hi, centroid.position.y - centroid.pressPosition.y));
                        zoneCol.dragTo = Math.max(0, Math.min(n - 1, Math.round(zoneCol.dragFrom + zoneCol.dragDy / zoneCol.rowH)));
                    }
                }

                Repeater {
                    id: worldRepeater
                    model: Flags.worldZones || []

                    WorldRow {
                        id: zoneRow
                        required property string modelData
                        required property int index
                        city: Clocks.cityOf(modelData)
                        sub: {
                            var c = root.countryOf(modelData);
                            var d = root.zoneSub(modelData);
                            return c.length ? c + " · " + d : d;
                        }
                        time: root.zoneTime(modelData)
                        removable: true
                        focused: root.worldIndex === index
                        lifted: zoneCol.dragFrom === index
                        z: lifted ? 10 : 0
                        scale: lifted ? 1.02 : 1
                        Behavior on scale {
                            NumberAnimation {
                                duration: Motion.fast
                                easing.type: Easing.OutCubic
                            }
                        }
                        transform: Translate {
                            y: zoneCol.offsetFor(zoneRow.index)
                            Behavior on y {
                                enabled: zoneCol.slide && zoneCol.dragFrom !== zoneRow.index
                                NumberAnimation {
                                    duration: 160
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }
                        onHovered: if (zoneCol.dragFrom < 0)
                            root.worldIndex = index
                        onRemoved: Clocks.removeZone(modelData)
                    }
                }
            }

            Item {
                width: parent.width
                height: 8 * root.s
            }

            /** "+ Add city": a dashed row, or the search field with its results. */
            Item {
                id: addRow
                visible: !root.searching
                width: parent.width
                height: visible ? 34 * root.s : 0
                readonly property bool focused: root.worldIndex === root.worldCount - 1

                HoverHandler {
                    onHoveredChanged: if (hovered)
                        root.worldIndex = root.worldCount - 1
                }

                Canvas {
                    anchors.fill: parent
                    property color stroke: Qt.alpha(Theme.vermLit, (addArea.containsMouse || addRow.focused) ? 0.7 : 0.36)
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
                        text: "Add city"
                        color: Theme.vermLit
                        font.family: Theme.font
                        font.pixelSize: 11 * root.s
                        font.weight: Font.DemiBold
                        font.letterSpacing: 0.5 * root.s
                    }
                }

                MouseArea {
                    id: addArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openSearch()
                }
            }

            Column {
                visible: root.searching
                width: parent.width
                spacing: 4 * root.s

                /** Indented so the seam sits in its column just left of the box. */
                Rectangle {
                    id: searchBox
                    x: 14 * root.s
                    width: parent.width - 14 * root.s
                    height: 28 * root.s
                    radius: 8 * root.s
                    color: Theme.frameBg
                    border.width: 1
                    border.color: searchField.activeFocus ? Qt.alpha(Theme.vermLit, 0.45) : Theme.hairSoft

                    TextField {
                        id: searchField
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
                        placeholderText: "City or country, e.g. Paris, Japan"
                        placeholderTextColor: Theme.faint
                        selectByMouse: true
                        selectionColor: Theme.verm
                        onTextEdited: {
                            root.results = Clocks.search(text, 6);
                            root.searchIndex = 0;
                        }
                        onAccepted: root.pickResult(root.searchIndex)
                        Keys.onEscapePressed: root.closeSearch()
                    }
                }

                Text {
                    visible: searchField.text.trim().length > 0 && root.results.length === 0
                    leftPadding: 12 * root.s
                    text: "No matching time zone"
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 10.5 * root.s
                }

                Repeater {
                    model: root.results

                    Rectangle {
                        id: res
                        required property var modelData
                        required property int index
                        readonly property bool current: root.searchIndex === index
                        x: 14 * root.s
                        width: parent.width - 14 * root.s
                        height: 30 * root.s
                        radius: 8 * root.s
                        color: res.current ? Qt.alpha(Theme.onGlow, 0.14) : (resArea.containsMouse ? Theme.frameBg : "transparent")

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 12 * root.s
                            anchors.verticalCenter: parent.verticalCenter
                            text: res.modelData.city
                            color: Theme.cream
                            font.family: Theme.font
                            font.pixelSize: 11.5 * root.s
                            font.weight: Font.DemiBold
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 12 * root.s
                            anchors.verticalCenter: parent.verticalCenter
                            text: res.modelData.country
                            color: Theme.faint
                            font.family: Theme.font
                            font.pixelSize: 10 * root.s
                        }
                        MouseArea {
                            id: resArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.searchIndex = res.index
                            onClicked: root.pickResult(res.index)
                        }
                    }
                }

                Hint {
                    text: "↑ ↓ choose  ·  Enter add  ·  Esc cancel"
                }
            }

            Hint {
                visible: !root.searching
                text: "Drag to reorder  ·  ↑ ↓ move  ·  Ctrl ↑ ↓ reorder  ·  Delete remove"
            }
        }
    }
}
