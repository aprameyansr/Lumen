pragma ComponentBehavior: Bound

import QtQuick

/** Shared pointer and keyboard focus target for a System dial or readout. */
Item {
    id: control

    required property string key
    property bool drillDown: true
    signal targeted
    signal activated

    activeFocusOnTab: drillDown
    Accessible.role: drillDown ? Accessible.Button : Accessible.StaticText
    Accessible.name: ({
            cpu: "CPU",
            gpu: "GPU",
            mem: "Memory",
            net: "Network",
            disk: "Storage",
            swap: "Swap",
            vram: "VRAM",
            apps: "Processes"
        })[key] ?? ""
    Accessible.onPressAction: if (drillDown)
        activated()
    onActiveFocusChanged: if (activeFocus && drillDown)
        targeted()

    HoverHandler {
        enabled: control.drillDown
        cursorShape: Qt.PointingHandCursor
        onHoveredChanged: if (hovered)
            control.targeted()
    }
    MouseArea {
        anchors.fill: parent
        enabled: control.drillDown
        cursorShape: Qt.PointingHandCursor
        onClicked: control.activated()
    }
}
