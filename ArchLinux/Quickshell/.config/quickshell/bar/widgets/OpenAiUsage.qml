import QtQuick
import QtQuick.Layouts

import qs.core as Core
import "../services/OpenAiUsage.js" as Usage

Rectangle {
    id: root

    required property Core.Theme theme
    required property var snapshot
    required property bool available
    required property string error
    required property date currentDate
    signal refreshRequested
    property bool tooltipVisible: false

    implicitWidth: content.implicitWidth + 16
    implicitHeight: content.implicitHeight + 4
    radius: root.theme.radiusMedium
    color: root.theme.openAiUsageBg

    function windowText(window) {
        const left = Usage.remaining(window);
        if (left === null)
            return "Unavailable";
        return Math.round(left) + "% remaining · resets in " + Usage.countdown(window.resetAt, root.currentDate.getTime());
    }

    function tooltipRows() {
        const rows = [];
        if (root.available && root.snapshot) {
            rows.push({
                label: "5-hour",
                value: root.windowText(root.snapshot.fiveHour)
            });
            rows.push({
                label: "Weekly",
                value: root.windowText(root.snapshot.weekly)
            });
            rows.push({
                label: "Plan",
                value: root.snapshot.plan
            });
            rows.push({
                label: "Status",
                value: root.snapshot.limitReached ? "Limit reached" : root.snapshot.allowed ? "Usage allowed" : "Usage not allowed"
            });
        } else {
            rows.push({
                label: "Status",
                value: root.error
            });
        }
        rows.push({
            label: "Updated",
            value: root.snapshot ? Qt.formatDateTime(new Date(root.snapshot.fetchedAt), "hh:mm:ss") : "Never"
        });
        return rows;
    }

    onVisibleChanged: {
        if (!visible) {
            tooltipDelay.stop();
            root.tooltipVisible = false;
        }
    }

    RowLayout {
        id: content
        anchors.centerIn: parent
        spacing: 6

        Image {
            source: Qt.resolvedUrl("../assets/openai.svg")
            sourceSize.width: root.theme.systemUsageFontSize
            sourceSize.height: root.theme.systemUsageFontSize
            Layout.preferredWidth: root.theme.systemUsageFontSize
            Layout.preferredHeight: root.theme.systemUsageFontSize
            opacity: root.available ? 1 : 0.5
        }

        Text {
            readonly property var remaining: root.available && root.snapshot ? Usage.remaining(root.snapshot.fiveHour) : null
            text: remaining === null ? "N/A" : Math.round(remaining) + "%"
            color: root.available ? root.theme.openAiUsageColor : root.theme.whiteMutedColor
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.systemUsageFontSize
            font.bold: true
        }
    }

    HoverHandler {
        id: usageHover
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
        onTriggered: root.tooltipVisible = usageHover.hovered && root.visible
    }

    SystemStatTooltip {
        visible: root.tooltipVisible
        anchorItem: root
        heading: "OpenAI Codex Usage"
        rows: root.tooltipVisible ? root.tooltipRows() : []
        theme: root.theme
    }
}
