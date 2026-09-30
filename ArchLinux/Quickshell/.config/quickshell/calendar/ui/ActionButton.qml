pragma ComponentBehavior: Bound
import QtQuick
import "../common/Theme.js" as Theme

Rectangle {
    id: root

    required property string label
    property bool primary: false
    property bool destructive: false
    property int minimumWidth: 80
    signal clicked

    implicitWidth: Math.max(root.minimumWidth, buttonLabel.implicitWidth + 28)
    implicitHeight: 34
    radius: Theme.radius
    color: root.primary ? buttonHover.hovered ? Qt.lighter(Theme.accent, 1.12) : Theme.accent : buttonHover.hovered ? Theme.surfaceRaised : Theme.background
    border.width: root.primary ? 0 : 1
    border.color: root.destructive ? Theme.currentTime : Theme.border

    Text {
        id: buttonLabel
        anchors.centerIn: parent
        text: root.label
        textFormat: Text.PlainText
        color: root.primary ? Theme.background : root.destructive ? Theme.currentTime : Theme.text
        font.pixelSize: 13
        font.weight: Font.DemiBold
    }

    HoverHandler {
        id: buttonHover
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.clicked()
    }
}
