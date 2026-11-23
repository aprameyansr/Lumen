import QtQuick
import "Singletons"

/** A chart for the last minute of samples, with a shared baseline for network I/O. */
Canvas {
    id: chart

    property real s: 1
    property var primary: []
    property var secondary: []
    property bool split: false
    property int samples: 120
    property real ceiling: 100
    readonly property color accent: Theme.vermLit
    readonly property color ink: Theme.subtle
    readonly property color grid: Theme.hairSoft

    antialiasing: true

    onPrimaryChanged: requestPaint()
    onSecondaryChanged: requestPaint()
    onSplitChanged: requestPaint()
    onSamplesChanged: requestPaint()
    onCeilingChanged: requestPaint()
    onAccentChanged: requestPaint()
    onInkChanged: requestPaint()
    onGridChanged: requestPaint()
    onSChanged: requestPaint()

    function plot(ctx, values, baseline, span, color, left, right) {
        const step = (right - left) / (samples - 1);
        const start = right - step * (values.length - 1);
        const points = [];
        for (let i = 0; i < values.length; i++) {
            if (values[i] == null)
                continue;
            points.push([start + i * step, baseline - span * Math.min(1, values[i] / ceiling)]);
        }
        if (!points.length)
            return;

        ctx.beginPath();
        ctx.moveTo(points[0][0], points[0][1]);
        for (let i = 1; i < points.length; i++)
            ctx.lineTo(points[i][0], points[i][1]);
        ctx.lineWidth = 1.4 * s;
        ctx.lineJoin = "round";
        ctx.strokeStyle = color;
        ctx.stroke();
        ctx.lineTo(points[points.length - 1][0], baseline);
        ctx.lineTo(points[0][0], baseline);
        ctx.closePath();
        ctx.fillStyle = Qt.alpha(color, 0.16);
        ctx.fill();
    }

    onPaint: {
        const ctx = getContext("2d");
        ctx.clearRect(0, 0, width, height);
        const left = 8 * s;
        const right = width - left;
        const top = 7 * s;
        const bottom = height - top;
        if (right <= left || bottom <= top)
            return;
        const mid = (top + bottom) / 2;
        ctx.lineWidth = 1;
        ctx.strokeStyle = grid;
        ctx.beginPath();
        for (const y of [top, mid, bottom]) {
            ctx.moveTo(left, y);
            ctx.lineTo(right, y);
        }
        for (let i = 1; i < 4; i++) {
            const x = left + (right - left) * i / 4;
            ctx.moveTo(x, top);
            ctx.lineTo(x, bottom);
        }
        ctx.stroke();
        if (split) {
            plot(ctx, primary, mid, mid - top, ink, left, right);
            plot(ctx, secondary, mid, mid - bottom, accent, left, right);
        } else {
            plot(ctx, primary, bottom, bottom - top, accent, left, right);
        }
    }
}
