pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "services" as Services
import "ui" as Ui

ShellRoot {
    id: root

    property Config config: Config {}
    readonly property bool hasTargetScreen: Quickshell.screens.some(screen => screen.name === root.config.targetScreenName)
    readonly property Services.DjiMicBattery micService: micLoader.item as Services.DjiMicBattery

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    FontMetrics {
        id: largeClockMetrics
        font.family: root.config.clockFontFamily
        font.pixelSize: root.config.clockHourMinuteSize
    }
    FontMetrics {
        id: secondClockMetrics
        font.family: root.config.clockFontFamily
        font.pixelSize: root.config.clockSecondSize
    }

    LazyLoader {
        id: quotaLoader
        active: root.hasTargetScreen && root.config.quotaEnabled
        Services.OpenAiUsage {
            currentDate: clock.date
        }
    }
    LazyLoader {
        id: mouseLoader
        active: root.hasTargetScreen && root.config.mouseBatteryEnabled
        Services.MouseBattery {}
    }
    LazyLoader {
        id: micLoader
        active: root.hasTargetScreen && root.config.micBatteryEnabled || (root.micService?.queryPending ?? false)
        Services.DjiMicBattery {
            enabled: root.hasTargetScreen && root.config.micBatteryEnabled
        }
    }

    Variants {
        model: Quickshell.screens.filter(screen => screen.name === root.config.targetScreenName)

        PanelWindow {
            id: window
            required property var modelData
            screen: modelData

            WlrLayershell.namespace: "desktop-status"
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            focusable: false
            color: "transparent"
            surfaceFormat.opaque: false

            anchors {
                top: true
                right: true
            }
            margins {
                top: root.config.topMargin
                right: root.config.rightMargin
            }

            readonly property real clockRight: root.config.clockLeft + Math.max(largeClockMetrics.advanceWidth("88"), secondClockMetrics.advanceWidth("88"))
            readonly property real clockBottom: root.config.clockTop + largeClockMetrics.height * 2 + secondClockMetrics.height + root.config.clockLineSpacing * 2
            readonly property real availableWidth: window.modelData.width - root.config.rightMargin - window.clockRight - root.config.clockGap
            readonly property real availableHeight: Math.min(window.clockBottom, window.modelData.height) - root.config.topMargin

            visible: window.availableWidth > 0 && window.availableHeight > 0 && (root.config.quotaEnabled || root.config.mouseBatteryEnabled || root.config.micBatteryEnabled)
            implicitWidth: Math.max(1, Math.min(root.config.columnWidth, window.availableWidth))
            implicitHeight: Math.max(1, Math.min(panel.implicitHeight, window.availableHeight))

            Ui.StatusPanel {
                id: panel
                anchors.fill: parent
                config: root.config
                quotaService: quotaLoader.item
                mouseService: mouseLoader.item
                micService: root.micService
                currentDate: clock.date
            }
        }
    }
}
