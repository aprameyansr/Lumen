pragma ComponentBehavior: Bound

import QtQuick
import "Singletons"

PillSurface {
    id: root

    mTop: 14
    mLeft: 16
    mRight: 16
    mBottom: 14

    property string selectedId: ""
    property string hoveredId: ""
    property bool dragging: false
    readonly property real rowHeight: 37 * s
    implicitHeight: shelfHeader.height + 10 * s + Math.min(7, Math.max(1, FileShelf.entries.length)) * rowHeight + shelfFooter.height

    ameForm: !open ? "off" : hoveredId || selectedId ? "rowseam" : "soul"
    amePoint: {
        void root.width;
        void root.height;
        void files.contentY;
        const id = hoveredId || selectedId;
        const index = FileShelf.entries.findIndex(entry => entry.id === id);
        const item = index >= 0 ? files.itemAtIndex(index) : null;
        return item && item.y >= files.contentY && item.y + item.height <= files.contentY + files.height ? item.mapToItem(root, 4 * s, item.height / 2) : shelfHeader.soulPoint;
    }

    function move(direction) {
        const entries = FileShelf.entries;
        if (!entries.length)
            return false;
        const current = entries.findIndex(entry => entry.id === selectedId);
        const next = current < 0 ? (direction > 0 ? 0 : entries.length - 1) : Math.max(0, Math.min(entries.length - 1, current + direction));
        hoveredId = "";
        selectedId = entries[next].id;
        files.positionViewAtIndex(next, ListView.Contain);
        return true;
    }

    function sizeText(bytes) {
        if (bytes < 1024)
            return bytes + " B";
        if (bytes < 1024 * 1024)
            return (bytes / 1024).toFixed(1) + " KiB";
        return (bytes / (1024 * 1024)).toFixed(1) + " MiB";
    }

    onActiveChanged: {
        if (active)
            FileShelf.refresh();
        else {
            hoveredId = "";
            selectedId = "";
        }
    }

    SettingsHeader {
        id: shelfHeader
        s: root.s
        title: "File shelf"
        glyph: "棚"
        showAction: false
    }

    ListView {
        id: files
        anchors.top: shelfHeader.bottom
        anchors.topMargin: 10 * root.s
        anchors.bottom: shelfFooter.top
        width: parent.width
        clip: true
        interactive: false
        model: FileShelf.entries

        delegate: Item {
            id: row
            required property var modelData
            width: ListView.view.width
            height: root.rowHeight
            Accessible.role: Accessible.ListItem
            Accessible.name: modelData.name

            Rectangle {
                anchors.fill: parent
                anchors.margins: 2 * root.s
                radius: 7 * root.s
                color: root.selectedId === row.modelData.id || root.hoveredId === row.modelData.id ? Theme.frameBg : "transparent"
            }
            Rectangle {
                width: parent.width
                height: 1
                color: Theme.hairSoft

                Rectangle {
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.right: parent.right
                    width: parent.width * removeHeat.hold
                    visible: removeHeat.holding
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop {
                            position: 0.0
                            color: Qt.alpha(Theme.vermLit, 0.15)
                        }
                        GradientStop {
                            position: 1.0
                            color: Theme.vermLit
                        }
                    }
                }
            }

            HeatHold {
                id: removeHeat
                onConfirmed: if (remove.enabled)
                    FileShelf.remove(row.modelData.id)
            }

            Item {
                anchors.left: parent.left
                anchors.right: remove.left
                height: parent.height

                Drag.active: grip.active
                Drag.imageSource: row.modelData.icon || ""
                Drag.imageSourceSize: Qt.size(48, 48)
                Drag.dragType: Drag.Automatic
                Drag.supportedActions: Qt.CopyAction
                Drag.proposedAction: Qt.CopyAction
                Drag.mimeData: ({
                        "text/uri-list": row.modelData.url + "\r\n"
                    })
                Drag.onDragStarted: {
                    root.selectedId = row.modelData.id;
                    root.dragging = true;
                }
                Drag.onDragFinished: root.dragging = false

                DragHandler {
                    id: grip
                    target: null
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.ClosedHandCursor
                }
                HoverHandler {
                    cursorShape: Qt.OpenHandCursor
                    onHoveredChanged: {
                        if (hovered)
                            root.hoveredId = row.modelData.id;
                        else if (root.hoveredId === row.modelData.id)
                            root.hoveredId = "";
                    }
                }
                TapHandler {
                    onTapped: root.selectedId = row.modelData.id
                }

                GlyphIcon {
                    id: fileIcon
                    anchors.left: parent.left
                    anchors.leftMargin: 13 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16 * root.s
                    height: width
                    name: row.modelData.directory ? "folder" : "file"
                    color: Theme.iconDim
                }
                Text {
                    anchors.left: fileIcon.right
                    anchors.leftMargin: 8 * root.s
                    anchors.right: fileSize.left
                    anchors.rightMargin: 8 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.name
                    textFormat: Text.PlainText
                    elide: Text.ElideMiddle
                    color: Theme.cream
                    font.family: Theme.font
                    font.pixelSize: 12 * root.s
                    font.weight: Font.DemiBold
                }
                Text {
                    id: fileSize
                    anchors.right: parent.right
                    anchors.rightMargin: 7 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.directory ? "Folder" : root.sizeText(row.modelData.size)
                    color: Theme.subtle
                    font.family: Theme.font
                    font.pixelSize: 10 * root.s
                    font.features: {
                        "tnum": 1
                    }
                }
            }

            MouseArea {
                id: remove
                anchors.right: parent.right
                anchors.rightMargin: 5 * root.s
                anchors.verticalCenter: parent.verticalCenter
                width: 25 * root.s
                height: width
                enabled: !FileShelf.busy && !root.dragging
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                Accessible.role: Accessible.Button
                Accessible.name: "Hold to remove " + row.modelData.name + " from shelf"
                onPressed: removeHeat.press()
                onReleased: removeHeat.release()
                onCanceled: removeHeat.cancel()
                onEnabledChanged: if (!enabled)
                    removeHeat.cancel()
                onEntered: root.hoveredId = row.modelData.id
                onExited: {
                    removeHeat.cancel();
                    if (root.hoveredId === row.modelData.id)
                        root.hoveredId = "";
                }

                Tooltip {
                    parent: root
                    s: root.s
                    title: "Hold to remove"
                    show: (remove.containsMouse || removeHeat.holding) && controlPoint.y >= files.y && controlPoint.y <= files.y + files.height

                    readonly property point controlPoint: {
                        // mapToItem does not track layout or scroll changes.
                        void remove.x;
                        void remove.y;
                        void files.y;
                        void files.contentY;
                        void row.y;
                        return remove.mapToItem(root, remove.width / 2, remove.height / 2);
                    }

                    anchors.horizontalCenter: undefined
                    anchors.top: undefined
                    anchors.bottom: undefined
                    x: Math.max(0, Math.min(root.width - width, controlPoint.x - width / 2))
                    y: Math.max(0, controlPoint.y - remove.height / 2 - height - gap)
                    pointerOffset: Math.max(12 * s, Math.min(width - 12 * s, controlPoint.x - x)) - width / 2
                }

                GlyphIcon {
                    anchors.centerIn: parent
                    width: 13 * root.s
                    height: width
                    name: "close"
                    color: removeHeat.holding ? Theme.vermLit : remove.containsMouse ? Theme.cream : Theme.faint
                    Behavior on color {
                        ColorAnimation {
                            duration: Motion.fast
                        }
                    }
                }
            }
        }
    }

    WheelScroller {
        anchors.fill: files
        s: root.s
        flick: files
    }

    Text {
        anchors.centerIn: files
        visible: FileShelf.entries.length === 0
        text: FileShelf.busy ? "Reading shelf…" : "Drop files or folders onto the pill"
        color: Theme.subtle
        font.family: Theme.font
        font.pixelSize: 11 * root.s
    }

    Text {
        id: shelfFooter
        anchors.bottom: parent.bottom
        width: parent.width
        height: visible ? 22 * root.s : 0
        verticalAlignment: Text.AlignBottom
        elide: Text.ElideRight
        visible: FileShelf.error.length > 0 || FileShelf.entries.length > 0
        text: FileShelf.error || "Drag a file out to use it"
        textFormat: Text.PlainText
        color: Theme.subtle
        font.family: Theme.font
        font.pixelSize: 10 * root.s
    }
}
