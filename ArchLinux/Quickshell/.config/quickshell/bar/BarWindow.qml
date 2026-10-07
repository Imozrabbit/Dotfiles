import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

import qs.core as Core
import qs.network as Network
import qs.widgets as Widgets

PanelWindow { // qmllint disable uncreatable-type
    id: root

    required property ShellScreen modelData
    required property var shared
    required property Core.Theme theme
    readonly property var configuration: root.shared.barConfig.forScreen(root.modelData.name)
    readonly property string mode: root.configuration.mode
    readonly property bool hoverToggleEnabled: root.configuration.hoverToggleEnabled
    readonly property var modules: root.configuration.modules
    readonly property var cpuStats: root.shared.cpuStats
    readonly property var gpuStats: root.shared.gpuStats
    readonly property var updateChecker: root.shared.updateChecker
    readonly property var memoryStats: root.shared.memoryStats
    readonly property var audioService: root.shared.audioService
    readonly property var brightnessService: root.shared.brightnessService
    readonly property var fcitx: root.shared.fcitx
    readonly property var swayncService: root.shared.swayncService
    readonly property var batteryService: root.shared.batteryService
    readonly property var mouseBatteryService: root.shared.mouseBatteryService
    readonly property var openAiUsageService: root.shared.openAiUsageService
    readonly property var mprisService: root.shared.mprisService
    readonly property var bluetoothService: root.shared.bluetoothService
    readonly property var weatherService: root.shared.weatherService
    readonly property var networkStats: root.shared.networkStats
    readonly property var vpnStatus: root.shared.vpnStatus
    readonly property var wifiMenu: root.shared.wifiMenu
    readonly property bool batteryDetailsVisible: root.modules.battery && timeDate.batteryDetailsVisible

    readonly property real sideMargin: root.configuration.edgeSpacing
    property int bottomMargin: -1
    property bool pinned: false
    property bool hoverRevealed: false
    property bool windowExpanded: true
    readonly property bool barShown: root.mode === "always" || root.pinned || root.hoverRevealed

    screen: root.modelData
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    implicitHeight: root.windowExpanded ? 35 : 2
    color: "transparent"
    WlrLayershell.exclusiveZone: root.mode === "always" || root.pinned ? 35 : -1

    Component.onCompleted: {
        if (root.mode === "hover")
            root.windowExpanded = false;
    }

    onModeChanged: {
        root.pinned = false;
        root.hoverRevealed = false;
        hideTimer.stop();
        collapseTimer.stop();
        root.windowExpanded = root.mode === "always";
    }

    function closeDisabledMenus() {
        if (!root.modules.volume)
            volumeWidget.closePopup();
        if (!root.modules.bluetooth)
            bluetoothWidget.closePopup();
        if (!root.modules.brightness)
            brightnessWidget.closePopup();
    }

    onModulesChanged: Qt.callLater(root.closeDisabledMenus)

    onBarShownChanged: {
        if (root.barShown) {
            collapseTimer.stop();
            root.windowExpanded = true;
        } else {
            collapseTimer.restart();
        }
    }

    function toggle() {
        if (root.mode !== "hover" || !root.hoverToggleEnabled)
            return;
        hideTimer.stop();
        root.hoverRevealed = false;
        root.pinned = !root.pinned;
    }

    HoverHandler {
        onHoveredChanged: {
            if (hovered) {
                hideTimer.stop();
                if (root.mode === "hover" && !root.pinned)
                    root.hoverRevealed = true;
            } else if (root.mode === "hover" && !root.pinned) {
                hideTimer.restart();
            }
        }
    }

    Timer {
        id: hideTimer

        interval: 80
        repeat: false
        onTriggered: root.hoverRevealed = false
    }

    Timer {
        id: collapseTimer

        interval: 20
        repeat: false
        onTriggered: {
            if (!root.barShown)
                root.windowExpanded = false;
        }
    }

    Item {
        id: barContents

        readonly property real leftEnd: workspaceBox.visible ? workspaceBox.x + workspaceBox.width : 0
        readonly property real rightStart: rightSection.visible ? rightSection.x : width
        readonly property real middleSpace: Math.max(0, rightStart - leftEnd)

        anchors.fill: parent
        anchors.margins: 1
        visible: root.windowExpanded
        opacity: root.barShown ? 1 : 0

        Behavior on opacity {
            enabled: root.mode === "hover"
            NumberAnimation {
                duration: root.barShown ? 10 : 20
                easing.type: Easing.Linear
                onFinished: {
                    if (!root.barShown)
                        root.windowExpanded = false;
                }
            }
        }

        // qmllint disable Quick.layout-positioning
        transform: Translate {
            y: root.barShown ? 0 : 4

            Behavior on y {
                enabled: root.mode === "hover"
                NumberAnimation {
                    duration: root.barShown ? 10 : 20
                    easing.type: Easing.Linear
                }
            }
        }
        // qmllint enable Quick.layout-positioning

        // -----------------------------------------------------------------------
        // Left Modules
        // -----------------------------------------------------------------------
        Widgets.Workspaces {
            id: workspaceBox

            anchors.left: parent.left
            anchors.leftMargin: root.sideMargin
            anchors.verticalCenter: parent.verticalCenter
            outputScreen: root.modelData
            visible: root.modules.tray || root.modules.workspaces || root.modules.launcher || root.modules.updates || root.modules.protonManager

            updateCount: root.updateChecker?.updateCount ?? 0
            checking: root.updateChecker?.checking ?? false
            onUpdateRequested: {
                if (root.updateChecker)
                    root.updateChecker.refresh();
            }
            showTray: root.modules.tray
            showWorkspaces: root.modules.workspaces
            showLauncher: root.modules.launcher
            showUpdates: root.modules.updates
            showProtonManager: root.modules.protonManager
            protonManagerOpen: root.shared.protonManagerScreen === root.modelData
            onProtonManagerRequested: root.shared.openProtonManager(root.modelData)
            workspaceDisplay: root.configuration.workspaceDisplay
            launchers: root.configuration.launchers

            // qmllint disable Quick.layout-positioning
            transform: Translate {
                y: root.bottomMargin
            }
            // qmllint enable Quick.layout-positioning
            theme: root.theme
        }

        // -----------------------------------------------------------------------
        // Central Modules
        // -----------------------------------------------------------------------
        Widgets.Mpris {
            id: mediaBox

            x: barContents.leftEnd + (barContents.middleSpace - width) / 2
            anchors.verticalCenter: parent.verticalCenter
            availableWidth: barContents.middleSpace * 0.7
            active: root.configuration.mediaPosition === "bottom" && root.modules.media && (root.mprisService?.active ?? false)
            paused: root.mprisService?.paused ?? false
            canTogglePlaying: root.mprisService?.canTogglePlaying ?? false
            app: root.mprisService?.app ?? ""
            title: root.mprisService?.title ?? ""
            artist: root.mprisService?.artist ?? ""
            theme: root.theme
            onTogglePlayingRequested: root.mprisService?.togglePlaying()
            transform: Translate {
                y: root.bottomMargin
            }
        }

        // -----------------------------------------------------------------------
        // Right Modules
        // -----------------------------------------------------------------------
        RowLayout {
            id: rightSection

            anchors.right: parent.right
            anchors.rightMargin: root.sideMargin
            anchors.verticalCenter: parent.verticalCenter
            visible: root.modules.network || root.modules.cpu || root.modules.gpu || root.modules.memory || root.modules.volume || root.modules.bluetooth || root.modules.inputMethod || root.modules.brightness || root.modules.battery || root.modules.mouseBattery || root.modules.openAiUsage || root.modules.clock || root.modules.calendar || root.modules.notifications
            z: 1

            Network.NetworkUsage {
                visible: root.modules.network
                downloadBps: root.networkStats?.downloadBps ?? 0
                uploadBps: root.networkStats?.uploadBps ?? 0
                online: root.networkStats?.online ?? false
                connectionType: root.networkStats?.connectionType ?? "unknown"
                vpnStatus: root.vpnStatus
                wifiMenuVisible: root.wifiMenu ? root.wifiMenu.visible && root.wifiMenu.screen === root.modelData : false
                wifiMenuEnabled: root.modules.wifiMenu
                vpnEnabled: root.modules.vpn
                onWifiMenuRequested: root.shared.openWifi(root.modelData)
                signalPercent: root.networkStats?.signalPercent ?? -1
                barRevealed: root.barShown
                onDetailsRequested: {
                    if (root.networkStats)
                        root.networkStats.refreshDetails();
                }

                // Tooltip information
                interfaceName: root.networkStats?.interfaceName ?? ""
                networkName: root.networkStats?.networkName ?? ""
                gatewayAddress: root.networkStats?.gatewayAddress ?? ""
                ipAddressCidr: root.networkStats?.ipAddressCidr ?? ""
                frequencyMhz: root.networkStats?.frequencyMhz ?? 0

                // qmllint disable Quick.layout-positioning
                transform: Translate {
                    y: root.bottomMargin
                }
                // qmllint enable Quick.layout-positioning
                theme: root.theme
            }

            Widgets.SystemUsage {
                visible: root.modules.cpu || root.modules.gpu || root.modules.memory
                showCpu: root.modules.cpu
                showGpu: root.modules.gpu
                showMemory: root.modules.memory
                cpuUsage: root.cpuStats?.cpuUsage ?? -1
                cpuModel: root.cpuStats?.cpuModel ?? "N/A"
                cpuClockMhz: root.cpuStats?.cpuClockMhz ?? -1
                cpuTemperatureC: root.cpuStats?.cpuTemperatureC ?? -1
                gpuUsage: root.gpuStats?.gpuUsage ?? -1
                gpuClockMhz: root.gpuStats?.clockMhz ?? -1
                gpuTemperatureC: root.gpuStats?.temperatureC ?? -1
                gpuName: root.gpuStats?.gpuName ?? "GPU unavailable"
                memUsage: root.memoryStats?.memUsage ?? -1
                memTotalKib: root.memoryStats?.memTotalKib ?? -1
                memUsedKib: root.memoryStats?.memUsedKib ?? -1
                memAvailableKib: root.memoryStats?.memAvailableKib ?? -1
                swapTotalKib: root.memoryStats?.swapTotalKib ?? -1
                swapUsedKib: root.memoryStats?.swapUsedKib ?? -1

                // qmllint disable Quick.layout-positioning
                transform: Translate {
                    y: root.bottomMargin
                }
                // qmllint enable Quick.layout-positioning
                theme: root.theme
            }

            Rectangle {
                id: functionBox
                visible: root.modules.volume || root.modules.bluetooth || root.modules.inputMethod || root.modules.brightness
                implicitWidth: audioInputLayout.implicitWidth
                implicitHeight: audioInputLayout.implicitHeight
                radius: root.theme.radiusMedium
                color: root.theme.volumeBg
                transform: Translate {
                    y: root.bottomMargin
                }
                RowLayout {
                    id: audioInputLayout
                    spacing: 0
                    Widgets.Volume {
                        id: volumeWidget
                        visible: root.modules.volume
                        available: root.audioService?.available ?? false
                        volume: root.audioService?.volume ?? 0
                        muted: root.audioService?.muted ?? false
                        onVolumeRequested: value => {
                            if (root.audioService)
                                root.audioService.setVolume(value);
                        }
                        onMuteRequested: {
                            if (root.audioService)
                                root.audioService.toggleMute();
                        }
                        theme: root.theme
                    }
                    Rectangle {
                        visible: root.modules.volume && (root.modules.bluetooth || root.modules.inputMethod || root.modules.brightness)
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: root.theme.volumeFontSize
                        Layout.alignment: Qt.AlignVCenter
                        color: root.theme.volumeSliderTrackColor
                        opacity: 0.55
                    }
                    Widgets.Bluetooth {
                        id: bluetoothWidget
                        visible: root.modules.bluetooth
                        outputScreen: root.modelData
                        available: root.bluetoothService?.available ?? false
                        powered: root.bluetoothService?.powered ?? false
                        connected: root.bluetoothService?.connected ?? false
                        detailsKnown: root.bluetoothService?.detailsKnown ?? false
                        connectedDevices: root.bluetoothService?.connectedDevices ?? []
                        disconnectedDevices: root.bluetoothService?.disconnectedDevices ?? []
                        actionBusy: root.bluetoothService?.actionBusy ?? false
                        actionAddress: root.bluetoothService?.actionAddress ?? ""
                        actionError: root.bluetoothService?.actionError ?? ""
                        barRevealed: root.barShown
                        onDetailsRequested: {
                            if (root.bluetoothService)
                                root.bluetoothService.refreshDetails();
                        }
                        onPoweredRequested: enabled => {
                            if (root.bluetoothService)
                                root.bluetoothService.setPowered(enabled);
                        }
                        onConnectRequested: address => {
                            if (root.bluetoothService)
                                root.bluetoothService.connectDevice(address);
                        }
                        onDisconnectRequested: address => {
                            if (root.bluetoothService)
                                root.bluetoothService.disconnectDevice(address);
                        }
                        onManagerRequested: {
                            if (root.bluetoothService)
                                root.bluetoothService.openManager();
                        }
                        theme: root.theme
                    }
                    Rectangle {
                        visible: root.modules.bluetooth && (root.modules.inputMethod || root.modules.brightness)
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: root.theme.volumeFontSize
                        Layout.alignment: Qt.AlignVCenter
                        color: root.theme.volumeSliderTrackColor
                        opacity: 0.55
                    }
                    Widgets.InputMethod {
                        visible: root.modules.inputMethod
                        currentMethod: root.fcitx?.currentMethod ?? "N/A"
                        onCycleRequested: {
                            if (root.fcitx)
                                root.fcitx.cycle();
                        }
                        theme: root.theme
                    }
                    Rectangle {
                        visible: root.modules.inputMethod && root.modules.brightness
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: root.theme.volumeFontSize
                        Layout.alignment: Qt.AlignVCenter
                        color: root.theme.volumeSliderTrackColor
                        opacity: 0.55
                    }
                    Widgets.Brightness {
                        id: brightnessWidget
                        visible: root.modules.brightness
                        available: root.brightnessService?.available ?? false
                        brightness: root.brightnessService?.brightness ?? 0.01
                        onBrightnessRequested: value => {
                            if (root.brightnessService)
                                root.brightnessService.setBrightness(value);
                        }
                        onKeyboardBacklightRequested: {
                            if (root.brightnessService)
                                root.brightnessService.cycleKeyboardBacklight();
                        }
                        theme: root.theme
                    }
                }
            }

            Widgets.OpenAiUsage {
                visible: root.modules.openAiUsage
                display: root.configuration.openAiUsage.display
                theme: root.theme
                snapshot: root.openAiUsageService?.snapshot ?? null
                available: root.openAiUsageService?.available ?? false
                error: root.openAiUsageService?.error ?? "No quota reading available"
                currentDate: root.shared.clock?.date ?? new Date()
                onRefreshRequested: force => {
                    if (root.openAiUsageService)
                        root.openAiUsageService.refresh(force);
                }
                // qmllint disable Quick.layout-positioning
                transform: Translate {
                    y: root.bottomMargin
                }
                // qmllint enable Quick.layout-positioning
            }

            Widgets.TimeDate {
                id: timeDate
                outputScreen: root.modelData
                currentDate: root.shared.clock?.date ?? new Date()
                showBattery: root.modules.battery
                showMouseBattery: root.modules.mouseBattery
                mouseName: root.configuration.mouseBattery.name
                mouseAvailable: root.mouseBatteryService?.available ?? false
                mousePercentage: root.mouseBatteryService?.percentage ?? -1
                mouseCharging: root.mouseBatteryService?.charging ?? false
                mouseConnection: root.mouseBatteryService?.connection ?? ""
                mouseError: root.mouseBatteryService?.error ?? "No reading available"
                onMouseRefreshRequested: {
                    if (root.mouseBatteryService)
                        root.mouseBatteryService.refresh();
                }
                showClock: root.modules.clock
                showCalendar: root.modules.calendar
                showWeather: root.modules.weather
                showNotifications: root.modules.notifications
                dnd: root.swayncService?.dnd ?? false
                hasNotifications: root.swayncService?.hasNotifications ?? false
                weatherService: root.weatherService
                batteryAvailable: root.batteryService?.available ?? false
                batteryCapacity: root.batteryService?.capacity ?? -1
                batteryStatus: root.batteryService?.status ?? "Unknown"
                acOnline: root.batteryService?.acOnline ?? false
                batteryEnergyNowUwh: root.batteryService?.energyNowUwh ?? -1
                batteryEnergyFullUwh: root.batteryService?.energyFullUwh ?? -1
                batteryEnergyFullDesignUwh: root.batteryService?.energyFullDesignUwh ?? -1
                batteryPowerNowUw: root.batteryService?.powerNowUw ?? -1
                batteryChargeStartThreshold: root.batteryService?.chargeStartThreshold ?? -1
                batteryChargeEndThreshold: root.batteryService?.chargeEndThreshold ?? -1
                batteryCycleCount: root.batteryService?.cycleCount ?? -1
                batteryPowerProfile: root.batteryService?.activePowerProfile ?? ""
                batteryActionBusy: root.batteryService?.actionBusy ?? false
                batteryActionError: root.batteryService?.actionError ?? ""
                barRevealed: root.barShown
                onBatteryPanelOpened: {
                    if (root.batteryService)
                        root.batteryService.refreshPowerProfile();
                }
                onBatteryPowerProfileRequested: profile => {
                    if (root.batteryService)
                        root.batteryService.setPowerProfile(profile);
                }
                onBatteryChargeThresholdsRequested: (startValue, endValue) => {
                    if (root.batteryService)
                        root.batteryService.setChargeThresholds(startValue, endValue);
                }
                onNotificationsRequested: {
                    if (root.swayncService)
                        root.swayncService.openPanel();
                }
                transform: Translate {
                    y: root.bottomMargin
                }
                theme: root.theme
            }
        }
    }
}
