pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "Singletons"
import "lib/fuzzy.js" as Fuzzy

PillSurface {
    id: root

    mTop: 14
    mLeft: 16
    mRight: 16
    mBottom: 16
    readonly property real appRowHeight: 34 * s
    implicitHeight: processes ? 460 * s : Math.min(410 * s, header.height + headings.anchors.topMargin + headings.height
        + rows.count * appRowHeight + appList.anchors.bottomMargin + actionBar.height + readingStatus.height)

    readonly property string probe: Quickshell.shellDir + "/lib/sysmon_apps.py"
    readonly property var desktopApps: DesktopEntries.applications.values
        .filter(entry => entry && !entry.noDisplay)
        .map(entry => ({ id: entry.id, name: entry.name, startup: entry.startupClass,
                          icon: entry.icon, command: entry.command }))

    property var apps: ({})
    property bool processes: false
    property string appFilter: ""
    property string appFilterName: ""
    property var filterMembers: []
    readonly property bool canViewProcesses: !processes && available && !!selected
    readonly property Item pointedFilterControl: filterChip.visible && (filterChip.hovered || filterChip.activeFocus)
        ? filterChip : viewProcesses.visible && (viewProcesses.hovered || viewProcesses.activeFocus)
        ? viewProcesses : null
    readonly property string actionSubject: processes ? "Process" : "App"
    readonly property bool sampling: processes ? processSamples.running : sample.running
    property string sortColumn: "memory"
    property bool descending: true
    property string selection: ""
    property string hoverKey: ""
    property string message: ""
    property bool available: false
    property bool menuOpen: false
    property string actionMode: "terminate"
    property var actionCommand: []
    readonly property var selected: apps[selection] || null
    readonly property bool canAct: open && available && !!selected && selected.targets.length > 0 && !action.running

    ameForm: open ? (modeTabs.pointedOption ? "soul"
        : pointedFilterControl || hoverKey || selection ? "rowseam"
        : processes && search.input.activeFocus ? "caret" : "soul") : "off"
    amePoint: {
        void appList.contentY;
        void root.height;
        void root.width;
        const tab = modeTabs.pointedOption;
        if (tab) {
            void modeTabs.x;
            void tab.x;
            return tab.mapToItem(root, tab.width / 2, tab.height + 4 * s);
        }
        const control = pointedFilterControl;
        if (control) {
            void control.x;
            void control.y;
            void control.width;
            return control.mapToItem(root, 4 * s, control.height / 2);
        }
        const key = hoverKey || selection;
        if (!key && processes && search.input.activeFocus) {
            void search.input.width;
            const caret = search.input.cursorRectangle;
            return search.input.mapToItem(root, caret.x + caret.width / 2, caret.y + caret.height / 2);
        }
        for (let i = 0; i < rows.count; i++) {
            if (rows.get(i).appId !== key)
                continue;
            const item = appList.itemAtIndex(i);
            if (item && item.y - appList.contentY >= 0
                && item.y + item.height - appList.contentY <= appList.height)
                return item.mapToItem(root, 4 * s, item.height / 2);
        }
        return header.soulPoint;
    }

    ListModel { id: rows }

    onOpenChanged: {
        if (open) {
            processes = false;
            resetRows();
            resetAppFilter();
            if (!sample.running)
                sample.running = true;
        } else {
            available = false;
            menuOpen = false;
            actionMode = "terminate";
            sample.running = false;
        }
    }

    function resetRows() {
        rows.clear();
        apps = ({});
        available = false;
        selection = "";
        hoverKey = "";
        message = "";
        menuOpen = false;
        actionMode = "terminate";
        search.text = "";
        appList.contentY = 0;
    }

    function resetAppFilter() {
        appFilter = "";
        appFilterName = "";
        filterMembers = [];
    }

    function openAppProcesses() {
        if (canViewProcesses)
            changeView(true, selected);
    }

    function clearAppFilter() {
        resetAppFilter();
        if (available) {
            updateRows(Object.values(apps));
            appList.positionViewAtBeginning();
        }
        search.input.forceActiveFocus();
    }

    function changeView(next, app) {
        if (processes === next)
            return;
        resetRows();
        resetAppFilter();
        if (app) {
            appFilter = app.id;
            appFilterName = app.name;
            filterMembers = app.members;
        }
        sortColumn = "memory";
        descending = true;
        processes = next;
        if (processes)
            search.input.forceActiveFocus();
        else if (!sample.running)
            sample.running = true;
    }

    function copyPid(pid) {
        if (pid <= 0)
            return;
        Quickshell.execDetached(["wl-copy", "--", String(pid)]);
        message = "Copied PID " + pid;
    }

    onCanActChanged: if (!canAct) {
        menuOpen = false;
        actionMode = "terminate";
    }

    function sortBy(column) {
        descending = sortColumn === column ? !descending : true;
        sortColumn = column;
        if (available)
            updateRows(Object.values(apps));
    }

    function columnLabel(column, title) {
        return sortColumn === column ? title + (descending ? " ▾" : " ▴") : title;
    }

    function compareApps(left, right) {
        const a = left[sortColumn];
        const b = right[sortColumn];
        if (a == null || b == null) {
            if (a != null || b != null)
                return a == null ? 1 : -1;
        } else {
            const difference = sortColumn === "name" ? a.localeCompare(b) : a - b;
            if (difference !== 0)
                return descending ? -difference : difference;
        }
        return left.name.localeCompare(right.name) || left.id.localeCompare(right.id);
    }

    function matchesSearch(app) {
        if (appFilter && app.appGroup !== appFilter)
            return false;
        const query = processes ? search.text.trim().toLowerCase() : "";
        if (!query)
            return true;
        return query.split(/\s+/).every(part => Fuzzy.score({
            name: app.name, keywords: [String(app.pid)]
        }, part) < 99);
    }

    function updateRows(result) {
        if (appFilter && appFilter !== "@system" && !result.some(row => row.appGroup === appFilter)) {
            // Window-based app identities can acquire a desktop ID between tabs.
            const previous = new Set(filterMembers);
            const candidates = new Set(result.filter(row => previous.has(row.id) && row.appGroup !== "@system")
                .map(row => row.appGroup));
            if (candidates.size === 1)
                appFilter = candidates.values().next().value;
        }
        if (appFilter)
            filterMembers = result.filter(row => row.appGroup === appFilter).map(row => row.id);
        const next = Object.create(null);
        for (const app of result)
            next[app.id] = app;
        result = result.filter(app => root.matchesSearch(app));
        result.sort((left, right) => root.compareApps(left, right));
        for (let i = 0; i < result.length; i++) {
            const app = result[i];
            let match = i;
            while (match < rows.count && rows.get(match).appId !== app.id)
                match++;
            const properties = { appId: app.id, appName: app.name, appIcon: app.icon || "", processId: app.pid ?? 0,
                                 memory: app.memory, estimated: app.estimated, cpu: app.cpu,
                                 gpu: app.gpu ?? -1 };
            if (match === rows.count)
                rows.insert(i, properties);
            else {
                if (match !== i)
                    rows.move(match, i, 1);
                rows.set(i, properties);
            }
        }
        if (rows.count > result.length)
            rows.remove(result.length, rows.count - result.length);
        if (selection && !next[selection]) {
            // Desktop entry metadata can arrive after the first window-based sample.
            const previous = apps[selection];
            const matches = result.filter(app => app.id !== "@system" && previous
                && previous.roots.some(old => app.roots.some(current => old[0] === current[0] && old[1] === current[1])));
            selection = matches.length === 1 ? matches[0].id : "";
        }
        if (selection && !matchesSearch(next[selection]))
            selection = "";
        apps = next;
        if (!next[hoverKey] || !matchesSearch(next[hoverKey]))
            hoverKey = "";
        available = true;
    }

    function choose(key) {
        if (!apps[key])
            return;
        selection = key;
        menuOpen = false;
        actionMode = "terminate";
        message = "";
    }

    function move(delta) {
        if (!rows.count)
            return false;
        let index = 0;
        while (index < rows.count && rows.get(index).appId !== selection)
            index++;
        index = index === rows.count ? 0 : Math.max(0, Math.min(rows.count - 1, index + delta));
        hoverKey = "";
        choose(rows.get(index).appId);
        appList.positionViewAtIndex(index, ListView.Contain);
        return true;
    }

    function run(mode) {
        if (!canAct)
            return;
        const targets = mode === "kill" ? selected.targets : selected.roots;
        if (!targets.length)
            return;
        actionCommand = ["python3", "-B", probe, mode, JSON.stringify(targets)];
        message = mode === "kill" ? "Sending force quit…" : "Sending quit request…";
        menuOpen = false;
        actionMode = "terminate";
        action.running = true;
    }

    function memoryLabel(kib) {
        return kib >= 1048576 ? (kib / 1048576).toFixed(2) + " GiB" : Math.round(kib / 1024) + " MiB";
    }

    Process {
        id: sample
        command: ["python3", "-B", root.probe, "sample", JSON.stringify(root.desktopApps),
                  Sysmon.gpuDevice.vendor, Dictate.svcDir, Dictate.engine]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!root.open || root.processes)
                    return;
                const data = Sysmon.unpack(text);
                if (Array.isArray(data))
                    root.updateRows(data);
                else
                    root.available = false;
            }
        }
    }

    Timer {
        interval: 1800
        running: root.open && !root.processes
        repeat: true
        onTriggered: if (!sample.running) sample.running = true
    }

    Process {
        id: processSamples
        running: root.open && root.processes
        command: ["python3", "-B", root.probe, "processes", Sysmon.gpuDevice.vendor,
                  JSON.stringify(root.desktopApps), Dictate.svcDir, Dictate.engine]
        stdout: SplitParser {
            onRead: line => {
                if (!root.open || !root.processes)
                    return;
                const data = Sysmon.unpack(line);
                if (Array.isArray(data))
                    root.updateRows(data);
            }
        }
    }

    Process {
        id: action
        command: root.actionCommand
        stdout: StdioCollector {
            onStreamFinished: {
                const result = Sysmon.unpack(text);
                root.message = result && result.sent > 0
                    ? (result.skipped ? "Signal sent to remaining processes" : "Signal sent")
                    : "No live process could be signaled";
                if (root.open && !root.processes && !sample.running)
                    sample.running = true;
            }
        }
    }

    SettingsHeader {
        id: header
        s: root.s
        title: "System"
        glyph: "系"
        showBack: true
    }

    SettingsSeg {
        id: modeTabs
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: header.verticalCenter
        s: root.s
        keyboardNavigation: true
        options: [{label: "Apps", value: false}, {label: "Processes", value: true}]
        value: root.processes
        onPicked: value => root.changeView(value)
    }

    SearchField {
        id: search
        anchors.top: header.bottom
        anchors.topMargin: root.processes ? 8 * root.s : 0
        width: parent.width
        height: root.processes ? 30 * root.s : 0
        s: root.s
        visible: root.processes
        kanji: "探"
        placeholder: "Find a process or PID"
        onMoved: delta => root.move(delta)
        onAccepted: if (!root.selection) root.move(1)
        onDismissed: root.requestClose()
        onTextChanged: if (root.processes && root.available) {
            root.updateRows(Object.values(root.apps));
            appList.positionViewAtBeginning();
        }

        SysmonFilterControl {
            id: filterChip
            s: root.s
            visible: root.appFilter.length > 0
            width: visible ? Math.min(implicitWidth, Math.max(0, search.width - 186 * root.s)) : 0
            label: root.appFilterName
            icon: "close"
            Accessible.name: "Clear " + root.appFilterName + " filter"
            onActivated: root.clearAppFilter()
        }
    }

    component Cell: Text {
        color: Theme.cream
        font.family: Theme.font
        font.pixelSize: 11 * root.s
        font.features: { "tnum": 1 }
        textFormat: Text.PlainText
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
    }

    component Columns: Row {
        id: columns

        property string name: ""
        property string memory: ""
        property string pidText: ""
        property int pidValue: 0
        property string cpu: ""
        property string gpu: ""
        property bool heading: false
        property bool selected: false
        property string icon: ""

        spacing: 8 * root.s

        Item {
            height: parent.height
            width: 21 * root.s

            Image {
                id: appImage
                anchors.centerIn: parent
                width: 16 * root.s
                height: width
                sourceSize: Qt.size(width, height)
                source: columns.icon.startsWith("/") ? "file://" + columns.icon
                    : columns.icon && columns.icon !== "@ai" ? Quickshell.iconPath(columns.icon, true) : ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                visible: status === Image.Ready
            }
            GlyphIcon {
                anchors.centerIn: parent
                width: 15 * root.s
                height: width
                visible: !columns.heading && !appImage.visible
                name: columns.icon === "@ai" ? "sparkles" : "app-window"
                color: Theme.iconDim
            }
        }

        Cell {
            width: parent.width - (21 + 81 + 72 + 54 + 32 + (root.processes ? 84 : 0)) * root.s
            height: parent.height
            text: parent.name
            color: parent.heading ? Theme.subtle : Theme.cream
            font.weight: parent.heading || parent.selected ? Font.Bold : Font.DemiBold
        }
        Cell {
            visible: root.processes
            width: 76 * root.s
            height: parent.height
            text: columns.pidText
            color: pidArea.containsMouse ? Theme.bright : Theme.subtle
            horizontalAlignment: Text.AlignRight

            MouseArea {
                id: pidArea
                anchors.fill: parent
                enabled: columns.pidValue > 0
                hoverEnabled: enabled
                cursorShape: Qt.PointingHandCursor
                Accessible.role: Accessible.Button
                Accessible.name: "Copy process ID " + columns.pidText
                Accessible.onPressAction: root.copyPid(columns.pidValue)
                onClicked: root.copyPid(columns.pidValue)
            }
        }
        Cell {
            width: 81 * root.s
            height: parent.height
            text: parent.memory
            color: parent.heading ? Theme.subtle : Theme.cream
            horizontalAlignment: Text.AlignRight
        }
        Cell {
            width: 72 * root.s
            height: parent.height
            text: parent.cpu
            color: parent.heading ? Theme.subtle : Theme.cream
            horizontalAlignment: Text.AlignRight
        }
        Cell {
            width: 54 * root.s
            height: parent.height
            text: parent.gpu
            color: parent.heading ? Theme.subtle : Theme.cream
            horizontalAlignment: Text.AlignRight
        }
    }

    Columns {
        id: headings
        anchors.top: search.bottom
        anchors.topMargin: 9 * root.s
        x: 10 * root.s
        width: parent.width - 27 * root.s
        height: 26 * root.s
        heading: true
        name: root.columnLabel("name", root.processes ? "Process" : "App name")
        pidText: root.columnLabel("pid", "Process ID")
        memory: root.columnLabel("memory", "Memory")
        cpu: root.columnLabel("cpu", "Processor")
        gpu: root.columnLabel("gpu", "GPU")
    }

    Row {
        anchors.fill: headings

        Repeater {
            model: [{ key: "name", title: root.processes ? "Process" : "App name", width: 0 }]
                .concat(root.processes ? [{ key: "pid", title: "Process ID", width: 84 }] : [])
                .concat([
                    { key: "memory", title: "Memory", width: 89 },
                    { key: "cpu", title: "Processor", width: 80 },
                    { key: "gpu", title: "GPU", width: 62 }
                ])

            MouseArea {
                required property var modelData

                width: modelData.width > 0 ? modelData.width * root.s : headings.width - (231 + (root.processes ? 84 : 0)) * root.s
                height: headings.height
                cursorShape: Qt.PointingHandCursor
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: "Sort by " + modelData.title
                Accessible.onPressAction: root.sortBy(modelData.key)
                Keys.onReturnPressed: root.sortBy(modelData.key)
                Keys.onSpacePressed: root.sortBy(modelData.key)
                onClicked: root.sortBy(modelData.key)
            }
        }
    }

    ListView {
        id: appList
        anchors.top: headings.bottom
        anchors.bottom: actionBar.top
        anchors.bottomMargin: 8 * root.s
        width: parent.width
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: rows

        delegate: Item {
            id: row
            required property string appId
            required property string appName
            required property string appIcon
            required property int processId
            required property real memory
            required property bool estimated
            required property real cpu
            required property real gpu

            width: ListView.view.width
            height: root.appRowHeight
            Accessible.role: Accessible.ListItem
            Accessible.name: appName
            Accessible.onPressAction: root.choose(appId)

            Rectangle {
                anchors.fill: parent
                anchors.margins: 2 * root.s
                radius: 7 * root.s
                color: root.selection === row.appId ? Theme.frameBg : "transparent"
            }
            Rectangle { width: parent.width; height: 1; color: Theme.hairSoft }

            Columns {
                x: 10 * root.s
                width: parent.width - 27 * root.s
                height: parent.height
                name: row.appName
                icon: row.appIcon
                pidText: row.processId > 0 ? String(row.processId) : ""
                pidValue: row.processId
                selected: root.selection === row.appId
                memory: (row.estimated ? "~" : "") + root.memoryLabel(row.memory)
                cpu: row.cpu.toFixed(1) + "%"
                gpu: row.gpu < 0 ? "—" : row.gpu.toFixed(1) + "%"
            }

            HoverHandler {
                cursorShape: Qt.PointingHandCursor
                onHoveredChanged: {
                    if (hovered)
                        root.hoverKey = row.appId;
                    else if (root.hoverKey === row.appId)
                        root.hoverKey = "";
                }
            }
            TapHandler { onTapped: root.choose(row.appId) }
        }
    }

    WheelScroller { anchors.fill: appList; s: root.s; flick: appList }

    Rectangle {
        visible: appList.contentHeight > appList.height
        x: root.width - width
        y: appList.y + appList.visibleArea.yPosition * appList.height
        width: 2 * root.s
        height: appList.visibleArea.heightRatio * appList.height
        radius: width / 2
        color: Theme.hair
    }

    Cell {
        id: readingStatus
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: root.available ? 0 : 23 * root.s
        visible: !root.available
        text: root.sampling ? (root.processes ? "Reading processes…" : "Reading running apps…")
            : (root.processes ? "Process readings unavailable" : "App readings unavailable")
        color: Theme.subtle
    }

    Item {
        id: actionBar
        anchors.bottom: readingStatus.top
        width: parent.width
        height: 37 * root.s

        Rectangle { width: parent.width; height: 1; color: Theme.hair }

        Cell {
            anchors.left: parent.left
            anchors.right: viewProcesses.visible ? viewProcesses.left : actions.left
            anchors.rightMargin: 12 * root.s
            anchors.verticalCenter: actions.verticalCenter
            text: root.message || (root.selected
                ? (root.processes ? "PID " + root.selected.pid : root.selected.count + " processes") + " · " + root.selected.name
                : root.processes ? (root.available && rows.count === 0 ? "No matching processes" : "Select a process")
                : "Select an app")
            color: Theme.subtle
        }

        SysmonFilterControl {
            id: viewProcesses
            s: root.s
            anchors.right: actions.left
            anchors.rightMargin: 8 * root.s
            anchors.verticalCenter: actions.verticalCenter
            visible: !root.processes
            enabled: root.canViewProcesses
            label: "View processes"
            icon: "chevron-right"
            onActivated: root.openAppProcesses()
        }

        Rectangle {
            id: actions
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: 127 * root.s
            height: 30 * root.s
            radius: 8 * root.s
            border.color: Theme.frameBorder
            color: root.menuOpen || primaryHover.hovered || toggleHover.hovered ? Theme.sheen : Theme.frameBg
            enabled: root.canAct
            opacity: enabled ? 1 : 0.46

            Item {
                id: primary
                anchors.left: parent.left
                anchors.right: divider.left
                height: parent.height
                enabled: root.actionMode === "kill" || !!root.selected?.roots.length
                opacity: enabled ? 1 : 0.46
                activeFocusOnTab: enabled
                Accessible.role: Accessible.Button
                Accessible.name: (root.actionMode === "kill" ? "Kill " : "Halt ") + root.actionSubject
                Accessible.onPressAction: root.run(root.actionMode)
                Keys.onReturnPressed: root.run(root.actionMode)
                Keys.onSpacePressed: root.run(root.actionMode)

                Row {
                    anchors.centerIn: parent
                    spacing: 6 * root.s
                    GlyphIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 13 * root.s
                        height: width
                        name: root.actionMode === "kill" ? "close" : "shutdown"
                        color: root.actionMode === "kill" ? Theme.onGlow : Theme.iconDim
                    }
                    Cell {
                        anchors.verticalCenter: parent.verticalCenter
                        text: (root.actionMode === "kill" ? "Kill " : "Halt ") + root.actionSubject
                        font.weight: Font.DemiBold
                    }
                }
                HoverHandler { id: primaryHover; cursorShape: Qt.PointingHandCursor }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.run(root.actionMode)
                }
            }

            Rectangle {
                id: divider
                anchors.right: toggle.left
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: 16 * root.s
                color: Theme.hair
            }

            Item {
                id: toggle
                anchors.right: parent.right
                width: 28 * root.s
                height: parent.height
                activeFocusOnTab: enabled
                Accessible.role: Accessible.Button
                Accessible.name: "Choose app action"
                Accessible.onPressAction: root.menuOpen = !root.menuOpen
                Keys.onReturnPressed: root.menuOpen = !root.menuOpen
                Keys.onSpacePressed: root.menuOpen = !root.menuOpen

                GlyphIcon {
                    anchors.centerIn: parent
                    width: 11 * root.s
                    height: width
                    name: root.menuOpen ? "chevron-down" : "chevron-up"
                    color: Theme.iconDim
                }
                HoverHandler { id: toggleHover; cursorShape: Qt.PointingHandCursor }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.menuOpen = !root.menuOpen
                }
            }
        }

        Rectangle {
            anchors.right: parent.right
            anchors.bottom: actions.top
            anchors.bottomMargin: 6 * root.s
            width: 230 * root.s
            height: menuRows.implicitHeight + 8 * root.s
            radius: 9 * root.s
            color: Theme.cardTop
            border.color: Theme.frameBorder
            visible: root.menuOpen

            QtObject {
                id: menuSurface
                readonly property real s: root.s
                readonly property Item focusRowItem: null

                function reportRowHover(item, hovered) {}

                function activateRow(item) {
                    root.actionMode = item.modelData.mode;
                    root.menuOpen = false;
                }
            }

            Column {
                id: menuRows
                anchors.centerIn: parent
                width: parent.width - 8 * root.s

                Repeater {
                    model: [
                        { name: "Halt " + root.actionSubject, icon: "shutdown",
                          sub: root.processes ? "Ask the process to exit" : "Ask the app to close", mode: "terminate" },
                        { name: "Kill " + root.actionSubject, icon: "close", sub: "Force quit now", mode: "kill" }
                    ]

                    SettingsRow {
                        required property var modelData
                        required property int index

                        surface: menuSurface
                        name: modelData.name
                        sub: modelData.sub
                        icon: modelData.icon
                        captionOnFocus: true
                        clip: true
                        last: index === 1
                        Behavior on height {
                            enabled: root.menuOpen
                            NumberAnimation {
                                duration: Motion.standard
                                easing.type: Motion.easeStandard
                            }
                        }
                        enabled: index !== 0 || !!root.selected?.roots.length
                        opacity: enabled ? 1 : 0.46
                    }
                }
            }
        }
    }
}
