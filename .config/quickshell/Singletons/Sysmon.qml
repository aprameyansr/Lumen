pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/** Open-session samples shared by the overview and its hardware pages. */
Singleton {
    id: root

    property bool open: false
    property string page: ""
    readonly property string probe: Quickshell.shellDir + "/lib/sysmon.py"

    property var hardware: ({})
    property var volume: ({})
    property var adapter: ({})
    property var gpuProperties: ({})
    property var gpuReadings: ({})
    readonly property var cpuProperties: hardware.cpu || ({})
    readonly property var memoryProperties: hardware.memory || ({})
    readonly property var gpuDevice: hardware.gpu || ({})
    readonly property bool hasGpu: !!gpuDevice.vendor
    readonly property bool hasVram: vramTotalGb > 0
    readonly property real vramUsedGb: gpuReadings.vramUsed ?? 0
    readonly property real vramTotalGb: gpuReadings.vramTotal ?? 0

    property int cpu: 0
    property int cpuTemp: -1
    property int gpu: -1
    property int gpuTemp: -1
    property real memUsedGb: 0
    property real memTotalGb: 0
    property int memPct: 0
    property real swapUsedGb: 0
    property real swapTotalGb: 0
    readonly property int swapPct: swapTotalGb > 0 ? Math.round(100 * swapUsedGb / swapTotalGb) : 0
    property string swapBacking: ""
    property var swapUsageHistory: []
    property var swapInHistory: []
    property var swapOutHistory: []
    property real swapInRate: 0
    property real swapOutRate: 0
    property var previousSwap: null

    property real netDown: 0
    property real netUp: 0
    property string netInterface: ""
    property real received: 0
    property real sent: 0
    property real receiveRate: 0
    property real sendRate: 0

    property int uptimeSeconds: -1
    readonly property string uptime: uptimeSeconds < 0 ? "" : "UP " + Math.floor(uptimeSeconds / 86400) + "D " + pad(Math.floor(uptimeSeconds / 3600) % 24) + ":" + pad(Math.floor(uptimeSeconds / 60) % 60)
    property real diskUsed: 0
    property real diskAvailable: 0
    property real diskTotal: 0
    readonly property int diskPct: diskUsed + diskAvailable > 0 ? Math.ceil(100 * diskUsed / (diskUsed + diskAvailable)) : 0

    property var cpuHistory: []
    property var memoryHistory: []
    property var gpuHistory: []
    property var receiveHistory: []
    property var sendHistory: []

    property real prevCpuTotal: 0
    property real prevCpuIdle: 0
    property real prevNetTime: 0
    property var prevInterfaces: ({})
    property var prevGpu: null
    property string gpuPage: ""
    property string slowPage: ""
    property bool slowPending: false

    function pad(n) {
        return String(n).padStart(2, "0");
    }

    function push(history, value, limit) {
        return history.slice(1 - limit).concat([value]);
    }

    function unpack(text) {
        try {
            return JSON.parse(text);
        } catch (error) {
            return null;
        }
    }

    function refreshGpu() {
        if (open && hasGpu && !gpuProc.running) {
            gpuPage = page;
            gpuProc.running = true;
        }
    }

    function refreshSlow() {
        if (slowProc.running) {
            slowPending = true;
            return;
        }
        slowPage = page;
        slowPending = false;
        slowProc.running = true;
    }

    function setInterface(name) {
        if (netInterface === name)
            return;
        netInterface = name;
        adapter = ({});
        receiveHistory = [];
        sendHistory = [];
        received = 0;
        sent = 0;
        receiveRate = 0;
        sendRate = 0;
    }

    function sampleNetwork(interfaces) {
        const now = Date.now();
        const dt = (now - prevNetTime) / 1000;
        let down = 0;
        let up = 0;
        for (const [name, counters] of Object.entries(interfaces)) {
            const previous = prevInterfaces[name];
            if (!previous || dt <= 0)
                continue;
            down += Math.max(0, counters[0] - previous[0]) / dt;
            up += Math.max(0, counters[1] - previous[1]) / dt;
        }
        netDown = down / 1048576;
        netUp = up / 1048576;
        const current = interfaces[netInterface];
        const previous = prevInterfaces[netInterface];
        if (current) {
            received = current[0];
            sent = current[1];
            if (previous && dt > 0) {
                receiveRate = Math.max(0, received - previous[0]) / dt;
                sendRate = Math.max(0, sent - previous[1]) / dt;
                receiveHistory = push(receiveHistory, receiveRate, 120);
                sendHistory = push(sendHistory, sendRate, 120);
            }
        }
        prevInterfaces = interfaces;
        prevNetTime = now;
    }

    // Intel's busiest engine gives one GPU-wide reading without adding overlapping work.
    function intelLoad(sample) {
        const previous = prevGpu;
        prevGpu = sample;
        if (!previous || sample.time <= previous.time)
            return null;
        const elapsed = sample.time - previous.time;
        const engines = {};
        for (const [id, counters] of Object.entries(sample.clients)) {
            const last = previous.clients[id] || {};
            for (const [key, value] of Object.entries(counters)) {
                let engine;
                let utilization;
                if (key.startsWith("cycles-")) {
                    engine = key.slice(7);
                    const clock = "total-cycles-" + engine;
                    const delta = counters[clock] - last[clock];
                    if (!(delta > 0))
                        continue;
                    utilization = (value - (last[key] ?? 0)) / delta;
                } else if (key.startsWith("engine-") && !key.startsWith("engine-capacity-")) {
                    engine = key.slice(7);
                    if (counters["total-cycles-" + engine] !== undefined && counters["cycles-" + engine] !== undefined)
                        continue;
                    utilization = (value - (last[key] ?? 0)) / elapsed;
                } else {
                    continue;
                }
                const capacity = Math.max(1, counters["engine-capacity-" + engine] ?? 1);
                engines[engine] = (engines[engine] || 0) + Math.max(0, utilization) / capacity;
            }
        }
        return Math.min(100, Math.round(100 * Math.max(0, ...Object.values(engines))));
    }

    function sampleSwap(inPages, outPages) {
        const now = Date.now();
        const previous = previousSwap;
        previousSwap = swapTotalGb > 0 ? {
            time: now,
            input: inPages,
            output: outPages
        } : null;
        if (!previousSwap) {
            swapInRate = 0;
            swapOutRate = 0;
            return;
        }
        const dt = previous ? (now - previous.time) / 1000 : 0;
        if (dt <= 0 || !hardware.pageSize)
            return;
        swapInRate = Math.max(0, inPages - previous.input) * hardware.pageSize / dt;
        swapOutRate = Math.max(0, outPages - previous.output) * hardware.pageSize / dt;
        swapInHistory = push(swapInHistory, swapInRate, 120);
        swapOutHistory = push(swapOutHistory, swapOutRate, 120);
    }

    onOpenChanged: {
        if (!open)
            return;
        cpuHistory = [];
        memoryHistory = [];
        swapUsageHistory = [];
        swapInHistory = [];
        swapOutHistory = [];
        swapInRate = 0;
        swapOutRate = 0;
        previousSwap = null;
        gpuHistory = [];
        receiveHistory = [];
        sendHistory = [];
        prevCpuTotal = 0;
        prevNetTime = 0;
        prevInterfaces = ({});
        prevGpu = null;
        fastProc.running = true;
        refreshGpu();
        refreshSlow();
    }
    onPageChanged: {
        if (open) {
            refreshSlow();
            if (page === "gpu")
                refreshGpu();
        }
    }

    Process {
        running: true
        command: ["python3", "-B", root.probe, "detect"]
        stdout: StdioCollector {
            onStreamFinished: {
                const data = root.unpack(text);
                if (data)
                    root.hardware = data;
                Qt.callLater(root.refreshGpu);
            }
        }
    }

    Process {
        id: fastProc
        command: ["sh", "-c", "read -r _ a b c d e f g h _ < /proc/stat; echo \"CPU $((a+b+c+d+e+f+g+h)) $((d+e))\"; " + "awk '/^MemTotal:/{mt=$2}/^MemAvailable:/{ma=$2}/^SwapTotal:/{st=$2}/^SwapFree:/{sf=$2}END{print \"MEM\",mt,ma,st,sf}' /proc/meminfo; " + "awk '$1==\"pswpin\"{i=$2}$1==\"pswpout\"{o=$2}END{print \"SWAP\",i+0,o+0}' /proc/vmstat; " + "awk -F: 'NR>2{gsub(/^[ \\t]+|[ \\t]+$/, \"\", $1); if($1!=\"lo\"){n=split($2,a,/[ \\t]+/); k=(a[1]==\"\"); print \"NET\", $1, a[1+k], a[9+k]}}' /proc/net/dev; " + "if [ -n \"$1\" ] && [ -r \"$1\" ]; then echo \"TMP $(cat \"$1\")\"; else echo 'TMP -'; fi", "_", root.hardware.sensor || ""]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!root.open)
                    return;
                const interfaces = Object.create(null);
                for (const line of text.trim().split("\n")) {
                    const p = line.trim().split(/\s+/);
                    if (p[0] === "CPU") {
                        const total = Number(p[1]);
                        const idle = Number(p[2]);
                        const dt = total - root.prevCpuTotal;
                        if (root.prevCpuTotal > 0 && dt > 0) {
                            const di = idle - root.prevCpuIdle;
                            root.cpu = Math.max(0, Math.min(100, Math.round(100 * (dt - di) / dt)));
                            root.cpuHistory = root.push(root.cpuHistory, root.cpu, 120);
                        }
                        root.prevCpuTotal = total;
                        root.prevCpuIdle = idle;
                    } else if (p[0] === "MEM") {
                        const [total, available, swapTotal, swapFree] = p.slice(1).map(Number);
                        root.memTotalGb = total / 1048576;
                        root.memUsedGb = (total - available) / 1048576;
                        root.memPct = total > 0 ? Math.round(100 * (total - available) / total) : 0;
                        if (total > 0)
                            root.memoryHistory = root.push(root.memoryHistory, root.memPct, 120);
                        if (root.swapTotalGb > 0 && swapTotal === 0) {
                            root.swapUsageHistory = [];
                            root.swapInHistory = [];
                            root.swapOutHistory = [];
                        }
                        root.swapTotalGb = swapTotal / 1048576;
                        root.swapUsedGb = (swapTotal - swapFree) / 1048576;
                        if (swapTotal > 0)
                            root.swapUsageHistory = root.push(root.swapUsageHistory, root.swapPct, 120);
                    } else if (p[0] === "SWAP") {
                        root.sampleSwap(Number(p[1]), Number(p[2]));
                    } else if (p[0] === "NET") {
                        interfaces[p[1]] = [Number(p[2]), Number(p[3])];
                    } else if (p[0] === "TMP") {
                        const temp = Number(p[1]);
                        root.cpuTemp = isFinite(temp) ? Math.round(temp / 1000) : -1;
                    }
                }
                root.sampleNetwork(interfaces);
            }
        }
    }

    Process {
        id: gpuProc
        command: ["python3", "-B", root.probe, "gpu", root.gpuDevice.vendor || "", root.gpuDevice.path || "", root.gpuDevice.pci || "", root.gpuDevice.card || "", root.gpuPage]
        stdout: StdioCollector {
            onStreamFinished: {
                const data = root.unpack(text);
                if (!data || !root.open)
                    return;
                root.gpuReadings = data;
                const usage = data.clients ? root.intelLoad(data) : data.usage;
                root.gpu = usage == null ? -1 : Math.max(0, Math.min(100, Math.round(usage)));
                root.gpuTemp = data.temp == null ? -1 : Math.round(data.temp);
                root.gpuHistory = root.push(root.gpuHistory, root.gpu < 0 ? null : root.gpu, 60);
            }
        }
    }

    Process {
        id: slowProc
        command: ["python3", "-B", root.probe, "slow", root.slowPage, root.gpuDevice.pci || "", root.gpuDevice.path || ""]
        stdout: StdioCollector {
            onStreamFinished: {
                const data = root.unpack(text);
                if (!data || !root.open)
                    return;
                root.diskUsed = data.used;
                root.diskAvailable = data.available;
                root.diskTotal = data.total;
                root.uptimeSeconds = data.uptime == null ? -1 : Math.floor(data.uptime);
                root.setInterface(data.netInterface);
                if (data.net)
                    root.adapter = data.net;
                if (data.swapBacking !== undefined)
                    root.swapBacking = data.swapBacking;
                if (data.disk)
                    root.volume = data.disk;
                if (data.gpu)
                    root.gpuProperties = data.gpu;
            }
        }
        onExited: if (root.open && root.slowPending)
            Qt.callLater(root.refreshSlow)
    }

    Timer {
        interval: 500
        running: root.open
        repeat: true
        onTriggered: if (!fastProc.running)
            fastProc.running = true
    }

    Timer {
        interval: 1000
        running: root.open && root.hasGpu
        repeat: true
        onTriggered: root.refreshGpu()
    }

    Timer {
        interval: 1000
        running: root.open
        repeat: true
        onTriggered: root.refreshSlow()
    }
}
