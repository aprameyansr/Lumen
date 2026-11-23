pragma ComponentBehavior: Bound

import QtQuick
import "Singletons"

/**
 * Mini-segmented choice control. `options` is a list of `{ label, value }`; the
 * pill whose value equals `value` lights with a flame tint. Picking a pill emits
 * `picked(value)`; selection keys off the source value, never a child's effective
 * visibility. The host passes `s` for scale.
 */
Rectangle {
    id: seg

    property real s: 1
    property var options: []
    property var value
    property bool keyboardNavigation: false
    property Item hoveredOption: null
    property Item focusedOption: null
    readonly property Item pointedOption: hoveredOption || focusedOption
    signal picked(var value)

    /**
     * When `flushLeft`, the control shifts left by the first option's text inset
     * so that text lines up with x=0 of where the control is placed, rather than
     * the pill edge sitting there.
     */
    property bool flushLeft: false

    readonly property real pad: 1
    readonly property real edgePad: seg.pad + 9 * seg.s

    x: seg.flushLeft ? -seg.edgePad : 0
    width: pills.implicitWidth + 2 * pad
    height: pills.implicitHeight + 2 * pad
    radius: 9 * seg.s
    color: "transparent"

    Row {
        id: pills
        anchors.centerIn: parent
        spacing: 2 * seg.s

        Repeater {
            model: seg.options

            Rectangle {
                id: opt
                required property var modelData
                readonly property bool current: seg.value === modelData.value
                readonly property bool targeted: seg.pointedOption === opt

                activeFocusOnTab: seg.keyboardNavigation
                onActiveFocusChanged: {
                    if (activeFocus)
                        seg.focusedOption = opt;
                    else if (seg.focusedOption === opt)
                        seg.focusedOption = null;
                }
                Keys.onReturnPressed: if (seg.keyboardNavigation) seg.picked(modelData.value)
                Keys.onSpacePressed: if (seg.keyboardNavigation) seg.picked(modelData.value)
                Accessible.role: Accessible.Button
                Accessible.name: modelData.label
                Accessible.onPressAction: seg.picked(modelData.value)

                width: optLabel.implicitWidth + 18 * seg.s
                height: optLabel.implicitHeight + 12 * seg.s
                radius: 8 * seg.s
                color: opt.current ? Qt.alpha(Theme.onGlow, 0.16) : (opt.targeted ? Theme.frameBg : "transparent")
                Behavior on color { ColorAnimation { duration: Motion.fast } }

                Text {
                    id: optLabel
                    anchors.centerIn: parent
                    text: opt.modelData.label
                    color: opt.current ? Theme.cream : Theme.subtle
                    font.family: Theme.font
                    font.pixelSize: 10.5 * seg.s
                    font.weight: Font.Bold
                    font.letterSpacing: 0.3 * seg.s
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: seg.hoveredOption = opt
                    onExited: if (seg.hoveredOption === opt) seg.hoveredOption = null
                    onClicked: seg.picked(opt.modelData.value)
                }
            }
        }
    }
}
