import QtQuick

import qs.core as Core

Item {
    id: root

    required property bool available
    required property int capacity
    required property string status
    required property bool acOnline
    required property real energyNowUwh
    required property real energyFullUwh
    required property real energyFullDesignUwh
    required property real powerNowUw
    required property int chargeStartThreshold
    required property int chargeEndThreshold
    required property int cycleCount
    required property string activePowerProfile
    required property bool actionBusy
    required property string actionError
    required property Core.Theme theme

    signal panelOpened
    signal powerProfileRequested(string profile)
    signal chargeThresholdsRequested(int startValue, int endValue)

    property bool tooltipVisible: false

    readonly property var dischargingIcons: ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
    readonly property var chargingIcons: ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"]

    function levelIndex() {
        return Math.max(0, Math.min(9, Math.ceil(root.capacity / 10) - 1));
    }

    function batteryIcon() {
        if (!root.available)
            return "󰂑";
        if (root.status === "Full")
            return root.acOnline ? "" : root.dischargingIcons[9];
        if (root.status === "Charging")
            return root.chargingIcons[root.levelIndex()];
        if (root.status === "Not charging" && root.acOnline)
            return "";
        if (root.status === "Discharging")
            return root.dischargingIcons[root.levelIndex()];
        return "󰂑";
    }

    function statusText() {
        return root.status + " · " + (root.acOnline ? "AC" : "Battery");
    }

    function formatDuration(hours) {
        if (!isFinite(hours) || hours < 0)
            return "";

        const rawMinutes = hours * 60;
        const totalMinutes = rawMinutes === 0 ? 0 : Math.max(1, Math.round(rawMinutes));
        const hourPart = Math.floor(totalMinutes / 60);
        const minutePart = totalMinutes % 60;
        if (hourPart <= 0)
            return minutePart + "m";
        return hourPart + "h" + (minutePart > 0 ? " " + minutePart + "m" : "");
    }

    function estimatedTime() {
        if (root.powerNowUw <= 0)
            return "";
        if (root.status === "Discharging" && root.energyNowUwh >= 0)
            return root.formatDuration(root.energyNowUwh / root.powerNowUw) + " remaining";
        if (root.status === "Charging" && root.energyFullUwh >= root.energyNowUwh && root.energyNowUwh >= 0)
            return root.formatDuration((root.energyFullUwh - root.energyNowUwh) / root.powerNowUw) + " to full";
        return "";
    }

    function rateText() {
        if (root.powerNowUw < 0)
            return "N/A";
        if (root.powerNowUw === 0 || root.status === "Full" || root.status === "Not charging")
            return "Idle";

        const watts = (root.powerNowUw / 1000000).toFixed(1) + " W";
        if (root.status === "Charging")
            return watts + " charge";
        if (root.status === "Discharging")
            return watts + " discharge";
        return "N/A";
    }

    function thresholdText() {
        if (root.chargeStartThreshold < 0 || root.chargeEndThreshold < 0)
            return "N/A";
        return root.chargeStartThreshold + "–" + root.chargeEndThreshold + "%";
    }

    function tooltipRows() {
        const rows = [
            {
                label: "Status",
                value: root.statusText()
            }
        ];
        const time = root.estimatedTime();
        if (time !== "")
            rows.push({
                label: "Time",
                value: time
            });
        rows.push({
            label: "Rate",
            value: root.rateText()
        });
        rows.push({
            label: "Charge limits",
            value: root.thresholdText()
        });
        return rows;
    }

    implicitWidth: batteryText.implicitWidth + 20
    implicitHeight: batteryText.implicitHeight + 4

    Text {
        id: batteryText

        anchors.centerIn: parent
        text: root.batteryIcon() + " " + (root.available ? root.capacity + "%" : "N/A")
        color: root.theme.timeDateColor
        font {
            family: root.theme.fontFamily
            pixelSize: root.theme.timeDateFontSize
            bold: true
        }
    }

    HoverHandler {
        id: batteryHover

        cursorShape: Qt.PointingHandCursor

        onHoveredChanged: {
            if (hovered && !batteryPanel.visible) {
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
        onTriggered: root.tooltipVisible = batteryHover.hovered && !batteryPanel.visible
    }

    TapHandler {
        onTapped: {
            tooltipDelay.stop();
            root.tooltipVisible = false;
            batteryPanel.visible = !batteryPanel.visible;
            if (batteryPanel.visible)
                root.panelOpened();
        }
    }

    SystemStatTooltip {
        visible: root.tooltipVisible
        anchorItem: root
        heading: "Battery"
        rows: root.tooltipRows()
        theme: root.theme
    }

    BatteryPanel {
        id: batteryPanel

        anchorItem: root
        icon: root.batteryIcon()
        available: root.available
        capacity: root.capacity
        status: root.status
        acOnline: root.acOnline
        energyFullUwh: root.energyFullUwh
        energyFullDesignUwh: root.energyFullDesignUwh
        cycleCount: root.cycleCount
        chargeStartThreshold: root.chargeStartThreshold
        chargeEndThreshold: root.chargeEndThreshold
        activePowerProfile: root.activePowerProfile
        actionBusy: root.actionBusy
        actionError: root.actionError
        theme: root.theme
        onPowerProfileRequested: profile => root.powerProfileRequested(profile)
        onChargeThresholdsRequested: (startValue, endValue) => root.chargeThresholdsRequested(startValue, endValue)
    }
}
