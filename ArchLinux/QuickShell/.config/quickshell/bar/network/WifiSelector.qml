pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Networking

import qs.core as Core

PopupWindow {
    id: root

    required property Item anchorItem
    required property Core.Theme theme

    // Keep the connected network first, then order nearby networks by signal strength.
    readonly property var networks: {
        if (!root.wifiDevice)
            return [];
        return root.wifiDevice.networks.values.slice().sort((a, b) => {
            if (a.connected !== b.connected)
                return a.connected ? -1 : 1;
            return b.signalStrength - a.signalStrength;
        });
    }

    readonly property var wifiDevices: Networking.devices.values.filter(device => device.type === DeviceType.Wifi)
    // Prefer the connected adapter; otherwise use the first available Wi-Fi adapter.
    readonly property var wifiDevice: {
        const connectedDevice = root.wifiDevices.find(device => device.connected);
        return connectedDevice || root.wifiDevices[0] || null;
    }

    function statusText() {
        if (!Networking.wifiEnabled)
            return "Wi-Fi is off";
        if (!root.wifiDevice)
            return "No Wi-Fi adapter";
        return "Adapter: " + root.wifiDevice.name;
    }

    visible: false
    implicitWidth: 320
    implicitHeight: 360
    color: "transparent"
    grabFocus: true

    anchor.item: root.anchorItem
    anchor.rect.x: 0
    anchor.rect.y: -8
    anchor.rect.width: root.anchorItem.width
    anchor.rect.height: root.anchorItem.height
    anchor.edges: Edges.Top
    anchor.gravity: Edges.Top

    // Scan only while this popup is open to avoid continuous background work.
    Binding {
        target: root.wifiDevice
        property: "scannerEnabled"
        value: root.visible && Networking.wifiEnabled
        when: root.wifiDevice !== null
    }

    Rectangle {
        anchors.fill: parent
        color: root.theme.wifiSelectorBg
        border.color: root.theme.wifiSelectorBorderColor
        border.width: 1
        radius: root.theme.radiusMedium
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 24
                Layout.maximumHeight: 24

                Text {
                    Layout.leftMargin: 4
                    text: "Wi-Fi"
                    color: root.theme.wifiSelectorHeaderColor
                    font {
                        family: root.theme.wifiSelectorFontFamily
                        pixelSize: root.theme.wifiSelectorHeaderFontSize
                        bold: true
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                Switch {
                    id: wifiToggle
                    Layout.rightMargin: 4

                    checked: Networking.wifiEnabled
                    onToggled: Networking.wifiEnabled = checked

                    implicitWidth: 38
                    implicitHeight: 20
                    contentItem: null

                    indicator: Rectangle {
                        width: 38
                        height: 20
                        y: (wifiToggle.height - height) / 2
                        radius: height / 2

                        color: wifiToggle.checked ? root.theme.wifiSelectorHeaderColor : root.theme.wifiSelectorMutedColor
                        border.color: root.theme.wifiSelectorBorderColor
                        border.width: 1

                        Rectangle {
                            width: 14
                            height: 14
                            radius: width / 2
                            anchors.verticalCenter: parent.verticalCenter

                            x: wifiToggle.checked ? parent.width - width - 3 : 3

                            color: wifiToggle.checked ? root.theme.wifiSelectorBg : root.theme.wifiSelectorTextColor

                            Behavior on x {
                                NumberAnimation {
                                    duration: 120
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: root.theme.wifiSelectorBorderColor
            }

            Text {
                Layout.fillHeight: !networkList.visible
                Layout.alignment: Qt.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: root.statusText()
                color: root.theme.wifiSelectorMutedColor
                font {
                    family: root.theme.wifiSelectorFontFamily
                    pixelSize: root.theme.wifiSelectorBodyFontSize
                }
            }

            ListView {
                id: networkList

                Layout.fillWidth: true
                Layout.fillHeight: true

                visible: Networking.wifiEnabled && root.wifiDevice !== null
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                model: root.networks

                ScrollBar.vertical: ScrollBar {}

                delegate: WifiNetworkRow {
                    required property var modelData
                    width: networkList.width
                    network: modelData
                    theme: root.theme
                }
            }
        }
    }
}
