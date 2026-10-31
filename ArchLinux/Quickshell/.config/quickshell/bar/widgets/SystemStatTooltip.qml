pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.core as Core

TooltipWindow {
    id: root

    required property string heading
    required property var rows
    required property Core.Theme theme

    implicitWidth: tooltipContent.implicitWidth + 20
    implicitHeight: tooltipContent.implicitHeight + 16

    Rectangle {
        anchors.fill: parent
        color: root.theme.tooltipBg
        border.color: root.theme.tooltipBorderColor
        border.width: 1
        radius: root.theme.radiusMedium

        ColumnLayout {
            id: tooltipContent

            anchors.centerIn: parent
            spacing: 4

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: root.heading
                textFormat: Text.PlainText
                color: root.theme.tooltipColor
                font {
                    family: root.theme.tooltipFontFamily
                    pixelSize: root.theme.tooltipFontSize
                    bold: true
                }
            }

            Repeater {
                model: root.rows
                delegate: RowLayout {
                    id: statRow
                    required property var modelData
                    readonly property bool showsDots: Number.isSafeInteger(modelData.dotCount) && modelData.dotCount >= 0

                    spacing: 4
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: parent.modelData.label + ":"
                        textFormat: Text.PlainText
                        color: root.theme.tooltipColor
                        font {
                            family: root.theme.tooltipFontFamily
                            pixelSize: root.theme.tooltipFontSize
                        }
                    }
                    Text {
                        visible: !statRow.showsDots
                        text: parent.modelData.value
                        textFormat: Text.PlainText
                        color: root.theme.tooltipColor
                        font {
                            family: root.theme.tooltipFontFamily
                            pixelSize: root.theme.tooltipFontSize
                            bold: true
                        }
                    }
                    RowLayout {
                        visible: statRow.showsDots
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 5

                        Repeater {
                            model: statRow.showsDots ? 5 : 0
                            Rectangle {
                                required property int index
                                Layout.alignment: Qt.AlignVCenter
                                implicitWidth: 7
                                implicitHeight: 7
                                radius: width / 2
                                color: index < statRow.modelData.dotCount ? root.theme.tooltipColor : "transparent"
                                border.color: root.theme.tooltipColor
                                border.width: 1
                            }
                        }
                        Text {
                            visible: statRow.showsDots && statRow.modelData.dotCount > 5
                            text: visible ? "+" + (statRow.modelData.dotCount - 5) : ""
                            color: root.theme.tooltipColor
                            font.family: root.theme.tooltipFontFamily
                            font.pixelSize: root.theme.tooltipFontSize
                            font.bold: true
                        }
                    }
                }
            }
        }
    }
}
