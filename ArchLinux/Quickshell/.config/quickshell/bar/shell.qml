import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

import qs.core as Core
import qs.network as Network
import qs.widgets as Widgets
import qs.services as Services

PanelWindow { // qmllint disable uncreatable-type
    id: root

    property Core.Theme theme: Core.Theme {}

    property Services.CpuStats cpuStats: Services.CpuStats {}
    property Services.GpuStats gpuStats: Services.GpuStats {}
    property Services.UpdateCount updateChecker: Services.UpdateCount {}
    property Services.MemoryStats memoryStats: Services.MemoryStats {}
    property Services.Audio audioService: Services.Audio {}
    property Services.Brightness brightnessService: Services.Brightness {}
    property Services.Fcitx fcitx: Services.Fcitx {}
    property Services.Swaync swayncService: Services.Swaync {}
    property Services.Battery batteryService: Services.Battery {}
    property Services.Mpris mprisService: Services.Mpris {}
    property Services.Bluetooth bluetoothService: Services.Bluetooth {}
    property Services.Weather weatherService: Services.Weather {}

    property Network.NetworkStats networkStats: Network.NetworkStats {}

    property int sideMargin: 14
    property int bottomMargin: -1
    property bool barEnabled: true
    property bool hoverRevealed: false
    property bool windowExpanded: true
    readonly property bool barShown: root.barEnabled || root.hoverRevealed

    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    implicitHeight: root.windowExpanded ? 35 : 2
    color: "transparent"
    WlrLayershell.exclusiveZone: root.barEnabled ? 35 : -1

    onBarShownChanged: {
        if (root.barShown)
            root.windowExpanded = true;
    }

    IpcHandler {
        target: "bar"

        function toggle(): void {
            hideTimer.stop();
            root.hoverRevealed = false;
            root.barEnabled = !root.barEnabled;
        }
    }

    HoverHandler {
        onHoveredChanged: {
            if (hovered) {
                hideTimer.stop();
                if (!root.barEnabled)
                    root.hoverRevealed = true;
            } else if (!root.barEnabled) {
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

    RowLayout {
        anchors.fill: parent
        anchors.margins: 1
        visible: root.windowExpanded
        opacity: root.barShown ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: 80
                easing.type: Easing.OutCubic
                onFinished: {
                    if (!root.barShown)
                        root.windowExpanded = false;
                }
            }
        }

        transform: Translate {
            y: root.barShown ? 0 : 6

            Behavior on y {
                NumberAnimation {
                    duration: 80
                    easing.type: Easing.OutCubic
                }
            }
        }

        // -----------------------------------------------------------------------
        // Left Modules
        // -----------------------------------------------------------------------
        Widgets.Workspaces {
            Layout.leftMargin: root.sideMargin

            updateCount: root.updateChecker.updateCount
            checking: root.updateChecker.checking
            onUpdateRequested: root.updateChecker.refresh()

            transform: Translate {
                y: root.bottomMargin
            }
            theme: root.theme
        }

        // -----------------------------------------------------------------------
        // Central Modules
        // -----------------------------------------------------------------------
        Item {
            Layout.fillWidth: true
        }

        Widgets.Mpris {
            active: root.mprisService.active
            playing: root.mprisService.playing
            paused: root.mprisService.paused
            canTogglePlaying: root.mprisService.canTogglePlaying
            app: root.mprisService.app
            title: root.mprisService.title
            artist: root.mprisService.artist
            onTogglePlayingRequested: root.mprisService.togglePlaying()
            theme: root.theme
            transform: Translate {
                y: root.bottomMargin
            }
        }

        Item {
            Layout.fillWidth: true
        }

        // -----------------------------------------------------------------------
        // Right Modules
        // -----------------------------------------------------------------------
        Network.NetworkUsage {
            downloadBps: root.networkStats.downloadBps
            uploadBps: root.networkStats.uploadBps
            online: root.networkStats.online
            connectionType: root.networkStats.connectionType
            signalPercent: root.networkStats.signalPercent
            barRevealed: root.barShown
            onDetailsRequested: root.networkStats.refreshDetails()

            // Tooltip information
            interfaceName: root.networkStats.interfaceName
            networkName: root.networkStats.networkName
            gatewayAddress: root.networkStats.gatewayAddress
            ipAddressCidr: root.networkStats.ipAddressCidr
            frequencyMhz: root.networkStats.frequencyMhz

            transform: Translate {
                y: root.bottomMargin
            }
            theme: root.theme
        }

        Widgets.SystemUsage {
            cpuUsage: root.cpuStats.cpuUsage
            cpuModel: root.cpuStats.cpuModel
            cpuClockMhz: root.cpuStats.cpuClockMhz
            cpuTemperatureC: root.cpuStats.cpuTemperatureC
            gpuUsage: root.gpuStats.gpuUsage
            gpuClockMhz: root.gpuStats.clockMhz
            gpuTemperatureC: root.gpuStats.temperatureC
            gpuName: root.gpuStats.gpuName
            memUsage: root.memoryStats.memUsage
            memTotalKib: root.memoryStats.memTotalKib
            memUsedKib: root.memoryStats.memUsedKib
            memAvailableKib: root.memoryStats.memAvailableKib
            swapTotalKib: root.memoryStats.swapTotalKib
            swapUsedKib: root.memoryStats.swapUsedKib

            transform: Translate {
                y: root.bottomMargin
            }
            theme: root.theme
        }

        Rectangle {
            id: functionBox
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
                    available: root.audioService.available
                    volume: root.audioService.volume
                    muted: root.audioService.muted
                    onVolumeRequested: value => root.audioService.setVolume(value)
                    onMuteRequested: root.audioService.toggleMute()
                    theme: root.theme
                }
                Rectangle {
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: root.theme.volumeFontSize
                    Layout.alignment: Qt.AlignVCenter
                    color: root.theme.volumeSliderTrackColor
                    opacity: 0.55
                }
                Widgets.Bluetooth {
                    available: root.bluetoothService.available
                    powered: root.bluetoothService.powered
                    connected: root.bluetoothService.connected
                    detailsKnown: root.bluetoothService.detailsKnown
                    connectedDevices: root.bluetoothService.connectedDevices
                    disconnectedDevices: root.bluetoothService.disconnectedDevices
                    actionBusy: root.bluetoothService.actionBusy
                    actionAddress: root.bluetoothService.actionAddress
                    actionError: root.bluetoothService.actionError
                    barRevealed: root.barShown
                    onDetailsRequested: root.bluetoothService.refreshDetails()
                    onPoweredRequested: enabled => root.bluetoothService.setPowered(enabled)
                    onConnectRequested: address => root.bluetoothService.connectDevice(address)
                    onDisconnectRequested: address => root.bluetoothService.disconnectDevice(address)
                    onManagerRequested: root.bluetoothService.openManager()
                    theme: root.theme
                }
                Rectangle {
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: root.theme.volumeFontSize
                    Layout.alignment: Qt.AlignVCenter
                    color: root.theme.volumeSliderTrackColor
                    opacity: 0.55
                }
                Widgets.InputMethod {
                    currentMethod: root.fcitx.currentMethod
                    theme: root.theme
                }
                Rectangle {
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: root.theme.volumeFontSize
                    Layout.alignment: Qt.AlignVCenter
                    color: root.theme.volumeSliderTrackColor
                    opacity: 0.55
                }
                Widgets.Brightness {
                    available: root.brightnessService.available
                    brightness: root.brightnessService.brightness
                    onBrightnessRequested: value => root.brightnessService.setBrightness(value)
                    theme: root.theme
                }
            }
        }

        Widgets.TimeDate {
            Layout.rightMargin: root.sideMargin
            dnd: root.swayncService.dnd
            hasNotifications: root.swayncService.hasNotifications
            weatherService: root.weatherService
            batteryAvailable: root.batteryService.available
            batteryCapacity: root.batteryService.capacity
            batteryStatus: root.batteryService.status
            acOnline: root.batteryService.acOnline
            batteryEnergyNowUwh: root.batteryService.energyNowUwh
            batteryEnergyFullUwh: root.batteryService.energyFullUwh
            batteryEnergyFullDesignUwh: root.batteryService.energyFullDesignUwh
            batteryPowerNowUw: root.batteryService.powerNowUw
            batteryChargeStartThreshold: root.batteryService.chargeStartThreshold
            batteryChargeEndThreshold: root.batteryService.chargeEndThreshold
            batteryCycleCount: root.batteryService.cycleCount
            batteryPowerProfile: root.batteryService.activePowerProfile
            batteryActionBusy: root.batteryService.actionBusy
            batteryActionError: root.batteryService.actionError
            barRevealed: root.barShown
            onBatteryPanelOpened: root.batteryService.refreshPowerProfile()
            onBatteryPowerProfileRequested: profile => root.batteryService.setPowerProfile(profile)
            onBatteryChargeThresholdsRequested: (startValue, endValue) => root.batteryService.setChargeThresholds(startValue, endValue)
            onNotificationsRequested: root.swayncService.openPanel()
            transform: Translate {
                y: root.bottomMargin
            }
            theme: root.theme
        }
    }
}
