pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "Singletons"

PillSurface {
    id: detail

    mTop: 14
    mLeft: 16
    mRight: 16
    mBottom: 16

    required property string page

    ameForm: open ? "soul" : "off"
    amePoint: header.soulPoint

    readonly property bool network: page === "net"
    readonly property bool storage: page === "disk"
    readonly property bool cpu: page === "cpu"
    readonly property bool memory: page === "mem"
    readonly property bool swap: page === "swap"
    readonly property bool swapEnabled: Sysmon.swapTotalGb > 0
    readonly property bool graphics: page === "gpu"
    readonly property var squirrel: DesktopEntries.applications.values.find(entry => entry.id === "lumen-squirreldisk")
    readonly property string deviceName: cpu ? (Sysmon.cpuProperties.name || "")
        : graphics ? (Sysmon.gpuProperties.name || Sysmon.gpuDevice.name || "")
        : network ? Sysmon.netInterface : storage ? (Sysmon.volume.model || "") : ""
    readonly property real peakReceive: Math.max(0, ...Sysmon.receiveHistory)
    readonly property real peakSend: Math.max(0, ...Sysmon.sendHistory)
    readonly property var properties: {
        const p = Sysmon.cpuProperties;
        const g = Sysmon.gpuProperties;
        const r = Sysmon.gpuReadings;
        const m = Sysmon.memoryProperties;
        const n = Sysmon.adapter;
        const d = Sysmon.volume;
        if (cpu)
            return [
                ["Max frequency", frequency(p.maxMhz)], ["Logical cores", p.logical],
                ["Physical cores", p.physical], ["Sockets", p.sockets],
                ["Uptime", elapsed(Sysmon.uptimeSeconds)], ["Virtualization", p.virtualization],
                ["Architecture", p.architecture]
            ];
        if (memory)
            return [
                ["Slots used", m.populated == null ? "" : m.populated + " of " + m.slots],
                ["Speed", m.speed ? m.speed + " MT/s" : ""], ["Form factor", m.formFactor],
                ["Type", m.type], ["Type detail", m.typeDetail]
            ];
        if (graphics)
            return [
                ["GPU frequency", frequency(r.coreMhz)], ["Video memory frequency", frequency(r.memoryMhz)],
                ["Power usage", watts(r.watts)], ["Manufacturer", g.manufacturer],
                ["PCI slot", g.pci || Sysmon.gpuDevice.pci], ["Driver used", g.driver],
                ["Max power cap", watts(r.cap)], ["Link", r.link]
            ];
        if (network)
            return [
                ["Manufacturer", n.manufacturer], ["Driver used", n.driver], ["Interface", Sysmon.netInterface],
                ["Hardware address", n.address], ["Network name", n.name], ["Link", n.link],
                ["Link speed", n.speed]
            ];
        if (swap)
            return [["Backing", swapEnabled ? Sysmon.swapBacking : ""]];
        if (storage)
            return [
                ["Type", d.type], ["Device", d.device], ["Capacity", bytes(d.capacity, 2)],
                ["Writable", yesNo(d.writable)], ["Removable", yesNo(d.removable)], ["Link", d.link],
                ["Root volume", d.volume], ["Filesystem", d.filesystem]
            ];
        return [];
    }

    implicitHeight: header.height + 9 * s + Math.min(content.implicitHeight, 440 * s)
        + (cleanup.visible ? cleanup.height + 9 * s : 0)

    function bytes(value, decimals) {
        if (value == null)
            return "";
        const units = ["B", "kB", "MB", "GB", "TB", "PB"];
        let i = 0;
        while (value >= 1000 && i < units.length - 1) {
            value /= 1000;
            i++;
        }
        const precision = i ? (value < 10 ? 2 : value < 100 ? 1 : 0) : 0;
        return value.toFixed(decimals ?? precision) + " " + units[i];
    }

    function frequency(mhz) {
        return mhz == null ? "" : mhz >= 1000 ? (mhz / 1000).toFixed(2) + " GHz" : Math.round(mhz) + " MHz";
    }

    function watts(value) {
        return value == null ? "" : value.toFixed(1) + " W";
    }

    function yesNo(value) {
        return value == null ? "" : value ? "Yes" : "No";
    }

    function elapsed(value) {
        if (value < 0)
            return "";
        const days = Math.floor(value / 86400);
        return (days ? days + "d " : "") + Sysmon.pad(Math.floor(value / 3600) % 24)
            + ":" + Sysmon.pad(Math.floor(value / 60) % 60) + ":" + Sysmon.pad(value % 60);
    }

    onActiveChanged: if (active) scroll.contentY = 0

    SettingsHeader {
        id: header
        s: detail.s
        glyph: "系"
        title: detail.cpu ? "CPU" : detail.graphics ? "GPU" : detail.memory ? "Memory"
            : detail.network ? "Network" : detail.swap ? "Swap" : "Storage"
        showBack: true
    }

    Flickable {
        id: scroll
        anchors.top: header.bottom
        anchors.topMargin: 9 * detail.s
        anchors.bottom: cleanup.top
        anchors.bottomMargin: cleanup.visible ? 9 * detail.s : 0
        anchors.left: parent.left
        anchors.right: parent.right
        clip: true
        contentWidth: width
        contentHeight: content.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        WheelScroller { anchors.fill: parent; s: detail.s; flick: scroll }

        Column {
            id: content
            width: scroll.width - (scroll.contentHeight > scroll.height + detail.s ? 7 * detail.s : 0)
            spacing: 10 * detail.s

            Text {
                width: parent.width
                visible: detail.deviceName.length > 0
                text: detail.deviceName
                elide: Text.ElideRight
                textFormat: Text.PlainText
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 13 * detail.s
                font.weight: Font.DemiBold
            }

            Text {
                visible: detail.swap
                text: detail.swapEnabled ? "Swap is on" : "Swap is off"
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 12 * detail.s
                font.weight: Font.DemiBold
            }

            Rectangle {
                width: parent.width
                height: metrics.implicitHeight + 16 * detail.s
                opacity: detail.swap && !detail.swapEnabled ? 0.48 : 1
                radius: 10 * detail.s
                color: Theme.frameBg
                border.color: Theme.frameBorder
                border.width: 1

                Column {
                    id: metrics
                    width: parent.width - 18 * detail.s
                    anchors.centerIn: parent
                    spacing: 6 * detail.s

                    Readout {
                        visible: !detail.network
                        label: detail.storage ? "Root filesystem" : "Usage"
                        value: detail.storage ? (Sysmon.diskTotal > 0 ? Sysmon.diskPct + "%" : "")
                            : detail.cpu ? Sysmon.cpu + "%"
                            : detail.memory ? (Sysmon.memTotalGb > 0 ? Sysmon.memPct + "%" : "")
                            : detail.swap ? Sysmon.swapPct + "%"
                            : Sysmon.gpu >= 0 ? Sysmon.gpu + "%" : ""
                        strong: true
                    }
                    Readout {
                        visible: detail.network
                        label: "↓ Receiving"
                        value: detail.bytes(Sysmon.receiveRate) + "/s · Peak " + detail.bytes(detail.peakReceive) + "/s"
                        strong: true
                    }

                    SysmonHistory {
                        width: parent.width
                        height: (detail.network ? 99 : 90) * detail.s
                        visible: !detail.storage
                        s: detail.s
                        split: detail.network
                        samples: detail.graphics ? 60 : 120
                        primary: detail.network ? Sysmon.receiveHistory : detail.cpu ? Sysmon.cpuHistory
                            : detail.memory ? Sysmon.memoryHistory : detail.swap ? Sysmon.swapUsageHistory : Sysmon.gpuHistory
                        secondary: detail.network ? Sysmon.sendHistory : []
                        ceiling: detail.network ? Math.max(1024, detail.peakReceive, detail.peakSend) : 100
                    }

                    Readout {
                        visible: detail.swap
                        label: "Used / total"
                        value: detail.bytes(Sysmon.swapUsedGb * 1073741824) + " / "
                            + detail.bytes(Sysmon.swapTotalGb * 1073741824)
                    }
                    Readout {
                        visible: detail.swap
                        label: "↑ Swap in"
                        value: detail.bytes(Sysmon.swapInRate) + "/s"
                    }
                    SysmonHistory {
                        visible: detail.swap
                        width: parent.width
                        height: 90 * detail.s
                        s: detail.s
                        split: true
                        primary: Sysmon.swapInHistory
                        secondary: Sysmon.swapOutHistory
                        ceiling: Math.max(1024, ...Sysmon.swapInHistory, ...Sysmon.swapOutHistory)
                    }
                    Readout {
                        visible: detail.swap
                        label: "↓ Swap out"
                        value: detail.bytes(Sysmon.swapOutRate) + "/s"
                        valueColor: detail.swapEnabled ? Theme.vermLit : Theme.dim
                    }
                    Readout {
                        visible: detail.memory
                        label: "Memory"
                        value: Sysmon.memTotalGb > 0
                            ? detail.bytes(Sysmon.memUsedGb * 1073741824, 2) + " / "
                                + detail.bytes(Sysmon.memTotalGb * 1073741824, 2)
                            : ""
                    }
                    Readout {
                        visible: (detail.cpu && Sysmon.cpuTemp >= 0) || (detail.graphics && Sysmon.gpuTemp >= 0)
                        label: "Temperature"
                        value: (detail.cpu ? Sysmon.cpuTemp : Sysmon.gpuTemp) + " °C"
                    }
                    Readout {
                        visible: detail.network
                        label: "↑ Sending"
                        value: detail.bytes(Sysmon.sendRate) + "/s · Peak " + detail.bytes(detail.peakSend) + "/s"
                        valueColor: Theme.vermLit
                        strong: true
                    }
                    Readout {
                        visible: detail.network
                        label: "Total received"
                        value: Sysmon.netInterface ? detail.bytes(Sysmon.received) : ""
                    }
                    Readout {
                        visible: detail.network
                        label: "Total sent"
                        value: Sysmon.netInterface ? detail.bytes(Sysmon.sent) : ""
                    }
                    Readout {
                        visible: detail.graphics && Sysmon.hasVram
                        label: "Video memory"
                        value: Sysmon.vramUsedGb.toFixed(1) + " / " + Sysmon.vramTotalGb.toFixed(1) + " GiB"
                    }
                    Readout {
                        visible: detail.storage
                        label: "Used"
                        value: Sysmon.diskTotal > 0 ? detail.bytes(Sysmon.diskUsed) : ""
                    }
                    Readout {
                        visible: detail.storage
                        label: "Available"
                        value: Sysmon.diskTotal > 0 ? detail.bytes(Sysmon.diskAvailable) : ""
                    }
                    Readout {
                        visible: detail.storage
                        label: "Total"
                        value: Sysmon.diskTotal > 0 ? detail.bytes(Sysmon.diskTotal) : ""
                    }
                }
            }

            Text {
                text: "Properties"
                opacity: detail.swap && !detail.swapEnabled ? 0.48 : 1
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 9 * detail.s
                font.weight: Font.Bold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.1 * detail.s
            }

            Column {
                width: parent.width
                opacity: detail.swap && !detail.swapEnabled ? 0.48 : 1
                Repeater {
                    model: detail.properties
                    Item {
                        required property var modelData

                        width: parent.width
                        height: 25 * detail.s
                        Rectangle {
                            anchors.top: parent.top
                            width: parent.width
                            height: 1
                            color: Theme.hairSoft
                        }
                        Readout {
                            anchors.verticalCenter: parent.verticalCenter
                            label: parent.modelData[0]
                            value: parent.modelData[1] ?? ""
                        }
                    }
                }
            }
        }

        Rectangle {
            z: 1
            parent: scroll
            visible: scroll.contentHeight > scroll.height + detail.s
            x: scroll.width - width
            y: scroll.visibleArea.yPosition * scroll.height
            width: 2 * detail.s
            height: scroll.visibleArea.heightRatio * scroll.height
            radius: width / 2
            color: Theme.hair
        }
    }

    Rectangle {
        id: cleanup
        anchors.bottom: parent.bottom
        width: parent.width
        height: visible ? 32 * detail.s : 0
        radius: 9 * detail.s
        color: cleanupHover.hovered || activeFocus ? Theme.sheen : Theme.frameBg
        border.color: Theme.frameBorder
        border.width: 1
        visible: detail.storage && !!detail.squirrel
        activeFocusOnTab: visible
        Accessible.role: Accessible.Button
        Accessible.name: "Free up space"
        Accessible.onPressAction: launch()

        function launch() {
            // This AppImage's normal FUSE mount is unavailable in the current session.
            Quickshell.execDetached(["env", "APPIMAGE_EXTRACT_AND_RUN=1", ...detail.squirrel.command]);
            detail.requestClose();
        }

        Keys.onReturnPressed: launch()
        Keys.onSpacePressed: launch()
        HoverHandler { id: cleanupHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: cleanup.launch() }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 11 * detail.s
            anchors.verticalCenter: parent.verticalCenter
            text: "Free up space"
            color: Theme.cream
            font.family: Theme.font
            font.pixelSize: 11.5 * detail.s
            font.weight: Font.DemiBold
        }
        GlyphIcon {
            anchors.right: parent.right
            anchors.rightMargin: 10 * detail.s
            anchors.verticalCenter: parent.verticalCenter
            width: 13 * detail.s
            height: width
            name: "chevron-right"
            color: Theme.iconDim
        }
    }

    component Readout: Item {
        id: line
        required property string label
        property string value: ""
        property bool strong: false
        property color valueColor: Theme.cream

        width: parent.width
        height: Math.max(caption.implicitHeight, reading.implicitHeight)
        Text {
            id: caption
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: line.label
            color: Theme.subtle
            font.family: Theme.font
            font.pixelSize: 10.5 * detail.s
            font.weight: Font.Medium
        }
        Text {
            id: reading
            anchors.left: caption.right
            anchors.leftMargin: 10 * detail.s
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
            text: line.value || "—"
            textFormat: Text.PlainText
            color: line.value ? line.valueColor : Theme.dim
            font.family: Theme.font
            font.pixelSize: (line.strong && !detail.network ? 17 : 11) * detail.s
            font.weight: line.strong ? Font.Bold : Font.DemiBold
            font.features: { "tnum": 1 }
        }
    }
}
