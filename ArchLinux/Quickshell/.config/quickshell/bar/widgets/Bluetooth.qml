import QtQuick

import qs.core as Core

Item {
    id: root

    required property Core.Theme theme
    required property bool available
    required property bool powered
    required property bool connected
    required property bool detailsKnown
    required property bool barRevealed
    required property var connectedDevices
    required property var disconnectedDevices
    required property bool actionBusy
    required property string actionAddress
    required property string actionError

    signal detailsRequested
    signal poweredRequested(bool enabled)
    signal connectRequested(string address)
    signal disconnectRequested(string address)
    signal managerRequested

    property bool tooltipVisible: false

    function bluetoothIcon() {
        return !root.available || !root.powered ? "󰂲" : root.connected ? "󰂱" : "";
    }

    function tooltipRows() {
        if (!root.available)
            return [
                {
                    label: "Status",
                    value: "Unavailable"
                }
            ];
        if (!root.powered)
            return [
                {
                    label: "Status",
                    value: "Powered off"
                }
            ];
        if (!root.detailsKnown)
            return [
                {
                    label: "Devices",
                    value: "Loading…"
                }
            ];
        if (root.connectedDevices.length === 0)
            return [
                {
                    label: "Devices",
                    value: "None connected"
                }
            ];
        return root.connectedDevices.map(device => ({
                    label: device.name,
                    value: device.battery >= 0 ? device.battery + "%" : "Connected"
                }));
    }

    implicitWidth: 38
    implicitHeight: iconText.implicitHeight + 4

    Text {
        id: iconText

        anchors.centerIn: parent
        text: root.bluetoothIcon()
        color: !root.available || !root.powered ? root.theme.bluetoothMutedColor : bluetoothHover.hovered ? root.theme.bluetoothHoverColor : root.connected ? root.theme.bluetoothConnectedColor : root.theme.bluetoothColor
        font {
            family: root.theme.fontFamily
            pixelSize: root.theme.volumeFontSize
            bold: true
        }
    }

    HoverHandler {
        id: bluetoothHover

        cursorShape: Qt.PointingHandCursor
        onHoveredChanged: {
            if (hovered && !bluetoothPanel.visible) {
                root.detailsRequested();
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
        onTriggered: root.tooltipVisible = bluetoothHover.hovered && !bluetoothPanel.visible
    }

    Timer {
        interval: 5000
        running: bluetoothPanel.visible
        repeat: true
        onTriggered: root.detailsRequested()
    }

    TapHandler {
        onTapped: {
            tooltipDelay.stop();
            root.tooltipVisible = false;
            bluetoothPanel.visible = !bluetoothPanel.visible;
            if (bluetoothPanel.visible)
                root.detailsRequested();
        }
    }

    SystemStatTooltip {
        visible: root.tooltipVisible
        anchorItem: root
        heading: "Bluetooth"
        rows: root.tooltipRows()
        theme: root.theme
    }

    BluetoothPanel {
        id: bluetoothPanel

        icon: root.bluetoothIcon()
        available: root.available
        powered: root.powered
        connectedDevices: root.connectedDevices
        disconnectedDevices: root.disconnectedDevices
        actionBusy: root.actionBusy
        actionAddress: root.actionAddress
        actionError: root.actionError
        barRevealed: root.barRevealed
        theme: root.theme
        onPoweredRequested: enabled => root.poweredRequested(enabled)
        onConnectRequested: address => root.connectRequested(address)
        onDisconnectRequested: address => root.disconnectRequested(address)
        onManagerRequested: {
            bluetoothPanel.visible = false;
            root.managerRequested();
        }
    }
}
