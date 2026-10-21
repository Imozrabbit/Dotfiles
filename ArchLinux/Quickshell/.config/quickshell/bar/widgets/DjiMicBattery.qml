import QtQuick
import qs.core as Core
import "../services/DjiMicBatteryParser.js" as DjiMicBatteryParser

Item {
    id: root
    required property Core.Theme theme
    required property bool available
    required property var transmitters
    required property string error
    signal refreshRequested(bool force)
    property bool tooltipVisible: false
    implicitWidth: micText.implicitWidth + 20
    implicitHeight: micText.implicitHeight + 4
    onVisibleChanged: {
        if (!visible) {
            tooltipDelay.stop();
            root.tooltipVisible = false;
        }
    }
    Text {
        id: micText
        anchors.centerIn: parent
        text: "󰍬 " + (root.available ? root.transmitters.map(tx => DjiMicBatteryParser.batteryIcon(tx.level) + (tx.charging ? " " : "")).join(" ") : "N/A")
        color: root.theme.timeDateColor
        font {
            family: root.theme.fontFamily
            pixelSize: root.theme.timeDateFontSize
            bold: true
        }
    }
    HoverHandler {
        id: micHover
        cursorShape: Qt.PointingHandCursor
        onHoveredChanged: {
            if (hovered) {
                root.refreshRequested(false);
                tooltipDelay.restart();
            } else {
                tooltipDelay.stop();
                root.tooltipVisible = false;
            }
        }
    }
    TapHandler {
        acceptedButtons: Qt.LeftButton
        onTapped: root.refreshRequested(true)
    }
    Timer {
        id: tooltipDelay
        interval: 300
        onTriggered: root.tooltipVisible = micHover.hovered && root.visible
    }
    SystemStatTooltip {
        visible: root.tooltipVisible
        anchorItem: root
        heading: "DJI Mic Mini"
        rows: root.available ? root.transmitters.map(tx => ({
                    label: tx.id.toUpperCase(),
                    value: (tx.level === null ? "Level unavailable" : tx.level === 1 ? "Full" : "Level " + tx.level + " / 7") + (tx.charging ? " · Charging" : " · Not charging")
                })) : [
            {
                label: "Status",
                value: root.error
            }
        ]
        theme: root.theme
    }
}
