pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.core as Core
import qs.network.vpn as Vpn

Rectangle {
    id: root

    required property real downloadBps
    required property real uploadBps
    required property bool online
    required property bool barRevealed
    required property string connectionType
    required property var vpnStatus
    required property bool wifiMenuVisible
    required property bool wifiMenuEnabled
    required property bool vpnEnabled

    required property string interfaceName
    required property string networkName
    required property string gatewayAddress
    required property string ipAddressCidr
    required property int frequencyMhz

    required property Core.Theme theme

    required property int signalPercent
    signal detailsRequested
    signal wifiMenuRequested
    property bool tooltipVisible: false
    // Hover loads extra details for the tooltip; clicking toggles the Wi-Fi menu.
    HoverHandler {
        id: networkHover

        cursorShape: root.wifiMenuEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onHoveredChanged: {
            if (hovered && !root.wifiMenuVisible) {
                root.detailsRequested();
                tooltipDelay.restart();
            } else {
                tooltipDelay.stop();
                root.tooltipVisible = false;
            }
        }
    }

    Timer {
        id: tooltipDelay
        interval: 300
        repeat: false
        onTriggered: root.tooltipVisible = networkHover.hovered && !root.wifiMenuVisible
    }

    TapHandler {
        enabled: root.wifiMenuEnabled
        onTapped: {
            root.tooltipVisible = false;
            root.wifiMenuRequested();
        }
    }

    // Keep transfer rates compact while preserving one decimal place for larger units.
    function formatRate(bytesPerSecond) {
        const value = Math.max(0, bytesPerSecond);
        if (value < 1000)
            return Math.round(value) + " B/s";
        if (value < 1000000)
            return (value / 1000).toFixed(0) + " KB/s";
        if (value < 1000000000)
            return (value / 1000000).toFixed(0) + " MB/s";
        return (value / 1000000000).toFixed(0) + " GB/s";
    }

    function connectionIcon() {
        if (!root.online)
            return "󰖪";
        if (root.connectionType === "wired")
            return "";
        if (root.connectionType === "wifi") {
            if (root.signalPercent < 20)
                return "󰤯";
            if (root.signalPercent < 40)
                return "󰤟";
            if (root.signalPercent < 60)
                return "󰤢";
            if (root.signalPercent < 80)
                return "󰤥";
            return "󰤨";
        }
        return "󰖟";
    }

    implicitWidth: content.implicitWidth + 16
    implicitHeight: content.implicitHeight + 4
    radius: root.theme.radiusMedium
    color: root.theme.networkUsageBg

    RowLayout {
        id: content
        anchors.centerIn: parent
        spacing: 6

        Text {
            text: root.connectionIcon()
            color: root.online ? root.theme.networkOnlineColor : root.theme.networkOfflineColor
            font {
                family: root.theme.fontFamily
                pixelSize: root.theme.networkUsageFontSize
                bold: true
            }
        }

        Rectangle {
            Layout.preferredWidth: 1
            Layout.preferredHeight: root.theme.networkUsageFontSize
            color: root.theme.networkSeparatorColor
        }

        Text {
            text: "󰇚 " + root.formatRate(root.downloadBps)
            color: root.theme.networkUsageColor
            font {
                family: root.theme.fontFamily
                pixelSize: root.theme.networkUsageFontSize
                bold: true
            }
        }

        Rectangle {
            Layout.preferredWidth: 1
            Layout.preferredHeight: root.theme.networkUsageFontSize
            color: root.theme.networkSeparatorColor
        }

        Text {
            text: "󰕒 " + root.formatRate(root.uploadBps)
            color: root.theme.networkUsageColor
            font {
                family: root.theme.fontFamily
                pixelSize: root.theme.networkUsageFontSize
                bold: true
            }
        }

        Loader {
            id: vpnIndicator
            active: root.vpnEnabled && Boolean(root.vpnStatus)
            Layout.leftMargin: 1
            Layout.rightMargin: 1
            sourceComponent: Vpn.VpnIndicator {
                theme: root.theme
                status: root.vpnStatus
            }
        }
    }

    // Network overlays are owned here so module interaction remains local.
    NetworkTooltip {
        visible: root.tooltipVisible
        vpnEnabled: root.vpnEnabled
        anchorItem: root
        online: root.online
        connectionType: root.connectionType
        signalPercent: root.signalPercent
        interfaceName: root.interfaceName
        networkName: root.networkName
        gatewayAddress: root.gatewayAddress
        ipAddressCidr: root.ipAddressCidr
        frequencyMhz: root.frequencyMhz
        protectionMode: root.vpnStatus?.protectionMode ?? "unknown"
        vpnName: root.vpnStatus?.vpnName ?? ""
        dnsName: root.vpnStatus?.dnsName ?? ""
        theme: root.theme
    }
}
