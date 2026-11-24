pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

/**
 * Combined outputs, made on the spot: tick a few outputs (everyone's
 * Bluetooth headphones for a movie) and they play as one. Each combined output
 * is a small PipeWire process running libpipewire-module-combine-stream; it
 * shows up in every app, becomes the default, and delays the quicker devices
 * so everyone hears the same moment. Members are matched by device, so
 * headphones that drop out and reconnect rejoin on their own.
 *
 * Nothing is saved: removing one, or restarting the shell, ends it, and the
 * previous default output comes back.
 */
Singleton {
    id: root

    readonly property string runDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/lumen-combine"

    /** [{ id, name, members: [{ match, label }] }] */
    property var combos: []
    property string prevDefault: ""

    readonly property var nodes: Pipewire.nodes.values

    function nodeName(id) {
        return "lumen_combine_" + id;
    }

    function isCombined(node) {
        return !!node && /^lumen_combine_/.test(node.name || "");
    }

    /** Bluetooth outputs are matched by device, whatever profile suffix they get. */
    function matchFor(node) {
        const n = node.name || "";
        const bt = n.match(/^(bluez_output\.[0-9A-Fa-f_:]+)\.\d+$/);
        return bt ? "~" + bt[1] + ".*" : n;
    }

    function matches(name, match) {
        if (match.charAt(0) !== "~")
            return name === match;
        try {
            return new RegExp("^" + match.slice(1) + "$").test(name);
        } catch (e) {
            return false;
        }
    }

    function memberPresent(m) {
        return root.nodes.some(n => n && n.isSink && !n.isStream && n.audio && root.matches(n.name || "", m.match));
    }

    function presentCount(c) {
        return c.members.filter(m => root.memberPresent(m)).length;
    }

    function confFor(c) {
        const rules = c.members.map(m => '{ media.class = "Audio/Sink" node.name = ' + JSON.stringify(m.match) + ' }').join(" ");
        return "context.properties = { log.level = 0 }\n" + "context.spa-libs = {\n    audio.convert.* = audioconvert/libspa-audioconvert\n    support.* = support/libspa-support\n}\n" + "context.modules = [\n" + "    { name = libpipewire-module-rt args = { } flags = [ ifexists nofail ] }\n" + "    { name = libpipewire-module-protocol-native }\n" + "    { name = libpipewire-module-client-node }\n" + "    { name = libpipewire-module-adapter }\n" + "    { name = libpipewire-module-combine-stream\n" + "      args = {\n" + "        combine.mode = sink\n" + "        node.name = " + JSON.stringify(root.nodeName(c.id)) + "\n" + "        node.description = " + JSON.stringify(c.name) + "\n" + "        combine.latency-compensate = true\n" + "        combine.props = { audio.position = [ FL FR ] }\n" + "        stream.props = { }\n" + "        stream.rules = [ { matches = [ " + rules + " ] actions = { create-stream = { } } } ]\n" + "      }\n" + "    }\n" + "]\n";
    }

    /**
     * Short name for a combined output, as every app lists it: the first word
     * of each device ("OnePlus + Laptop"), repeats counted ("OnePlus ×2"),
     * anything past three summed up ("+2").
     */
    function shortName(labels) {
        const counts = [];
        for (const l of labels) {
            const w = (l || "").trim().split(/\s+/)[0] || "Output";
            const hit = counts.find(c => c.w.toLowerCase() === w.toLowerCase());
            if (hit)
                hit.n++;
            else
                counts.push({
                    w: w,
                    n: 1
                });
        }
        const parts = counts.map(c => c.n > 1 ? c.w + " ×" + c.n : c.w);
        return parts.length > 3 ? parts.slice(0, 3).join(" + ") + " +" + (parts.length - 3) : parts.join(" + ");
    }

    /** The same outputs in any order give the same key. */
    function keyOf(matchList) {
        return matchList.slice().sort().join("|");
    }

    /** A combined output that already plays exactly these outputs, or null. */
    function existing(sinks) {
        const k = root.keyOf(sinks.filter(n => n && !root.isCombined(n)).map(n => root.matchFor(n)));
        return root.combos.find(c => root.keyOf(c.members.map(m => m.match)) === k) || null;
    }

    function nodeOf(c) {
        return c ? (root.nodes.find(n => n && n.name === root.nodeName(c.id)) || null) : null;
    }

    function isDefault(c) {
        return !!c && !!Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.name === root.nodeName(c.id);
    }

    /**
     * Combine these outputs now; the new output becomes the default. The same
     * set again doesn't make a second copy: the existing one is switched to.
     */
    function combine(sinks) {
        const picked = sinks.filter(n => n && !root.isCombined(n));
        if (picked.length < 2)
            return;
        const dup = root.existing(picked);
        if (dup) {
            const node = root.nodeOf(dup);
            if (node)
                Pipewire.preferredDefaultAudioSink = node;
            return;
        }
        const cur = Pipewire.defaultAudioSink;
        if (cur && !root.isCombined(cur))
            root.prevDefault = cur.name;
        const id = Date.now().toString(36);
        root.combos = root.combos.concat([
            {
                id: id,
                name: root.shortName(picked.map(n => n.description || n.nickname || n.name)),
                members: picked.map(n => ({
                            match: root.matchFor(n),
                            label: n.description || n.nickname || n.name
                        }))
            }
        ]);
        root.pendingDefault = id;
    }

    function remove(id) {
        const wasDefault = Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.name === root.nodeName(id);
        root.combos = root.combos.filter(c => c.id !== id);
        if (wasDefault) {
            const back = root.nodes.find(n => n && n.name === root.prevDefault && n.isSink && !n.isStream);
            if (back)
                Pipewire.preferredDefaultAudioSink = back;
        }
    }

    /** Make a new combined output the default as soon as it appears. */
    property string pendingDefault: ""
    readonly property var pendingNode: root.pendingDefault.length ? (root.nodes.find(n => n && n.name === root.nodeName(root.pendingDefault)) || null) : null
    onPendingNodeChanged: {
        if (root.pendingNode) {
            Pipewire.preferredDefaultAudioSink = root.pendingNode;
            root.pendingDefault = "";
        }
    }

    /** One PipeWire process per combined output; removing it from the list ends it. */
    Instantiator {
        model: root.combos
        delegate: Process {
            required property var modelData
            readonly property string conf: root.runDir + "/" + modelData.id + ".conf"
            running: true
            command: ["sh", "-c", "mkdir -p \"$1\" && printf '%s' \"$2\" > \"$3\" && exec pipewire -c \"$3\"", "_", root.runDir, root.confFor(modelData), conf]
            Component.onDestruction: running = false
        }
    }

    /** Combined outputs don't outlive the shell: clear any left by a previous run. */
    Process {
        running: true
        command: ["sh", "-c", "pkill -f 'pipewire -c .*/lumen-(combine|groups)/' ; rm -rf \"$1\"", "_", root.runDir]
    }
}
