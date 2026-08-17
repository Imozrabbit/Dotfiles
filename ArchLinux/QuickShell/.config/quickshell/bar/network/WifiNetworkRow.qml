pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Networking

import qs.core as Core

Rectangle {
    id: root

    required property var network
    required property Core.Theme theme

    readonly property int signalPercent: Math.round(Math.max(0, Math.min(1, root.network.signalStrength)) * 100)

    readonly property bool isOpen: root.network.security === WifiSecurityType.Open

    signal activated(var network)

    // Map signal percentage to five familiar Wi-Fi strength icons.
    function signalIcon() {
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

    // Show connection progress first, then the network's connected or security state.
    function statusText() {
        if (root.network.state === ConnectionState.Connecting)
            return "Connecting...";
        if (root.network.state === ConnectionState.Disconnecting)
            return "Disconnecting...";
        if (root.network.connected)
            return "Connected";
        if (root.isOpen)
            return "Open";

        return "";
    }

    implicitHeight: 36
    radius: 4

    color: rowHover.hovered ? root.theme.wifiSelectorHoverBg : "transparent"

    HoverHandler {
        id: rowHover
        cursorShape: root.network.stateChanging ? Qt.ArrowCursor : Qt.PointingHandCursor
    }

    TapHandler {
        enabled: !root.network.stateChanging
        onTapped: root.activated(root.network)
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: 8

        Text {
            text: root.signalIcon()
            color: root.theme.wifiSelectorTextColor
            font {
                family: root.theme.wifiSelectorFontFamily
                pixelSize: root.theme.wifiSelectorBodyFontSize
            }
        }

        Text {
            Layout.fillWidth: true
            text: root.network.name
            elide: Text.ElideRight
            color: root.network.connected ? root.theme.wifiSelectorActiveColor : root.theme.wifiSelectorTextColor
            font {
                family: root.theme.wifiSelectorFontFamily
                pixelSize: root.theme.wifiSelectorBodyFontSize
                bold: root.network.connected
            }
        }

        Text {
            text: root.statusText()
            color: root.network.connected ? root.theme.wifiSelectorActiveColor : root.isOpen ? root.theme.wifiSelectorWarningColor : root.theme.wifiSelectorMutedColor
            font {
                family: root.theme.wifiSelectorFontFamily
                pixelSize: root.theme.wifiSelectorBodyFontSize
            }
        }
    }
}
