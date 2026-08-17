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
    property Services.UpdateCount updateChecker: Services.UpdateCount {}
    property Services.MemoryStats memoryStats: Services.MemoryStats {}
    property Services.Audio audioService: Services.Audio {}
    property Services.Fcitx fcitx: Services.Fcitx {}

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
            memUsage: root.memoryStats.memUsage

            transform: Translate {
                y: root.bottomMargin
            }
            theme: root.theme
        }

        Widgets.Volume {
            available: root.audioService.available
            volume: root.audioService.volume
            muted: root.audioService.muted

            onVolumeRequested: value => root.audioService.setVolume(value)
            onMuteRequested: root.audioService.toggleMute()

            transform: Translate {
                y: root.bottomMargin
            }

            theme: root.theme
        }

        Widgets.TimeDate {
            Layout.rightMargin: root.sideMargin
            transform: Translate {
                y: root.bottomMargin
            }
            theme: root.theme
        }
    }
}
