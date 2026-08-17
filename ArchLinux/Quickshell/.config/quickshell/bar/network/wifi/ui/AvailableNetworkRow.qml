import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

import "../WifiUtils.js" as WifiUtils

// Renders one available WiFi network and emits selection intent.
Rectangle {
    id: root

    required property var style
    required property string ssid
    required property string security
    required property int strength
    required property bool isEnterprise
    required property bool isBusy

    signal selected(string ssid, string security, bool isEnterprise)

    width: ListView.view ? ListView.view.width : 0
    height: 54
    radius: 12
    color: mouse.containsMouse ? Qt.rgba(style.accent.r, style.accent.g, style.accent.b, 0.10) : "transparent"
    border.width: mouse.containsMouse ? 1 : 0
    border.color: Qt.rgba(style.accent.r, style.accent.g, style.accent.b, 0.25)
    opacity: isBusy ? 0.6 : 1.0

    RowLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 10

        Label {
            text: WifiUtils.getSignalIcon(root.strength)
            font.family: root.style.iconFont
            font.pixelSize: 14
            color: root.style.success
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            Label {
                text: root.ssid || ""
                font.family: root.style.textFont
                font.pixelSize: 13
                font.weight: 500
                color: root.style.foreground
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            Label {
                text: WifiUtils.securityLabel(root.security, root.isEnterprise)
                font.family: root.style.textFont
                font.pixelSize: 10
                color: root.style.muted
            }
        }

        Label {
            text: root.security.trim() !== "" && root.security !== "--" ? "󰌾" : "󰦝"
            font.family: root.style.iconFont
            font.pixelSize: 12
            color: root.style.muted
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.isBusy ? Qt.ArrowCursor : Qt.PointingHandCursor
        enabled: !root.isBusy
        onClicked: root.selected(root.ssid, root.security, root.isEnterprise)
    }
}
