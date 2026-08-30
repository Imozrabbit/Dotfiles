pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

import qs.core as Core

PanelWindow {
    id: root

    required property string icon
    required property bool available
    required property bool powered
    required property var connectedDevices
    required property var disconnectedDevices
    required property bool actionBusy
    required property string actionAddress
    required property string actionError
    required property bool barRevealed
    required property Core.Theme theme

    signal poweredRequested(bool enabled)
    signal connectRequested(string address)
    signal disconnectRequested(string address)
    signal managerRequested

    function deviceGlyph(icon) {
        if (icon.indexOf("keyboard") !== -1)
            return "󰌌";
        if (icon.indexOf("mouse") !== -1)
            return "󰍽";
        if (icon.indexOf("head") !== -1 || icon.indexOf("audio") !== -1)
            return "󰋋";
        return "";
    }

    component DeviceRow: Rectangle {
        id: deviceRow

        required property var device
        required property bool connected

        Layout.fillWidth: true
        implicitHeight: device.battery >= 0 ? 72 : 56
        color: root.theme.bluetoothPanelCardColor
        border.color: root.theme.bluetoothPanelBorderColor
        border.width: 1
        radius: 6

        RowLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10

            Text {
                text: root.deviceGlyph(deviceRow.device.icon)
                color: deviceRow.connected ? root.theme.bluetoothConnectedColor : root.theme.bluetoothPanelMutedColor
                font {
                    family: root.theme.fontFamily
                    pixelSize: root.theme.bluetoothPanelHeaderFontSize
                    bold: true
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3

                Text {
                    Layout.fillWidth: true
                    text: deviceRow.device.name
                    color: root.theme.bluetoothPanelTextColor
                    elide: Text.ElideRight
                    font {
                        family: root.theme.fontFamily
                        pixelSize: root.theme.bluetoothPanelFontSize + 1
                        bold: true
                    }
                }

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        Layout.fillWidth: true
                        text: deviceRow.device.address
                        color: root.theme.bluetoothPanelMutedColor
                        font {
                            family: root.theme.fontFamily
                            pixelSize: root.theme.bluetoothPanelFontSize - 1
                        }
                    }

                    Text {
                        visible: deviceRow.device.battery >= 0
                        text: deviceRow.device.battery + "%"
                        color: root.theme.bluetoothPanelAccentColor
                        font {
                            family: root.theme.fontFamily
                            pixelSize: root.theme.bluetoothPanelFontSize
                            bold: true
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 6
                    visible: deviceRow.device.battery >= 0
                    color: root.theme.bluetoothPanelTrackColor
                    radius: height / 2

                    Rectangle {
                        width: parent.width * deviceRow.device.battery / 100
                        height: parent.height
                        color: root.theme.bluetoothPanelAccentColor
                        radius: parent.radius
                    }
                }
            }

            Button {
                id: actionButton

                Layout.preferredWidth: 88
                Layout.preferredHeight: 30
                enabled: root.powered && !root.actionBusy
                onClicked: {
                    if (deviceRow.connected)
                        root.disconnectRequested(deviceRow.device.address);
                    else
                        root.connectRequested(deviceRow.device.address);
                }

                contentItem: Text {
                    text: root.actionBusy && root.actionAddress === deviceRow.device.address ? "Working…" : deviceRow.connected ? "Disconnect" : "Connect"
                    color: actionButton.enabled ? root.theme.bluetoothPanelAccentColor : root.theme.bluetoothPanelMutedColor
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font {
                        family: root.theme.fontFamily
                        pixelSize: root.theme.bluetoothPanelFontSize
                        bold: true
                    }
                }

                background: Rectangle {
                    color: actionButton.hovered && actionButton.enabled ? Qt.lighter(root.theme.bluetoothPanelButtonColor, 1.2) : root.theme.bluetoothPanelButtonColor
                    border.color: actionButton.enabled ? root.theme.bluetoothPanelAccentColor : root.theme.bluetoothPanelBorderColor
                    border.width: 1
                    radius: 4
                }

                HoverHandler {
                    cursorShape: actionButton.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                }
            }
        }
    }

    visible: false
    color: "transparent"
    focusable: true

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.namespace: "bluetooth-menu"

    Shortcut {
        sequence: "Esc"
        enabled: root.visible
        onActivated: root.visible = false
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: mouse => {
            const inside = mouse.x >= panelCard.x && mouse.x <= panelCard.x + panelCard.width && mouse.y >= panelCard.y && mouse.y <= panelCard.y + panelCard.height;
            if (!inside)
                root.visible = false;
        }
    }

    Rectangle {
        id: panelCard

        width: 430
        height: panelContent.implicitHeight + 32
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: root.barRevealed ? 17 : 10
        anchors.bottomMargin: root.barRevealed ? 40 : 10
        color: root.theme.bluetoothPanelBackgroundColor
        border.color: root.theme.bluetoothPanelBorderColor
        border.width: 1
        radius: root.theme.radiusMedium

        ColumnLayout {
            id: panelContent

            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    text: root.icon
                    color: root.powered ? root.theme.bluetoothPanelAccentColor : root.theme.bluetoothPanelMutedColor
                    font {
                        family: root.theme.fontFamily
                        pixelSize: root.theme.bluetoothPanelHeaderFontSize
                        bold: true
                    }
                }

                ColumnLayout {
                    spacing: 0

                    Text {
                        text: "Bluetooth"
                        color: root.theme.bluetoothPanelTextColor
                        font {
                            family: root.theme.fontFamily
                            pixelSize: root.theme.bluetoothPanelFontSize + 4
                            bold: true
                        }
                    }

                    Text {
                        text: !root.available ? "UNAVAILABLE" : root.powered ? "POWERED ON" : "POWERED OFF"
                        color: root.theme.bluetoothPanelMutedColor
                        font {
                            family: root.theme.fontFamily
                            pixelSize: root.theme.bluetoothPanelFontSize
                            bold: true
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                Button {
                    id: powerButton

                    Layout.preferredHeight: 30
                    enabled: root.available && !root.actionBusy
                    onClicked: root.poweredRequested(!root.powered)

                    contentItem: Text {
                        text: root.powered ? "Turn off" : "Turn on"
                        color: powerButton.enabled ? root.theme.bluetoothPanelAccentColor : root.theme.bluetoothPanelMutedColor
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font {
                            family: root.theme.fontFamily
                            pixelSize: root.theme.bluetoothPanelFontSize
                            bold: true
                        }
                    }

                    background: Rectangle {
                        color: powerButton.hovered && powerButton.enabled ? Qt.lighter(root.theme.bluetoothPanelButtonColor, 1.2) : root.theme.bluetoothPanelButtonColor
                        border.color: powerButton.enabled ? root.theme.bluetoothPanelAccentColor : root.theme.bluetoothPanelBorderColor
                        border.width: 1
                        radius: 4
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: root.theme.bluetoothPanelBorderColor
                opacity: 0.2
            }

            Text {
                text: "CONNECTED DEVICES"
                color: root.theme.bluetoothPanelMutedColor
                font {
                    family: root.theme.fontFamily
                    pixelSize: root.theme.bluetoothPanelFontSize
                    bold: true
                }
            }

            Repeater {
                model: root.connectedDevices
                delegate: DeviceRow {
                    required property var modelData
                    device: modelData
                    connected: true
                }
            }

            Text {
                visible: root.connectedDevices.length === 0
                text: root.powered ? "No connected devices" : "Bluetooth is off"
                color: root.theme.bluetoothPanelMutedColor
                font {
                    family: root.theme.fontFamily
                    pixelSize: root.theme.bluetoothPanelFontSize
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: root.theme.bluetoothPanelBorderColor
                opacity: 0.2
            }

            Text {
                text: "PAIRED DEVICES"
                color: root.theme.bluetoothPanelMutedColor
                font {
                    family: root.theme.fontFamily
                    pixelSize: root.theme.bluetoothPanelFontSize
                    bold: true
                }
            }

            Repeater {
                model: root.disconnectedDevices
                delegate: DeviceRow {
                    required property var modelData
                    device: modelData
                    connected: false
                }
            }

            Text {
                visible: root.disconnectedDevices.length === 0
                text: "No disconnected paired devices"
                color: root.theme.bluetoothPanelMutedColor
                font {
                    family: root.theme.fontFamily
                    pixelSize: root.theme.bluetoothPanelFontSize
                }
            }

            Text {
                Layout.fillWidth: true
                visible: root.actionError !== ""
                text: root.actionError
                color: root.theme.bluetoothPanelErrorColor
                horizontalAlignment: Text.AlignRight
                font {
                    family: root.theme.fontFamily
                    pixelSize: root.theme.bluetoothPanelFontSize
                }
            }

            Button {
                id: managerButton

                Layout.fillWidth: true
                Layout.preferredHeight: 32
                onClicked: root.managerRequested()

                contentItem: Text {
                    text: "Open advanced manager"
                    color: root.theme.bluetoothPanelAccentColor
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font {
                        family: root.theme.fontFamily
                        pixelSize: root.theme.bluetoothPanelFontSize
                        bold: true
                    }
                }

                background: Rectangle {
                    color: managerButton.hovered ? Qt.lighter(root.theme.bluetoothPanelButtonColor, 1.2) : root.theme.bluetoothPanelButtonColor
                    border.color: root.theme.bluetoothPanelBorderColor
                    border.width: 1
                    radius: 4
                }

                HoverHandler {
                    cursorShape: Qt.PointingHandCursor
                }
            }
        }
    }
}
