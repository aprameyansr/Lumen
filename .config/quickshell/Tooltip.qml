pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import "Singletons"

// Delayed hover hint. The control owns pointer input and supplies the show state.
Item {
    id: root

    property real s: 1
    property string title: ""
    property string desc: ""
    property bool show: false
    property string placement: "above"
    property real pointerOffset: 0

    readonly property bool below: placement === "below"
    readonly property real pointerH: 5 * s
    readonly property real gap: 5 * s

    property bool armed: false

    width: bubble.width
    height: bubble.height + pointerH
    z: 20

    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: below ? undefined : parent.top
    anchors.bottomMargin: below ? 0 : gap
    anchors.top: below ? parent.bottom : undefined
    anchors.topMargin: below ? gap : 0

    visible: armed || opacity > 0.01
    opacity: armed ? 1 : 0
    Behavior on opacity {
        NumberAnimation {
            duration: root.armed ? Motion.standard : Motion.fast
        }
    }

    Timer {
        id: delay
        interval: 470
        onTriggered: root.armed = true
    }
    onShowChanged: {
        if (show) {
            delay.restart();
        } else {
            delay.stop();
            armed = false;
        }
    }

    Rectangle {
        id: bubble
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: root.below ? undefined : parent.top
        anchors.bottom: root.below ? parent.bottom : undefined
        width: Math.max(titleText.implicitWidth, descText.implicitWidth) + 22 * root.s
        height: column.implicitHeight + 14 * root.s
        radius: 9 * root.s
        border.width: 1
        border.color: Theme.frameBorder
        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: Theme.cardTop
            }
            GradientStop {
                position: 1.0
                color: Theme.cardBot
            }
        }

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Theme.shadow
            shadowBlur: 0.6
            shadowVerticalOffset: 4 * root.s
        }
    }

    Column {
        id: column
        anchors.centerIn: bubble
        spacing: 2 * root.s

        Text {
            id: titleText
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.title
            color: Theme.cream
            font.family: Theme.font
            font.pixelSize: 11 * root.s
            font.weight: Font.Bold
        }
        Text {
            id: descText
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.desc.length > 0
            text: root.desc
            color: Theme.subtle
            font.family: Theme.font
            font.pixelSize: 10 * root.s
        }
    }

    Canvas {
        width: 11 * root.s
        height: root.pointerH
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: root.pointerOffset
        anchors.top: root.below ? parent.top : undefined
        anchors.bottom: root.below ? undefined : parent.bottom
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.fillStyle = Theme.cardBot;
            ctx.beginPath();
            if (root.below) {
                ctx.moveTo(0, height);
                ctx.lineTo(width, height);
                ctx.lineTo(width / 2, 0);
            } else {
                ctx.moveTo(0, 0);
                ctx.lineTo(width, 0);
                ctx.lineTo(width / 2, height);
            }
            ctx.closePath();
            ctx.fill();
        }
    }
}
