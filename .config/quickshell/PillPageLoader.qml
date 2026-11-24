import QtQuick

Loader {
    required property var host

    property real pageWidth: 392 * host.s
    property real heightPadding: 29 * host.s
    property size morphSize: Qt.size(pageWidth, ((item as Item)?.implicitHeight ?? 0) + heightPadding)
    property bool showAme: true
    property bool preload: false

    active: false
    visible: !host.criticalToast
    anchors.fill: parent
}
