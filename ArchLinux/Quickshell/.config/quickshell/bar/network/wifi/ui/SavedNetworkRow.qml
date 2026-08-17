import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// Renders one saved WiFi profile and emits connection intent.
Rectangle {
    id: root

    required property var style
    required property string ssid
    required property string uuid
    required property string name
    required property bool isBusy

    signal clicked(string uuid, string ssid)

    width: ListView.view ? ListView.view.width : 0
    height: 35
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
            text: "Saved"
            font.family: root.style.textFont
            font.pixelSize: 10
            color: root.style.muted
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.isBusy ? Qt.ArrowCursor : Qt.PointingHandCursor
        enabled: !root.isBusy
        onClicked: root.clicked(root.uuid, root.ssid)
    }
}
