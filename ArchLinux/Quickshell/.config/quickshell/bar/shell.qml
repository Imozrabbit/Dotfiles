import Quickshell
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

    property Network.NetworkStats networkStats: Network.NetworkStats {}

    property int sideMargin: 14
    property int bottomMargin: -4

    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    implicitHeight: 35
    color: "transparent"

    RowLayout {
        anchors.fill: parent
        anchors.margins: 1
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
