pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell

import qs.core as Core

PopupWindow {
    id: root

    required property Item anchorItem
    required property string heading
    required property var rows
    required property Core.Theme theme

    color: "transparent"
    grabFocus: false

    implicitWidth: tooltipContent.implicitWidth + 20
    implicitHeight: tooltipContent.implicitHeight + 16

    anchor.item: root.anchorItem
    anchor.rect.x: 0
    anchor.rect.y: -8
    anchor.rect.width: root.anchorItem.width
    anchor.rect.height: root.anchorItem.height
    anchor.edges: Edges.Top
    anchor.gravity: Edges.Top

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
                    required property var modelData

                    spacing: 4
                    Text {
                        text: parent.modelData.label + ":"
                        color: root.theme.tooltipColor
                        font {
                            family: root.theme.tooltipFontFamily
                            pixelSize: root.theme.tooltipFontSize
                        }
                    }
                    Text {
                        text: parent.modelData.value
                        color: root.theme.tooltipColor
                        font {
                            family: root.theme.tooltipFontFamily
                            pixelSize: root.theme.tooltipFontSize
                            bold: true
                        }
                    }
                }
            }
        }
    }
}
