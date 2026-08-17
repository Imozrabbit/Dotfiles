pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell

import qs.core as Core

PopupWindow {
    id: root

    required property Item anchorItem
    required property bool online
    required property string connectionType
    required property int signalPercent
    required property string interfaceName
    required property string networkName
    required property string gatewayAddress
    required property string ipAddressCidr
    required property int frequencyMhz
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
        return rows;
    }

    color: "transparent"
    grabFocus: false

    implicitWidth: tooltipContent.implicitWidth + 20
    implicitHeight: tooltipContent.implicitHeight + 16

    anchor.item: root.anchorItem
    anchor.rect.x: 0
    anchor.rect.y: -8
    anchor.rect.width: root.anchorItem.width
    anchor.rect.height: root.anchorItem.height
    anchor.edges: Edges.Top
    anchor.gravity: Edges.Top

    Rectangle {
        anchors.fill: parent
        color: root.theme.networkTooltipBg
        border.color: root.theme.networkTooltipBorderColor
        border.width: 1
        radius: root.theme.radiusMedium
        ColumnLayout {
            id: tooltipContent
            anchors.centerIn: parent
            spacing: 4
            Text {
                id: tooltipTitle
                Layout.alignment: Qt.AlignHCenter
                text: root.connectionTitle()
                color: root.theme.networkTooltipColor
                font {
                    family: root.theme.tooltipFontFamily
                    pixelSize: root.theme.networkTooltipFontSize
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
                        color: root.theme.networkTooltipColor
                        font {
                            family: root.theme.tooltipFontFamily
                            pixelSize: root.theme.networkTooltipFontSize
                        }
                    }
                    Text {
                        text: parent.modelData.value
                        color: root.theme.networkTooltipColor
                        font {
                            family: root.theme.tooltipFontFamily
                            pixelSize: root.theme.networkTooltipFontSize
                            bold: true
                        }
                    }
                }
            }
        }
    }
}
