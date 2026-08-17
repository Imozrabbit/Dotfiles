import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

import "../WifiUtils.js" as WifiUtils

// Renders radio controls and current WiFi connection details.
ColumnLayout {
    id: root

    required property var controller
    required property var style

    Layout.fillWidth: true
    spacing: 8

    RowLayout {
        Layout.fillWidth: true

        Label {
            text: "Internet"
            font.family: root.style.textFont
            font.pixelSize: 18
            font.weight: 700
            color: root.style.foreground
            Layout.fillWidth: true
        }

        Rectangle {
            width: 46
            height: 24
            radius: 12
            color: root.controller.wifiEnabled ? Qt.rgba(root.style.success.r, root.style.success.g, root.style.success.b, 0.95) : root.style.backgroundAlt
            border.width: 1
            border.color: root.controller.wifiEnabled ? Qt.rgba(root.style.success.r, root.style.success.g, root.style.success.b, 0.55) : root.style.border
            opacity: root.controller.isBusy ? 0.6 : 1.0

            Rectangle {
                width: 18
                height: 18
                radius: 9
                color: root.style.card
                anchors.verticalCenter: parent.verticalCenter
                x: root.controller.wifiEnabled ? parent.width - width - 3 : 3

                Behavior on x {
                    NumberAnimation {
                        duration: 180
                        easing.type: Easing.OutCubic
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: root.controller.isBusy ? Qt.ArrowCursor : Qt.PointingHandCursor
                enabled: !root.controller.isBusy
                onClicked: root.controller.toggleWifi()
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        height: 76
        radius: 8
        color: root.style.backgroundAlt

        RowLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 12

            Rectangle {
                width: 44
                height: 44
                radius: 14
                color: "transparent"

                Label {
                    anchors.centerIn: parent
                    text: root.controller.wifiEnabled ? WifiUtils.getSignalIcon(root.controller.currentSignalVal) : "󰤮"
                    font.pixelSize: 22
                    font.family: root.style.iconFont
                    color: root.controller.wifiEnabled ? root.style.success : root.style.muted
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Label {
                    text: root.controller.currentSsid
                    font.family: root.style.textFont
                    font.pixelSize: 14
                    font.weight: 600
                    color: root.style.foreground
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                Label {
                    text: root.controller.currentIp && root.controller.currentIp.length > 0 ? root.controller.currentIp : (root.controller.wifiEnabled ? "No IP address" : "WiFi disabled")
                    font.family: root.style.textFont
                    font.pixelSize: 12
                    color: root.style.muted
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }

            Rectangle {
                visible: root.controller.wifiEnabled && root.controller.activeConnectionUuid !== ""
                width: 36
                height: 36
                radius: 12
                color: disconnectMouse.containsMouse ? Qt.rgba(root.style.error.r, root.style.error.g, root.style.error.b, 0.12) : "transparent"
                border.width: disconnectMouse.containsMouse ? 1 : 0
                border.color: Qt.rgba(root.style.error.r, root.style.error.g, root.style.error.b, 0.35)
                opacity: root.controller.isBusy ? 0.6 : 1.0

                Label {
                    anchors.centerIn: parent
                    text: "󰅙"
                    font.family: root.style.iconFont
                    color: root.style.error
                    font.pixelSize: 16
                }

                MouseArea {
                    id: disconnectMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: root.controller.isBusy ? Qt.ArrowCursor : Qt.PointingHandCursor
                    enabled: !root.controller.isBusy
                    onClicked: root.controller.disconnectNetwork()
                }
            }
        }
    }
}
