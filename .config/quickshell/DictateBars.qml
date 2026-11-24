pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import "Singletons"

/**
 * Dictation on the resting pill, drawn into the clock row's own footprint so
 * the pill never changes shape. While talking, ember bars mirrored from the
 * centre chase the live mic level (the same bar build as MusicBars); a locked
 * take adds a small lock at the trailing edge so it is clear letting go of the
 * key will not stop it. Once the take ends the bars fold down into a small
 * spinning arc until the words land, then the clock fades back in.
 */
Item {
    id: root

    property real s: 1
    property real span: 18
    /** Keep the strip as faint dots between takes (the Vocabulary teach view). */
    property bool idle: false

    readonly property bool live: Dictate.live
    readonly property bool working: Dictate.state === "working"
    readonly property bool locked: Dictate.state === "locked"

    Row {
        id: barRow
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: root.locked ? -8.5 * root.s : 0
        Behavior on anchors.horizontalCenterOffset {
            NumberAnimation {
                duration: Motion.standard
                easing.type: Motion.easeStandard
            }
        }
        height: root.span * root.s
        spacing: 2 * root.s
        /** Dim, gently breathing, until the mic actually delivers sound. */
        opacity: root.live ? (Dictate.micHot ? 1 : waitPulse.value) : (root.idle && !root.working ? 0.3 : 0)
        scale: root.live || (root.idle && !root.working) ? 1 : 0.6
        Behavior on opacity {
            NumberAnimation {
                duration: Motion.standard
                easing.type: Motion.easeStandard
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: Motion.standard
                easing.type: Motion.easeStandard
            }
        }

        Repeater {
            model: Dictate.bars

            Rectangle {
                required property int index

                width: 2 * root.s
                radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                height: Math.max(2 * root.s, (Dictate.levels[index] || 0) * root.span * root.s)

                gradient: Gradient {
                    GradientStop {
                        position: 0.0
                        color: Theme.flameGlow
                    }
                    GradientStop {
                        position: 0.5
                        color: Theme.vermLit
                    }
                    GradientStop {
                        position: 1.0
                        color: Theme.flameGlow
                    }
                }

                Behavior on height {
                    NumberAnimation {
                        duration: Motion.fast
                        easing.type: Easing.OutQuad
                    }
                }
            }
        }
    }

    QtObject {
        id: waitPulse
        property real value: 0.35
    }
    SequentialAnimation {
        running: root.live && !Dictate.micHot
        loops: Animation.Infinite
        onStopped: waitPulse.value = 0.35
        NumberAnimation {
            target: waitPulse
            property: "value"
            from: 0.25
            to: 0.55
            duration: 420
            easing.type: Easing.InOutSine
        }
        NumberAnimation {
            target: waitPulse
            property: "value"
            from: 0.55
            to: 0.25
            duration: 420
            easing.type: Easing.InOutSine
        }
    }

    GlyphIcon {
        anchors.left: barRow.right
        anchors.leftMargin: 7 * root.s
        anchors.verticalCenter: parent.verticalCenter
        width: 10 * root.s
        height: 10 * root.s
        name: "lock"
        color: Theme.subtle
        stroke: 1.8
        opacity: root.locked ? 1 : 0
        scale: root.locked ? 1 : 0.6
        Behavior on opacity {
            NumberAnimation {
                duration: Motion.standard
                easing.type: Motion.easeStandard
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: Motion.standard
                easing.type: Easing.OutBack
            }
        }
    }

    Shape {
        id: spinner
        anchors.centerIn: parent
        width: 14 * root.s
        height: 14 * root.s
        preferredRendererType: Shape.CurveRenderer
        opacity: root.working ? 1 : 0
        scale: root.working ? 1 : 0.6
        visible: opacity > 0.01
        Behavior on opacity {
            NumberAnimation {
                duration: Motion.standard
                easing.type: Motion.easeStandard
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: Motion.standard
                easing.type: Motion.easeStandard
            }
        }

        readonly property real lw: 1.7 * root.s

        ShapePath {
            fillColor: "transparent"
            strokeColor: Qt.alpha(Theme.cream, 0.14)
            strokeWidth: spinner.lw
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: spinner.width / 2
                centerY: spinner.height / 2
                radiusX: (spinner.width - spinner.lw) / 2
                radiusY: radiusX
                startAngle: 0
                sweepAngle: 360
            }
        }
        ShapePath {
            fillColor: "transparent"
            strokeColor: Theme.vermLit
            strokeWidth: spinner.lw
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: spinner.width / 2
                centerY: spinner.height / 2
                radiusX: (spinner.width - spinner.lw) / 2
                radiusY: radiusX
                startAngle: -90
                sweepAngle: 100
            }
        }

        RotationAnimation on rotation {
            running: spinner.visible
            from: 0
            to: 360
            duration: 760
            loops: Animation.Infinite
        }
    }
}
