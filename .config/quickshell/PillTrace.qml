import QtQuick
import "Singletons"

/**
 * Quiet running signals drawn on the pill's own outline, so a timer or
 * stopwatch never adds numbers or width to the resting pill.
 *
 * Timer: a dim warm line traces the outline from the top centre clockwise and
 * drains as the time runs out, one lap being the whole run. It holds still while
 * paused. When the timer finishes, the full outline pulses once, on whatever
 * shape the pill has at that moment (the critical notification takes over as it
 * fires).
 *
 * Stopwatch: a tiny dot at the top centre that brightens softly once a minute,
 * like a heartbeat.
 *
 * Both show only on the resting pill and fade out as it expands. Every size
 * (inset, corner, stroke, glow, dot) comes from the pill's live geometry and
 * `s`, so the UI scale and corner morphs carry through. Idle cost is nil: the
 * drain repaints only as often as the line moves about half a pixel, and the
 * heartbeat is a single-shot timer armed for the next minute.
 */
Item {
    id: trace

    property real s: 1
    property real radius: 0
    property bool rest: false

    anchors.fill: parent

    readonly property bool timerShown: trace.rest && !Clocks.tmIdle
    readonly property bool dotShown: trace.rest && Clocks.swRunning

    // ── timer outline ──

    property real frac: 1
    property real pulse: 0

    /** Outline geometry shared by the paint and the repaint pacing. */
    readonly property real lw: 1.4 * trace.s
    readonly property real inset: trace.lw / 2 + 0.5
    readonly property real r: Math.max(0, Math.min(trace.radius - trace.inset, (trace.height - 2 * trace.inset) / 2, (trace.width - 2 * trace.inset) / 2))
    readonly property real perimeter: {
        var w = trace.width - 2 * trace.inset, h = trace.height - 2 * trace.inset;
        return Math.max(0, 2 * (w - 2 * trace.r) + 2 * (h - 2 * trace.r) + 2 * Math.PI * trace.r);
    }

    function sync() {
        trace.frac = Clocks.tmFracAt(Date.now());
        canvas.requestPaint();
    }

    onTimerShownChanged: sync()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()
    onRadiusChanged: canvas.requestPaint()
    onPulseChanged: canvas.requestPaint()

    Connections {
        target: Flags
        function onTmEndChanged() {
            trace.sync();
        }
        function onTmLeftChanged() {
            trace.sync();
        }
        function onTmTotalChanged() {
            trace.sync();
        }
    }

    /** Repaint about every half pixel of drain, between 30 fps and once a second. */
    Timer {
        repeat: true
        triggeredOnStart: true
        running: trace.timerShown && Clocks.tmRunning
        interval: Math.max(33, Math.min(1000, trace.perimeter > 0 ? Flags.tmTotal / (trace.perimeter * 2) : 1000))
        onTriggered: trace.sync()
    }

    SequentialAnimation {
        id: pulseAnim
        NumberAnimation {
            target: trace
            property: "pulse"
            to: 1
            duration: 220
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: trace
            property: "pulse"
            to: 0
            duration: 1100
            easing.type: Easing.InOutSine
        }
    }

    Connections {
        target: Clocks
        function onFinished() {
            pulseAnim.restart();
        }
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        opacity: trace.timerShown || trace.pulse > 0 ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity {
            NumberAnimation {
                duration: Motion.standard
                easing.type: Motion.easeStandard
            }
        }

        /** Rounded-rect outline from the top centre, clockwise. */
        function outline(ctx) {
            var i = trace.inset, r = trace.r, w = width, h = height;
            ctx.beginPath();
            ctx.moveTo(w / 2, i);
            ctx.lineTo(w - i - r, i);
            ctx.arcTo(w - i, i, w - i, i + r, r);
            ctx.lineTo(w - i, h - i - r);
            ctx.arcTo(w - i, h - i, w - i - r, h - i, r);
            ctx.lineTo(i + r, h - i);
            ctx.arcTo(i, h - i, i, h - i - r, r);
            ctx.lineTo(i, i + r);
            ctx.arcTo(i, i, i + r, i, r);
            ctx.lineTo(w / 2, i);
        }

        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            if (width <= 0 || height <= 0)
                return;
            ctx.lineCap = "round";

            if (trace.timerShown && trace.frac > 0) {
                const len = trace.frac * trace.perimeter;
                ctx.setLineDash([len, trace.perimeter + 1]);
                outline(ctx);
                ctx.shadowColor = Qt.alpha(Theme.vermLit, 0.5);
                ctx.shadowBlur = 5 * trace.s;
                ctx.lineWidth = trace.lw;
                ctx.strokeStyle = Qt.alpha(Theme.vermLit, 0.42);
                ctx.stroke();
            }

            if (trace.pulse > 0) {
                ctx.setLineDash([]);
                outline(ctx);
                ctx.shadowColor = Qt.alpha(Theme.flameGlow, 0.8 * trace.pulse);
                ctx.shadowBlur = 10 * trace.s;
                ctx.lineWidth = trace.lw * 1.2;
                ctx.strokeStyle = Qt.alpha(Theme.flameGlow, 0.75 * trace.pulse);
                ctx.stroke();
            }
        }
    }

    // ── stopwatch heartbeat ──

    property real beat: 0

    /** Arm for the next whole stopwatch minute. */
    function armBeat() {
        beatTimer.stop();
        if (!trace.dotShown)
            return;
        beatTimer.interval = Math.max(50, 60000 - (Clocks.swElapsedAt(Date.now()) % 60000));
        beatTimer.start();
    }

    onDotShownChanged: armBeat()

    Connections {
        target: Flags
        function onSwStartChanged() {
            trace.armBeat();
        }
        function onSwAccumChanged() {
            trace.armBeat();
        }
    }

    Timer {
        id: beatTimer
        onTriggered: {
            beatAnim.restart();
            trace.armBeat();
        }
    }

    /**
     * Heartbeat as a ripple: the dot holds its size and only glows a little
     * brighter, while two thin rings flow outward from it one after the other,
     * widening and fading like a drop landing on water.
     */
    property real ring1: 0
    property real ring2: 0

    ParallelAnimation {
        id: beatAnim
        SequentialAnimation {
            NumberAnimation {
                target: trace
                property: "beat"
                to: 1
                duration: 600
                easing.type: Easing.InOutSine
            }
            NumberAnimation {
                target: trace
                property: "beat"
                to: 0
                duration: 2400
                easing.type: Easing.InOutSine
            }
        }
        SequentialAnimation {
            PropertyAction {
                target: trace
                property: "ring1"
                value: 0
            }
            NumberAnimation {
                target: trace
                property: "ring1"
                to: 1
                duration: 2800
                easing.type: Easing.OutQuad
            }
            PropertyAction {
                target: trace
                property: "ring1"
                value: 0
            }
        }
        SequentialAnimation {
            PropertyAction {
                target: trace
                property: "ring2"
                value: 0
            }
            PauseAnimation {
                duration: 700
            }
            NumberAnimation {
                target: trace
                property: "ring2"
                to: 1
                duration: 2800
                easing.type: Easing.OutQuad
            }
            PropertyAction {
                target: trace
                property: "ring2"
                value: 0
            }
        }
    }

    Item {
        id: dot
        anchors.horizontalCenter: parent.horizontalCenter
        y: 3 * trace.s
        width: 4.8 * trace.s
        height: width
        opacity: trace.dotShown ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity {
            NumberAnimation {
                duration: Motion.standard
                easing.type: Motion.easeStandard
            }
        }

        Rectangle {
            readonly property real t: trace.ring1
            anchors.centerIn: parent
            width: parent.width * (1 + 4 * t)
            height: width
            radius: width / 2
            color: "transparent"
            border.width: Math.max(0.6, 0.9 * trace.s * (1 - 0.5 * t))
            border.color: Theme.flameGlow
            opacity: t > 0 ? 0.6 * (1 - t) * (1 - t) : 0
        }
        Rectangle {
            readonly property real t: trace.ring2
            anchors.centerIn: parent
            width: parent.width * (1 + 4 * t)
            height: width
            radius: width / 2
            color: "transparent"
            border.width: Math.max(0.6, 0.9 * trace.s * (1 - 0.5 * t))
            border.color: Theme.flameGlow
            opacity: t > 0 ? 0.6 * (1 - t) * (1 - t) : 0
        }

        /** The dot itself: steady size, 75% at rest, full at the beat. */
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Theme.flameGlow
            opacity: 0.75 + 0.25 * trace.beat
        }
    }
}
