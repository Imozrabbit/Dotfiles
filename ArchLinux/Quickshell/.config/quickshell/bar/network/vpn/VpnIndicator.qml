pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.core as Core

RowLayout {
    id: root

    required property Core.Theme theme
    required property string networkName
    readonly property string protectionMode: vpnStatus.protectionMode
    readonly property string vpnName: vpnStatus.vpnName
    readonly property string dnsName: vpnStatus.dnsName
    readonly property string dnsServers: vpnStatus.dnsServers
    readonly property bool dnsExpected: vpnStatus.dnsExpected
    readonly property bool dnsKnown: vpnStatus.dnsKnown

    function indicatorIcon() {
        if (root.protectionMode === "home")
            return !root.dnsKnown ? "" : root.dnsExpected ? "󰣫" : "󱗑";
        if (root.protectionMode === "vpn")
            return !root.dnsKnown ? "" : root.dnsExpected ? "" : "󱗑";
        if (root.protectionMode === "unprotected")
            return "󱙲";
        return "";
    }

    function indicatorColor() {
        if ((root.protectionMode === "home" || root.protectionMode === "vpn") && root.dnsKnown && root.dnsExpected)
            return root.theme.networkOnlineColor;
        if (((root.protectionMode === "home" || root.protectionMode === "vpn") && root.dnsKnown) || root.protectionMode === "unprotected")
            return root.theme.networkOfflineColor;
        return root.theme.networkSeparatorColor;
    }

    spacing: 6

    Rectangle {
        Layout.preferredWidth: 1
        Layout.preferredHeight: root.theme.networkUsageFontSize
        color: root.theme.networkSeparatorColor
    }

    Text {
        text: root.indicatorIcon()
        color: root.indicatorColor()
        font {
            family: root.theme.fontFamily
            pixelSize: root.theme.networkUsageFontSize
            bold: true
        }
    }

    VpnDnsStatus {
        id: vpnStatus
        networkName: root.networkName
    }
}
