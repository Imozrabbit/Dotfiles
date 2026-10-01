import QtQuick

import qs.core as Core

Item {
    id: root

    required property Core.Theme theme
    required property string mouseName
    required property bool available
    required property int percentage
    required property bool charging
    required property string connection
    required property string error

    signal refreshRequested
    property bool tooltipVisible: false

    implicitWidth: mouseText.implicitWidth + 20
    implicitHeight: mouseText.implicitHeight + 4

    onVisibleChanged: {
        if (!visible) {
            tooltipDelay.stop();
            root.tooltipVisible = false;
        }
    }

    Text {
        id: mouseText
        anchors.centerIn: parent
        text: "󰍽 " + (root.available ? root.percentage + "%" : "N/A")
        color: root.theme.timeDateColor
        font {
            family: root.theme.fontFamily
            pixelSize: root.theme.timeDateFontSize
            bold: true
        }
    }

    HoverHandler {
        id: mouseHover
        onHoveredChanged: {
            if (hovered) {
                root.refreshRequested();
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
        onTriggered: root.tooltipVisible = mouseHover.hovered && root.visible
    }

    SystemStatTooltip {
        visible: root.tooltipVisible
        anchorItem: root
        heading: root.mouseName
        rows: {
            const result = [
                {
                    label: "Connection",
                    value: root.available ? (root.connection === "wired" ? "Wired" : "Wireless") : "Unavailable"
                },
                {
                    label: "Charging",
                    value: root.available ? (root.charging ? "Yes" : "No") : "Unavailable"
                }
            ];
            if (!root.available)
                result.push({
                    label: "Status",
                    value: root.error
                });
            return result;
        }
        theme: root.theme
    }
}
