pragma ComponentBehavior: Bound

import QtQuick
import "Singletons"

Rectangle {
    id: button
    required property real s
    required property string label
    required property string icon
    readonly property bool hovered: hover.hovered
    signal activated()

    implicitWidth: Math.ceil(labelText.implicitWidth + labelText.anchors.leftMargin
        + labelText.anchors.rightMargin + symbol.width + symbol.anchors.rightMargin)
    width: implicitWidth
    height: 29 * button.s
    radius: 8 * button.s
    border.color: Theme.frameBorder
    color: hovered || activeFocus ? Theme.sheen : Theme.frameBg
    opacity: enabled ? 1 : 0.46
    activeFocusOnTab: enabled
    Accessible.role: Accessible.Button
    Accessible.name: label
    Accessible.onPressAction: activated()
    Keys.onReturnPressed: activated()
    Keys.onSpacePressed: activated()

    Text {
        id: labelText
        color: Theme.cream
        font.family: Theme.font
        font.pixelSize: 11 * button.s
        textFormat: Text.PlainText
        elide: width < implicitWidth ? Text.ElideRight : Text.ElideNone
        anchors.left: parent.left
        anchors.leftMargin: 12 * button.s
        anchors.right: symbol.left
        anchors.rightMargin: 6 * button.s
        anchors.verticalCenter: parent.verticalCenter
        text: button.label
        font.weight: Font.DemiBold
    }
    GlyphIcon {
        id: symbol
        anchors.right: parent.right
        anchors.rightMargin: 9 * button.s
        anchors.verticalCenter: parent.verticalCenter
        width: 11 * button.s
        height: width
        name: button.icon
        color: Theme.iconDim
    }
    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: button.activated()
    }
}
