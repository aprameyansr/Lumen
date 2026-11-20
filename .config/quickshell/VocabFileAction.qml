import QtQuick
import "Singletons"

/**
 * A quiet half-width action under the Vocabulary list (Import / Export). Joins
 * the page's row registry like any other row, so hover, arrow keys and Enter
 * reach it and the seam lands on it.
 */
Item {
    id: fa

    required property var page
    property string label: ""
    property bool flip: false
    property bool dim: false

    readonly property real s: fa.page.s
    readonly property bool lit: faArea.containsMouse || fa.page.focusRowItem === fa

    height: 30 * fa.s
    opacity: fa.dim ? 0.45 : 1

    HoverHandler { onHoveredChanged: fa.page.reportRowHover(fa, hovered) }

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 2 * fa.s
        anchors.bottomMargin: 2 * fa.s
        radius: 8 * fa.s
        color: fa.lit ? Theme.frameBg : "transparent"
        Behavior on color { ColorAnimation { duration: Motion.fast } }
    }

    Row {
        anchors.centerIn: parent
        spacing: 6 * fa.s

        GlyphIcon {
            anchors.verticalCenter: parent.verticalCenter
            width: 13 * fa.s
            height: 13 * fa.s
            name: "download"
            rotation: fa.flip ? 180 : 0
            color: fa.lit ? Theme.cream : Theme.iconDim
            stroke: 1.8
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: fa.label
            color: fa.lit ? Theme.cream : Theme.subtle
            font.family: Theme.font
            font.pixelSize: 11 * fa.s
            font.weight: Font.Medium
        }
    }

    MouseArea {
        id: faArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: fa.dim ? Qt.ArrowCursor : Qt.PointingHandCursor
        onClicked: fa.page.activateRow(fa)
    }
}
