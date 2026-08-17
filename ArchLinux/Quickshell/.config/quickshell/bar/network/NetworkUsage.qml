pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.core as Core
import qs.network.wifi as Wifi

Rectangle {
    id: root

    required property real downloadBps
    required property real uploadBps
    required property bool online
    required property string connectionType

    required property string interfaceName
    required property string networkName
    required property string gatewayAddress
    required property string ipAddressCidr
    required property int frequencyMhz

    required property Core.Theme theme

    required property int signalPercent
    signal detailsRequested
    property bool tooltipVisible: false
    // Hover loads extra details for the tooltip; clicking toggles the Wi-Fi menu.
    HoverHandler {
        id: networkHover

        cursorShape: Qt.PointingHandCursor
        onHoveredChanged: {
            if (hovered && !wifiMenu.visible) {
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
        onTriggered: root.tooltipVisible = networkHover.hovered && !wifiMenu.visible
    }

    TapHandler {
        onTapped: {
            root.tooltipVisible = false;
            wifiMenu.visible = !wifiMenu.visible;
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
    }

    // Network overlays are owned here so module interaction remains local.
    NetworkTooltip {
        visible: root.tooltipVisible
        anchorItem: root
        online: root.online
        connectionType: root.connectionType
        signalPercent: root.signalPercent
        interfaceName: root.interfaceName
        networkName: root.networkName
        gatewayAddress: root.gatewayAddress
        ipAddressCidr: root.ipAddressCidr
        frequencyMhz: root.frequencyMhz
        theme: root.theme
    }

    Wifi.WifiMenu {
        id: wifiMenu

        standalone: false
        theme: root.theme
        onCloseRequested: visible = false
    }
}
