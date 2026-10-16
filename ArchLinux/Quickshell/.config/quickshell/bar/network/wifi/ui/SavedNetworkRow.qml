import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "./controls"

// Renders one saved WiFi profile and emits connection intent.
Rectangle {
    id: root

    required property var style
    required property string ssid
    required property string uuid
    required property string name
    required property bool isEnterprise
    required property bool isBusy
    property bool expanded: false
    property bool isConnected: false
    property bool isHome: false
    required property var dnsBackend

    signal clicked(string uuid, string ssid, bool isEnterprise)
    signal toggleRequested

    width: ListView.view ? ListView.view.width : 0
    height: 35 + (root.expanded ? dnsOptions.implicitHeight + 12 : 0)
    radius: 12
    color: mouse.containsMouse ? Qt.rgba(style.accent.r, style.accent.g, style.accent.b, 0.10) : "transparent"
    border.width: mouse.containsMouse ? 1 : 0
    border.color: Qt.rgba(style.accent.r, style.accent.g, style.accent.b, 0.25)
    opacity: isBusy ? 0.6 : 1.0

    RowLayout {
        x: 10
        y: 0
        width: parent.width - 110
        height: 35
        spacing: 10

        Label {
            text: "󰤨"
            font.family: root.style.iconFont
            font.pixelSize: 14
            color: root.style.success
        }

        Label {
            text: root.name || root.ssid || ""
            font.family: root.style.textFont
            font.pixelSize: 13
            font.weight: 500
            color: root.style.foreground
            Layout.fillWidth: true
            elide: Text.ElideRight
        }

        Label {
            text: root.isConnected ? "Connected" : "Saved"
            font.family: root.style.textFont
            font.pixelSize: 10
            color: root.style.muted
        }
        Label {
            text: root.expanded ? "⌃" : "⌄"
            color: root.style.muted
        }
    }

    MouseArea {
        id: mouse

        width: parent.width - (root.isConnected ? 0 : 90)
        height: 35
        hoverEnabled: true
        cursorShape: root.isBusy ? Qt.ArrowCursor : Qt.PointingHandCursor
        enabled: !root.isBusy
        onClicked: root.toggleRequested()
    }
    MenuButton {
        anchors.right: parent.right
        anchors.rightMargin: 5
        y: 4
        width: 80
        height: 26
        visible: !root.isConnected
        text: "Connect"
        style: root.style
        disabled: root.isBusy
        onClicked: root.clicked(root.uuid, root.ssid, root.isEnterprise)
    }
    DnsSettingsPage {
        id: dnsOptions
        x: 12
        y: 40
        width: parent.width - 24
        visible: root.expanded
        style: root.style
        profileUuid: root.uuid
        backend: root.dnsBackend
        isHome: root.isHome
    }
}
