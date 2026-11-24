pragma ComponentBehavior: Bound

import QtQuick
import "Singletons"

Rectangle {
    id: card

    required property real s
    required property string title
    required property string icon
    property string detail: ""
    property bool current: false

    radius: 10 * card.s
    color: current ? Qt.alpha(Theme.onGlow, 0.13) : Theme.frameBg
    border.color: current ? Qt.alpha(Theme.onGlow, 0.43) : Theme.frameBorder
    border.width: 1
    Behavior on color {
        ColorAnimation {
            duration: Motion.fast
        }
    }

    GlyphIcon {
        id: symbol
        anchors.left: parent.left
        anchors.leftMargin: 10 * card.s
        anchors.verticalCenter: parent.verticalCenter
        width: 16 * card.s
        height: width
        name: card.icon
        color: card.current ? Theme.onGlow : Theme.iconDim
    }

    Column {
        anchors.left: symbol.right
        anchors.leftMargin: 7 * card.s
        anchors.right: parent.right
        anchors.rightMargin: 8 * card.s
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3 * card.s

        Text {
            width: parent.width
            text: card.title
            elide: Text.ElideRight
            color: card.current ? Theme.cream : Theme.subtle
            font.family: Theme.font
            font.pixelSize: 11 * card.s
            font.weight: Font.DemiBold
        }
        Text {
            width: parent.width
            visible: text.length > 0
            text: card.detail
            elide: Text.ElideRight
            color: Theme.subtle
            font.family: Theme.font
            font.pixelSize: 9.5 * card.s
        }
    }
}
