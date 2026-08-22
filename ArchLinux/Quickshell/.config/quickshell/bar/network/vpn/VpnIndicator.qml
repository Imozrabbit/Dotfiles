pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.core as Core

RowLayout {
    id: root

    required property Core.Theme theme
    readonly property bool vpnActive: vpnStatus.ifVpn
    readonly property string vpnName: vpnStatus.vpnName
    readonly property string dnsName: vpnStatus.dnsName
    readonly property bool statusKnown: vpnStatus.statusKnown

    spacing: 6

    Rectangle {
        Layout.preferredWidth: 1
        Layout.preferredHeight: root.theme.networkUsageFontSize
        color: root.theme.networkSeparatorColor
    }

    Text {
        text: "󰖂"
        color: root.vpnActive ? root.theme.networkOnlineColor : root.theme.networkSeparatorColor
        font {
            family: root.theme.fontFamily
            pixelSize: root.theme.networkUsageFontSize
            bold: true
        }
    }

    VpnDnsStatus {
        id: vpnStatus
    }
}
