pragma ComponentBehavior: Bound

import QtQuick
import "Singletons"

PillSurface {
    id: root

    mTop: 14
    mLeft: 16
    mRight: 16
    mBottom: 12

    implicitHeight: content.implicitHeight
    onActiveChanged: if (active)
        Battery.refreshHardware()

    ameForm: "seam"
    amePoint: {
        void root.width;
        void root.height;
        void meter.x;
        void meter.y;
        void chargeCard.y;
        return meter.mapToItem(root, meter.width * Battery.frac, meter.height / 2);
    }

    Column {
        id: content
        width: parent.width
        spacing: 10 * root.s

        SettingsHeader {
            s: root.s
            glyph: "蓄"
            title: "Battery"
            showAction: false
        }

        Rectangle {
            id: chargeCard
            width: parent.width
            height: charge.implicitHeight + 22 * root.s
            radius: 10 * root.s
            color: Theme.frameBg
            border.color: Theme.frameBorder
            border.width: 1

            Column {
                id: charge
                anchors.centerIn: parent
                width: parent.width - 24 * root.s
                spacing: 9 * root.s

                Item {
                    width: parent.width
                    height: chargeLevel.implicitHeight

                    Text {
                        id: chargeLevel
                        anchors.verticalCenter: parent.verticalCenter
                        text: Battery.present ? Battery.pct + "%" : "—"
                        color: Battery.present && Battery.low ? Theme.vermLit : Battery.charging ? Theme.flameGlow : Theme.cream
                        font.family: Theme.font
                        font.pixelSize: 40 * root.s
                        font.weight: Font.Bold
                        font.letterSpacing: -root.s
                        font.features: { "tnum": 1 }
                    }

                    Column {
                        anchors.left: chargeLevel.right
                        anchors.leftMargin: 8 * root.s
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3 * root.s

                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignRight
                            text: Battery.present ? Battery.stateLabel : "Charge unavailable"
                            color: Battery.charging ? Theme.flameGlow : Theme.cream
                            font.family: Theme.font
                            font.pixelSize: 10 * root.s
                            font.weight: Font.Bold
                            font.capitalization: Font.AllUppercase
                            font.letterSpacing: 0.8 * root.s
                        }

                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignRight
                            visible: Battery.hasTime
                            text: Battery.timeStr + (Battery.charging ? " to full" : " remaining")
                            color: Theme.subtle
                            font.family: Theme.font
                            font.pixelSize: 11 * root.s
                        }
                    }
                }

                Rectangle {
                    id: meter
                    width: parent.width
                    height: 4 * root.s
                    radius: height / 2
                    color: Theme.threadBg

                    Rectangle {
                        width: parent.width * Battery.frac
                        height: parent.height
                        radius: parent.radius
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop {
                                position: 0
                                color: Battery.charging ? Theme.vermLit : Theme.vermDeep
                            }
                            GradientStop {
                                position: 1
                                color: Battery.charging ? Theme.flameGlow : Theme.vermLit
                            }
                        }
                    }
                }

                StatRow {
                    visible: Math.abs(Battery.rateW) >= 0.05
                    label: "Rate"
                    value: (Battery.rateW > 0 ? "+" : "−") + Math.abs(Battery.rateW).toFixed(1) + " W"
                    valueColor: Battery.charging ? Theme.flameGlow : Theme.cream
                }

                StatRow {
                    visible: Battery.capacityWh >= 1
                    label: "Full charge capacity"
                    value: Battery.capacityWh.toFixed(1) + " Wh"
                }
            }
        }

        Text {
            text: "Properties"
            color: Theme.subtle
            font.family: Theme.font
            font.pixelSize: 9 * root.s
            font.weight: Font.Bold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.1 * root.s
        }

        Column {
            width: parent.width

            Repeater {
                model: [
                    ["Battery Health", Battery.health],
                    ["Design Capacity", Battery.designCapacity],
                    ["Charge Cycles", Battery.chargeCycles],
                    ["Technology", Battery.technology],
                    ["Manufacturer", Battery.manufacturer],
                    ["Model Name", Battery.modelName],
                    ["Device", Battery.deviceName]
                ]

                StatRow {
                    required property var modelData

                    height: 25 * root.s
                    label: modelData[0]
                    value: modelData[1]

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Theme.hairSoft
                    }
                }
            }
        }
    }

    component StatRow: Item {
        id: stat

        required property string label
        required property string value
        property color valueColor: Theme.cream

        width: parent.width
        height: Math.max(caption.implicitHeight, reading.implicitHeight)

        Text {
            id: caption
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: stat.label
            color: Theme.subtle
            font.family: Theme.font
            font.pixelSize: 10.5 * root.s
            font.weight: Font.Medium
        }

        Text {
            id: reading
            anchors.left: caption.right
            anchors.leftMargin: 10 * root.s
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
            text: stat.value || "N/A"
            textFormat: Text.PlainText
            color: stat.value ? stat.valueColor : Theme.dim
            font.family: Theme.font
            font.pixelSize: 11 * root.s
            font.weight: Font.DemiBold
            font.features: { "tnum": 1 }
        }
    }
}
