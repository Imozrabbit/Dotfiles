import QtQuick
import QtQuick.Layouts

import qs.core as Core

RowLayout {
    id: root
    spacing: 4

    required property int cpuUsage
    required property int memUsage
    required property Core.Theme theme

    Rectangle {
        id: cpuContainer
        implicitWidth: cpuUsage_text.implicitWidth + 24
        implicitHeight: cpuUsage_text.implicitHeight + 4
        radius: root.theme.radiusMedium
        color: root.theme.cpuUsageBg
        Text {
            id: cpuUsage_text
            anchors.centerIn: parent
            text: " " + root.cpuUsage + "%"
            color: root.cpuUsage >= 90 ? root.theme.overloadColor : root.theme.cpuUsageColor
            font {
                family: root.theme.fontFamily
                pixelSize: root.theme.systemUsageFontSize
                bold: true
            }
        }
    }

    Rectangle {
        id: memContainer
        implicitWidth: memUsage_text.implicitWidth + 25
        implicitHeight: memUsage_text.implicitHeight + 4
        color: root.theme.memUsageBg
        radius: root.theme.radiusMedium
        Text {
            id: memUsage_text
            anchors.centerIn: parent
            text: " " + root.memUsage + "%"
            color: root.memUsage >= 90 ? root.theme.overloadColor : root.theme.memUsageColor
            font {
                family: root.theme.fontFamily
                pixelSize: root.theme.systemUsageFontSize
                bold: true
            }
        }
    }
}
