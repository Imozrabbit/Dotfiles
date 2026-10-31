pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.core as Core
import qs.widgets as Widgets

Widgets.TooltipWindow {
    id: root

    required property bool online
    required property bool vpnEnabled
    required property string connectionType
    required property int signalPercent
    required property string interfaceName
    required property string networkName
    required property string gatewayAddress
    required property string ipAddressCidr
    required property int frequencyMhz
    required property string protectionMode
    required property string vpnName
    property var vpnDetails: ({})
    required property string dnsName
    required property Core.Theme theme

    function valueOrUnavailable(value) {
        return value === "" ? "N/A" : value;
    }

    function connectionTitle() {
        if (!root.online)
            return "Disconnected";
        if (root.connectionType === "wifi")
            return "Wi-Fi: " + root.valueOrUnavailable(root.networkName);
        if (root.connectionType === "wired")
            return "Ethernet";
        return "Network";
    }

    function frequencyText() {
        if (root.frequencyMhz <= 0)
            return "N/A";
        return (root.frequencyMhz / 1000).toFixed(2) + " GHz";
    }

    function vpnText() {
        const text = root.protectionMode === "unknown" ? "Unavailable" : root.protectionMode === "home" ? "Router VPN (assumed)" : root.protectionMode === "vpn" ? root.vpnName : "Not connected";
        const status = root.vpnDetails.schoolStatus || "";
        return status && !root.vpnDetails.schoolConnected && !status.endsWith(": disconnected") ? text + " · " + status : text;
    }

    // Build only the detail rows that apply to the current connection type.
    function tooltipRows() {
        if (!root.online)
            return [];
        const rows = [];
        if (root.connectionType === "wifi") {
            rows.push({
                label: "Signal",
                value: root.signalPercent >= 0 ? root.signalPercent + "%" : "N/A"
            });
            rows.push({
                label: "Frequency",
                value: root.frequencyText()
            });
        }
        rows.push({
            label: "Interface",
            value: root.valueOrUnavailable(root.interfaceName)
        });
        rows.push({
            label: "IPv4",
            value: root.valueOrUnavailable(root.ipAddressCidr)
        });
        rows.push({
            label: "Gateway",
            value: root.valueOrUnavailable(root.gatewayAddress)
        });
        if (root.vpnEnabled) {
            rows.push({
                label: "VPN",
                value: root.vpnText()
            });
            rows.push({
                label: "DNS",
                value: root.valueOrUnavailable(root.dnsName)
            });
            if (root.vpnDetails.nestedWarning)
                rows.push({
                    label: "Warning",
                    value: "Possible nested VPN: school + assumed router VPN.\nAdditional tunneling overhead may increase latency."
                });
        }
        return rows;
    }

    implicitWidth: tooltipContent.implicitWidth + 20
    implicitHeight: tooltipContent.implicitHeight + 16

    Rectangle {
        anchors.fill: parent
        color: root.theme.tooltipBg
        border.color: root.theme.tooltipBorderColor
        border.width: 1
        radius: root.theme.radiusMedium
        ColumnLayout {
            id: tooltipContent
            anchors.centerIn: parent
            spacing: 4
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: root.connectionTitle()
                textFormat: Text.PlainText
                color: root.theme.tooltipColor
                font {
                    family: root.theme.tooltipFontFamily
                    pixelSize: root.theme.tooltipFontSize
                    bold: true
                }
            }
            Repeater {
                model: root.tooltipRows()
                delegate: RowLayout {
                    required property var modelData
                    spacing: 4
                    Text {
                        text: parent.modelData.label + ":"
                        color: root.theme.tooltipColor
                        font {
                            family: root.theme.tooltipFontFamily
                            pixelSize: root.theme.tooltipFontSize
                        }
                    }
                    Text {
                        text: parent.modelData.value
                        textFormat: Text.PlainText
                        color: root.theme.tooltipColor
                        font {
                            family: root.theme.tooltipFontFamily
                            pixelSize: root.theme.tooltipFontSize
                            bold: true
                        }
                    }
                }
            }
        }
    }
}
