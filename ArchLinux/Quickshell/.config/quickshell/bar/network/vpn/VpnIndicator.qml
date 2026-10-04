pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.core as Core

RowLayout {
    id: root

    required property Core.Theme theme
    required property var status
    readonly property string protectionMode: root.status.protectionMode

    function indicatorIcon() {
        if (root.protectionMode === "home")
            return "󰣫";
        if (root.protectionMode === "vpn")
            return "";
        if (root.protectionMode === "unprotected")
            return "󱙲";
        return "";
    }

    function indicatorColor() {
        if (root.protectionMode === "home" || root.protectionMode === "vpn")
            return root.theme.networkOnlineColor;
        if (root.protectionMode === "unprotected")
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
    Rectangle {
        Layout.preferredWidth: 5
        Layout.preferredHeight: 5
        radius: 2.5
        color: ({
                nextdns: "#8FB7AB",
                router: "#9EB5C6",
                vpn: "#D8D8D8",
                other: "#D8D8D8",
                mixed: "#B7A6C9",
                unavailable: "#B77A72"
            })[root.status.dnsKind] ?? "#707072"
    }
}
