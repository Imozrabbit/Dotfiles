pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.core as Core

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
    // Hover loads extra details for the tooltip; clicking toggles the Wi-Fi selector.
    HoverHandler {
        id: networkHover

        cursorShape: Qt.PointingHandCursor
        onHoveredChanged: {
            if (hovered && !wifiSelector.visible) {
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
        onTriggered: root.tooltipVisible = networkHover.hovered && !wifiSelector.visible
    }

    TapHandler {
        onTapped: {
            root.tooltipVisible = false;
            wifiSelector.visible = !wifiSelector.visible;
        }
    }

    // Keep transfer rates compact while preserving one decimal place for larger units.
    function formatRate(bytesPerSecond) {
        const value = Math.max(0, bytesPerSecond);
        if (value < 1000)
            return Math.round(value) + " B/s";
        if (value < 1000000)
            return (value / 1000).toFixed(1) + " KB/s";
        if (value < 1000000000)
            return (value / 1000000).toFixed(1) + " MB/s";
        return (value / 1000000000).toFixed(1) + " GB/s";
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

    // Both popups are owned here so they stay anchored to the network card.
    NetworkTooltip {
        id: networkTooltip

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

    WifiSelector {
        id: wifiSelector

        anchorItem: root
        theme: root.theme
    }
}
