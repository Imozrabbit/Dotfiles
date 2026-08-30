import QtQuick
import QtQuick.Layouts

import qs.core as Core

RowLayout {
    id: root
    spacing: 0

    required property int cpuUsage
    required property string cpuModel
    required property int cpuClockMhz
    required property int cpuTemperatureC
    required property int gpuUsage
    required property int gpuClockMhz
    required property int gpuTemperatureC
    required property string gpuName
    required property int memUsage
    required property real memTotalKib
    required property real memUsedKib
    required property real memAvailableKib
    required property real swapTotalKib
    required property real swapUsedKib
    required property Core.Theme theme

    property bool cpuTooltipVisible: false
    property bool gpuTooltipVisible: false
    property bool memTooltipVisible: false

    function formatClock(mhz) {
        return mhz >= 0 ? (mhz / 1000).toFixed(2) + " GHz" : "N/A";
    }

    function formatTemperature(celsius) {
        return celsius >= 0 ? celsius + "°C" : "N/A";
    }

    function formatGib(kib) {
        return kib >= 0 ? (kib / 1048576).toFixed(1) + " GiB" : "N/A";
    }

    function formatMemoryPair(usedKib, totalKib) {
        return usedKib >= 0 && totalKib >= 0 ? (usedKib / 1048576).toFixed(1) + " / " + (totalKib / 1048576).toFixed(1) + " GiB" : "N/A";
    }

    Rectangle {
        id: cpuContainer
        implicitWidth: cpuUsage_text.implicitWidth + 24
        implicitHeight: cpuUsage_text.implicitHeight + 4
        radius: root.theme.radiusMedium
        color: root.theme.cpuUsageBg

        Rectangle {
            anchors {
                top: parent.top
                right: parent.right
                bottom: parent.bottom
            }
            width: parent.radius
            color: parent.color
        }

        Rectangle {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: root.theme.systemUsageFontSize
            color: root.theme.networkSeparatorColor
        }

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

        HoverHandler {
            id: cpuHover

            onHoveredChanged: {
                if (hovered) {
                    cpuTooltipDelay.restart();
                } else {
                    cpuTooltipDelay.stop();
                    root.cpuTooltipVisible = false;
                }
            }
        }

        Timer {
            id: cpuTooltipDelay

            interval: 300
            repeat: false
            onTriggered: root.cpuTooltipVisible = cpuHover.hovered
        }

        SystemStatTooltip {
            visible: root.cpuTooltipVisible
            anchorItem: cpuContainer
            heading: root.cpuModel
            rows: [
                {
                    label: "Clock",
                    value: root.formatClock(root.cpuClockMhz)
                },
                {
                    label: "Temperature",
                    value: root.formatTemperature(root.cpuTemperatureC)
                }
            ]
            theme: root.theme
        }
    }

    Rectangle {
        id: gpuContainer

        implicitWidth: gpuUsageText.implicitWidth + 24
        implicitHeight: gpuUsageText.implicitHeight + 4
        color: root.theme.gpuUsageBg

        Rectangle {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: root.theme.systemUsageFontSize
            color: root.theme.networkSeparatorColor
        }

        Text {
            id: gpuUsageText

            anchors.centerIn: parent
            text: "󰢮 " + (root.gpuUsage >= 0 ? root.gpuUsage + "%" : "N/A")
            color: root.gpuUsage >= 90 ? root.theme.overloadColor : root.theme.gpuUsageColor
            font {
                family: root.theme.fontFamily
                pixelSize: root.theme.systemUsageFontSize
                bold: true
            }
        }

        HoverHandler {
            id: gpuHover

            onHoveredChanged: {
                if (hovered) {
                    gpuTooltipDelay.restart();
                } else {
                    gpuTooltipDelay.stop();
                    root.gpuTooltipVisible = false;
                }
            }
        }

        Timer {
            id: gpuTooltipDelay

            interval: 300
            repeat: false
            onTriggered: root.gpuTooltipVisible = gpuHover.hovered
        }

        SystemStatTooltip {
            visible: root.gpuTooltipVisible
            anchorItem: gpuContainer
            heading: root.gpuName
            rows: [
                {
                    label: "Clock",
                    value: root.gpuClockMhz >= 0 ? root.gpuClockMhz + " MHz" : "N/A"
                },
                {
                    label: "Temperature",
                    value: root.formatTemperature(root.gpuTemperatureC)
                }
            ]
            theme: root.theme
        }
    }

    Rectangle {
        id: memContainer
        implicitWidth: memUsage_text.implicitWidth + 25
        implicitHeight: memUsage_text.implicitHeight + 4
        color: root.theme.memUsageBg
        radius: root.theme.radiusMedium

        Rectangle {
            anchors {
                top: parent.top
                left: parent.left
                bottom: parent.bottom
            }
            width: parent.radius
            color: parent.color
        }

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

        HoverHandler {
            id: memHover

            onHoveredChanged: {
                if (hovered) {
                    memTooltipDelay.restart();
                } else {
                    memTooltipDelay.stop();
                    root.memTooltipVisible = false;
                }
            }
        }

        Timer {
            id: memTooltipDelay

            interval: 300
            repeat: false
            onTriggered: root.memTooltipVisible = memHover.hovered
        }

        SystemStatTooltip {
            visible: root.memTooltipVisible
            anchorItem: memContainer
            heading: "Memory"
            rows: [
                {
                    label: "Used",
                    value: root.formatMemoryPair(root.memUsedKib, root.memTotalKib)
                },
                {
                    label: "Available",
                    value: root.formatGib(root.memAvailableKib)
                },
                {
                    label: "Swap",
                    value: root.formatMemoryPair(root.swapUsedKib, root.swapTotalKib)
                }
            ]
            theme: root.theme
        }
    }
}
