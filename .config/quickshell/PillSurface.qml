import QtQuick
import "Singletons"

/**
 * Shared morph-surface base for the pill's standard surfaces. Each surface fills
 * the pill body inset by its own margins (scaled by `s`), fades in with the morph
 * as it nears full openness, and is only enabled while open. The host sets `open`,
 * `s` and `morphCloseness`; the surface sets its own `mTop`/`mLeft`/`mRight`/
 * `mBottom` insets. `active` mirrors `open` for the older `onActiveChanged` hooks.
 * `requestClose()` asks the pill to dismiss. Osd and Toast use a different
 * lifecycle and do not derive from this base.
 */
Item {
    id: surface

    property real s: 1
    property bool open: false
    property real morphCloseness: 1

    property real mTop: 0
    property real mLeft: 0
    property real mRight: 0
    property real mBottom: 0

    signal requestClose

    /**
     * Ame anchor. Each surface declares the flame's form and dock point (in
     * surface-local coords) for its open state; the host maps the point into
     * pill space and feeds the active surface's pair to Ame. Left non-readonly
     * so a deriving surface can re-bind. Base default is off at the centre.
     */
    property string ameForm: "off"
    property point amePoint: Qt.point(width / 2, height / 2)

    readonly property bool active: open

    /**
     * Latched true once the open morph has first settled, so a relayout inside
     * (a collapsible snapping its height) never dims the surface for a frame.
     */
    property bool settled: false
    onMorphClosenessChanged: if (open && morphCloseness > 0.92)
        settled = true

    /**
     * Fade-in follows the open morph; the exit is cut loose from it. Before,
     * opacity stayed tied to the shrinking geometry on close, so a surface could
     * dim, reappear or pop as the pill reshaped. Now a close fades out on its own
     * 150 ms curve from wherever it was, with a slight shrink from the top edge.
     */
    readonly property real enter: settled ? 1 : Math.min(gate, Math.pow(morphCloseness, 1.3))
    property real exitFade: 0
    property real lastShown: 0

    /** Held at 0 briefly when this surface replaces another, so the two never cross-fade. Set by the pill. */
    property real gate: 1
    function arrive(swap) {
        gateIn.stop();
        gate = swap ? 0 : 1;
        if (swap)
            gateIn.start();
    }

    SequentialAnimation {
        id: gateIn
        PauseAnimation {
            duration: 90
        }
        NumberAnimation {
            target: surface
            property: "gate"
            to: 1
            duration: 150
            easing.type: Easing.OutCubic
        }
    }

    anchors.fill: parent
    anchors.topMargin: mTop * s
    anchors.leftMargin: mLeft * s
    anchors.rightMargin: mRight * s
    anchors.bottomMargin: mBottom * s

    enabled: open
    opacity: open ? enter : exitFade
    visible: open || opacity > 0.01

    onOpacityChanged: if (open)
        lastShown = opacity
    onOpenChanged: {
        if (open) {
            fadeOut.stop();
        } else {
            settled = false;
            exitFade = lastShown;
            fadeOut.restart();
        }
    }

    transform: Scale {
        readonly property bool closing: !surface.open && !Flags.reduceMotion
        origin.x: surface.width / 2
        origin.y: 0
        xScale: closing ? 0.95 + 0.05 * surface.exitFade / Math.max(0.01, surface.lastShown) : 1
        yScale: xScale
    }

    NumberAnimation {
        id: fadeOut
        target: surface
        property: "exitFade"
        to: 0
        duration: 150
        easing.type: Easing.OutCubic
    }
}
