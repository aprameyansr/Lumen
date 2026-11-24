pragma ComponentBehavior: Bound

import QtQuick
import "Singletons"

/** Live overview and hardware navigation for the 系 SYSTEM surface. */
PillSurface {
    id: root

    mTop: 14
    mLeft: 16
    mRight: 16
    mBottom: 16

    signal requestDetail(string key)

    property string focusKey: ""
    readonly property var overviewRows: [["apps"], dialKeys, ["net", "disk", "swap"]]
    readonly property Item focusedTarget: targetFor(focusKey)
    implicitHeight: content.implicitHeight

    readonly property var dialKeys: Sysmon.hasGpu ? ["cpu", "gpu", "mem"] : ["cpu", "mem"]
    readonly property var cellKeys: Sysmon.hasVram ? ["net", "disk", "swap", "vram"] : ["net", "disk", "swap"]

    function targetFor(key) {
        if (key === "apps")
            return processes;
        const dialIndex = dialKeys.indexOf(key);
        if (dialIndex >= 0)
            return dialIndex < dials.count ? dials.itemAt(dialIndex) : null;
        const cellIndex = cellKeys.indexOf(key);
        return cellIndex >= 0 && cellIndex < cells.count ? cells.itemAt(cellIndex) : null;
    }

    function move(dx, dy) {
        if (!focusedTarget) {
            focusKey = dialKeys[0];
            return true;
        }

        const row = overviewRows.findIndex(keys => keys.includes(focusKey));
        const keys = overviewRows[row];
        if (dx) {
            const index = Math.max(0, Math.min(keys.length - 1, keys.indexOf(focusKey) + dx));
            focusKey = keys[index];
        } else if (row + dy >= 0 && row + dy < overviewRows.length) {
            const center = focusedTarget.mapToItem(root, focusedTarget.width / 2, 0).x;
            let distance = Infinity;
            let nearest = focusKey;
            for (const key of overviewRows[row + dy]) {
                const candidate = targetFor(key);
                if (!candidate)
                    continue;
                const offset = Math.abs(candidate.mapToItem(root, candidate.width / 2, 0).x - center);
                if (offset < distance) {
                    distance = offset;
                    nearest = key;
                }
            }
            focusKey = nearest;
        }
        return true;
    }

    function activate() {
        if (!focusedTarget)
            return false;
        requestDetail(focusKey);
        return true;
    }

    Connections {
        target: Sysmon
        function onOpenChanged() {
            if (!Sysmon.open)
                root.focusKey = "";
        }
    }

    /**
     * The soul ember rests with the 系 header kanji: the kanji is the lantern,
     * the bead its flame, hovering just above the glyph with its wick rising into
     * it. Anchored to the header rather than the dial row so the ember sits in the
     * same deliberate spot whether three dials or two are shown (the header never
     * changes with GPU presence). With glyphs off the kanji is hidden, so the
     * anchor falls back to the SYSTEM label's left edge, vertically centred on the
     * header, and never floats. Mapped into surface-local space so the host can
     * offset it by the surface origin.
     */
    readonly property point soulPoint: {
        void root.width;
        void root.height;
        if (Flags.showGlyphs)
            return kanji.mapToItem(root, kanji.width / 2, -3 * root.s);
        return sysLabel.mapToItem(root, -8 * root.s, sysLabel.height / 2);
    }

    ameForm: open ? "soul" : "off"
    amePoint: {
        const item = focusedTarget;
        if (!item)
            return soulPoint;
        void item.x;
        void item.y;
        void root.width;
        void root.height;
        return item.mapToItem(root, item.width / 2, item.height + 6 * s);
    }

    component Dial: Item {
        id: dial

        property real arc: 0
        property string big: ""
        property string unit: ""
        property string sub: ""
        property string label: ""
        property bool shrink: false
        property bool selected: false
        property real display: 0
        onArcChanged: display = arc
        Component.onCompleted: display = arc
        onDisplayChanged: face.requestPaint()
        Behavior on display {
            NumberAnimation {
                duration: Math.round(700 * Motion.mult)
                easing.type: Easing.OutCubic
            }
        }

        width: 110 * root.s
        height: 110 * root.s

        Canvas {
            id: face
            anchors.fill: parent
            antialiasing: true

            onPaint: {
                var ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                var cx = width / 2;
                var cy = height / 2;
                var lw = 8 * root.s;
                var r = Math.min(width, height) / 2 - lw / 2 - root.s;
                var start = 135 * Math.PI / 180;
                var full = 270 * Math.PI / 180;
                ctx.lineCap = "round";
                ctx.lineWidth = lw;
                ctx.strokeStyle = Qt.rgba(0.94, 0.88, 0.84, 0.13);
                ctx.beginPath();
                ctx.arc(cx, cy, r, start, start + full, false);
                ctx.stroke();
                var v = Math.max(0, Math.min(100, dial.display));
                if (v > 0.5) {
                    const diag = r * 0.7071;
                    const grad = ctx.createLinearGradient(cx - diag, cy + diag, cx + diag, cy - diag);
                    grad.addColorStop(0, Theme.vermBurn);
                    grad.addColorStop(0.35, Theme.vermBurn);
                    grad.addColorStop(1, Theme.vermLit);
                    ctx.strokeStyle = grad;
                    ctx.beginPath();
                    ctx.arc(cx, cy, r, start, start + full * v / 100, false);
                    ctx.stroke();
                }
            }
        }

        /**
         * The big value owns the dial's exact centre so it reads as the focal
         * number whatever its width, with the label and sub line stacked
         * directly beneath it; centring the value rather than the whole column
         * means a one- or three-digit value never drifts off the eye line.
         */
        Row {
            id: bigRow
            anchors.centerIn: parent
            /** Ring gap is at the bottom, so its optical middle sits above the hole centre; lift the value there. */
            anchors.verticalCenterOffset: -12 * root.s
            spacing: 1 * root.s

            Text {
                id: bigText
                text: dial.big
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: (dial.shrink ? 16 : 20) * root.s
                font.weight: Font.ExtraBold
                font.letterSpacing: -0.5 * root.s
                font.features: {
                    "tnum": 1
                }
            }
            Text {
                anchors.baseline: bigText.baseline
                visible: dial.unit.length > 0
                text: dial.unit
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 11 * root.s
                font.weight: Font.Bold
            }
        }

        Column {
            anchors.top: bigRow.bottom
            anchors.topMargin: 3 * root.s
            anchors.horizontalCenter: bigRow.horizontalCenter
            spacing: 2 * root.s

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 3 * root.s
                Text {
                    text: dial.label
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 8.5 * root.s
                    font.weight: Font.Bold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1 * root.s
                }
                GlyphIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "chevron-right"
                    width: 7 * root.s
                    height: width
                    color: dial.selected ? Theme.cream : Theme.faint
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: dial.sub
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 10.5 * root.s
                font.weight: Font.Bold
                font.features: {
                    "tnum": 1
                }
            }
        }
    }

    Column {
        id: content
        anchors.top: parent.top
        anchors.left: parent.left
        width: parent.width
        spacing: 0

        Item {
            width: parent.width
            height: 30 * root.s

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 9 * root.s

                Text {
                    id: kanji
                    anchors.verticalCenter: headerLabels.verticalCenter
                    anchors.verticalCenterOffset: (sysLabel.height - headerLabels.height) / 2
                    visible: Flags.showGlyphs
                    text: "系"
                    color: Theme.cream
                    font.family: Theme.fontJp
                    font.weight: Font.Medium
                    font.pixelSize: 16 * root.s
                }
                Column {
                    id: headerLabels
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: 1.5 * root.s
                    spacing: 2 * root.s

                    Text {
                        id: sysLabel
                        text: "SYSTEM"
                        color: Theme.subtle
                        font.family: Theme.font
                        font.pixelSize: 12 * root.s
                        font.weight: Font.DemiBold
                        font.letterSpacing: 1.8 * root.s
                    }
                    Text {
                        text: Sysmon.uptime
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 8.5 * root.s
                        font.weight: Font.Bold
                        font.letterSpacing: 0.7 * root.s
                        font.features: {
                            "tnum": 1
                        }
                    }
                }
            }

            SysmonTarget {
                id: processes
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: processesLabel.implicitWidth + 8 * root.s
                height: parent.height
                key: "apps"
                onTargeted: root.focusKey = key
                onActivated: {
                    root.focusKey = key;
                    root.requestDetail(key);
                }

                Row {
                    id: processesLabel
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5 * root.s

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "PROCESSES"
                        color: root.focusKey === "apps" ? Theme.cream : Theme.subtle
                        font.family: Theme.font
                        font.pixelSize: 10 * root.s
                        font.weight: Font.DemiBold
                        font.letterSpacing: 1.3 * root.s
                    }
                    GlyphIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "chevron-right"
                        width: 10 * root.s
                        height: width
                        color: root.focusKey === "apps" ? Theme.cream : Theme.iconDim
                    }
                }
            }
        }

        Item {
            width: 1
            height: 16 * root.s
        }

        Item {
            width: parent.width
            height: 110 * root.s

            Repeater {
                id: dials
                model: root.dialKeys

                SysmonTarget {
                    id: tile
                    required property int index
                    required property var modelData
                    key: modelData
                    onTargeted: root.focusKey = key
                    onActivated: {
                        root.focusKey = key;
                        root.requestDetail(key);
                    }
                    readonly property int val: key === "cpu" ? Sysmon.cpu : key === "gpu" ? Sysmon.gpu : Sysmon.memPct

                    x: root.dialKeys.length > 1 ? index * (parent.width - width) / (root.dialKeys.length - 1) : (parent.width - width) / 2

                    width: 110 * root.s
                    height: parent.height

                    Dial {
                        anchors.fill: parent
                        selected: root.focusKey === tile.key
                        arc: Math.max(0, tile.val)
                        big: tile.key === "mem" ? Sysmon.memUsedGb.toFixed(1) : tile.val < 0 ? "—" : "" + tile.val
                        unit: tile.key === "mem" || tile.val < 0 ? "" : "%"
                        shrink: tile.key !== "mem" && tile.val >= 100
                        label: tile.key
                        sub: tile.key === "cpu" ? (Sysmon.cpuTemp >= 0 ? Sysmon.cpuTemp + "°" : "") : tile.key === "gpu" ? (Sysmon.gpuTemp >= 0 ? Sysmon.gpuTemp + "°" : "") : "/ " + Sysmon.memTotalGb.toFixed(0) + " GB"
                    }
                }
            }
        }

        Item {
            width: 1
            height: 18 * root.s
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.hair
        }

        Item {
            width: 1
            height: 13 * root.s
        }

        Item {
            width: parent.width
            height: 30 * root.s

            Repeater {
                id: cells
                model: root.cellKeys

                SysmonTarget {
                    id: cell
                    required property int index
                    required property var modelData
                    key: modelData
                    onTargeted: root.focusKey = key
                    onActivated: {
                        root.focusKey = key;
                        root.requestDetail(key);
                    }
                    drillDown: key !== "vram"

                    width: parent.width / root.cellKeys.length
                    height: parent.height
                    x: index * width

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.topMargin: 2 * root.s
                        anchors.bottomMargin: 2 * root.s
                        height: parent.height - 4 * root.s
                        width: 1
                        visible: cell.index > 0
                        color: Theme.hairSoft
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 6 * root.s

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 3 * root.s
                            Text {
                                text: cell.key === "net" ? "Net · " + (Math.max(Sysmon.netDown, Sysmon.netUp) >= 1 ? "MB/S" : "KB/S") : cell.key === "disk" ? "Disk · %" : cell.key === "swap" ? "Swap · GB" : "VRAM · GB"
                                color: Theme.faint
                                font.family: Theme.font
                                font.pixelSize: 8 * root.s
                                font.weight: Font.Bold
                                font.capitalization: Font.AllUppercase
                                font.letterSpacing: 0.9 * root.s
                            }
                            GlyphIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: cell.drillDown
                                name: "chevron-right"
                                width: 7 * root.s
                                height: width
                                color: root.focusKey === cell.key ? Theme.cream : Theme.faint
                            }
                        }

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 8 * root.s
                            visible: cell.key === "net"

                            Text {
                                text: "↓" + (Math.max(Sysmon.netDown, Sysmon.netUp) >= 1 ? Sysmon.netDown.toFixed(1) : (Sysmon.netDown * 1024).toFixed(1))
                                color: Theme.cream
                                font.family: Theme.font
                                font.pixelSize: 13 * root.s
                                font.weight: Font.ExtraBold
                                font.features: {
                                    "tnum": 1
                                }
                            }
                            Text {
                                text: "↑" + (Math.max(Sysmon.netDown, Sysmon.netUp) >= 1 ? Sysmon.netUp.toFixed(1) : (Sysmon.netUp * 1024).toFixed(1))
                                color: Theme.vermLit
                                font.family: Theme.font
                                font.pixelSize: 13 * root.s
                                font.weight: Font.ExtraBold
                                font.features: {
                                    "tnum": 1
                                }
                            }
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: cell.key !== "net"
                            text: cell.key === "disk" ? "" + Sysmon.diskPct : cell.key === "swap" ? Sysmon.swapUsedGb.toFixed(1) : Sysmon.vramUsedGb.toFixed(1) + " / " + Sysmon.vramTotalGb.toFixed(0)
                            color: Theme.cream
                            font.family: Theme.font
                            font.pixelSize: 13 * root.s
                            font.weight: Font.ExtraBold
                            font.features: {
                                "tnum": 1
                            }
                        }
                    }
                }
            }
        }
    }
}
