pragma ComponentBehavior: Bound

import QtQuick
import ".." as Desktop
import "../services/OpenAiUsage.js" as Usage

Item {
    id: root

    required property Desktop.Config config
    required property var quotaService
    required property var mouseService
    required property var micService
    required property date currentDate

    implicitHeight: column.implicitHeight
    readonly property real fitScale: Math.max(0, Math.min(1, root.width / 260, root.height / Math.max(1, column.implicitHeight)))
    readonly property var snapshot: root.quotaService?.available ? root.quotaService.snapshot : null
    readonly property bool mouseAvailable: root.mouseService?.available ?? false
    readonly property bool micAvailable: root.micService?.available ?? false

    function resetTime(quotaWindow) {
        if (!Number.isSafeInteger(quotaWindow?.resetAt))
            return "N/A";
        const minutes = Math.ceil((quotaWindow.resetAt - root.currentDate.getTime()) / 60000);
        if (minutes <= 0)
            return "Due";
        const days = Math.floor(minutes / 1440);
        const hours = Math.floor(minutes / 60) % 24;
        return days > 0 ? days + "d " + hours + "h" : hours > 0 ? hours + "h " + minutes % 60 + "m" : minutes + "m";
    }

    Column {
        id: column
        objectName: "statusColumn"
        width: root.width / Math.max(0.001, root.fitScale)
        spacing: 24
        scale: root.fitScale
        transformOrigin: Item.TopLeft

        Column {
            visible: root.config.quotaEnabled
            width: parent.width
            spacing: 8

            Text {
                text: "OPENAI"
                color: root.config.mutedColor
                font.family: root.config.fontFamily
                font.pixelSize: root.config.fontSize - 4
            }
            MeterRow {
                objectName: "quotaWeekly"
                width: parent.width
                config: root.config
                label: "WEEK"
                readonly property var remaining: Usage.remaining(root.snapshot?.weekly ?? null)
                valueText: root.resetTime(root.snapshot?.weekly)
                fraction: remaining === null ? -1 : remaining / 100
                onRefreshRequested: force => root.quotaService?.refresh(force)
            }
            MeterRow {
                objectName: "quotaFiveHour"
                width: parent.width
                config: root.config
                label: "5 HOUR"
                readonly property var remaining: Usage.remaining(root.snapshot?.fiveHour ?? null)
                valueText: root.resetTime(root.snapshot?.fiveHour)
                fraction: remaining === null ? -1 : remaining / 100
                onRefreshRequested: force => root.quotaService?.refresh(force)
            }
        }

        Column {
            visible: root.config.mouseBatteryEnabled
            width: parent.width
            spacing: 8

            Text {
                text: "MOUSE"
                color: root.config.mutedColor
                font.family: root.config.fontFamily
                font.pixelSize: root.config.fontSize - 4
            }
            MeterRow {
                objectName: "mouseBattery"
                width: parent.width
                config: root.config
                label: "BATTERY"
                valueText: root.mouseAvailable ? root.mouseService.percentage + "%" + (root.mouseService.charging ? " +" : "") : "N/A"
                fraction: root.mouseAvailable ? root.mouseService.percentage / 100 : -1
                onRefreshRequested: force => root.mouseService?.refresh(force)
            }
        }

        Column {
            visible: root.config.micBatteryEnabled
            width: parent.width
            spacing: 8

            Text {
                text: "DJI MIC"
                color: root.config.mutedColor
                font.family: root.config.fontFamily
                font.pixelSize: root.config.fontSize - 4
            }
            Repeater {
                model: root.micAvailable ? root.micService.transmitters : [
                    {
                        id: "unavailable",
                        level: null,
                        charging: false
                    }
                ]

                MeterRow {
                    required property var modelData
                    objectName: "mic-" + modelData.id
                    width: column.width
                    config: root.config
                    label: modelData.id === "unavailable" ? "TX" : modelData.id.toUpperCase()
                    valueText: !root.micAvailable ? "N/A" : (modelData.level === null ? "N/A" : modelData.level === 1 ? "FULL" : "L" + modelData.level) + (modelData.charging ? " +" : "")
                    fraction: !root.micAvailable || modelData.level === null ? -1 : (8 - modelData.level) / 7
                    segments: 7
                    onRefreshRequested: force => root.micService?.refresh(force)
                }
            }
        }
    }
}
