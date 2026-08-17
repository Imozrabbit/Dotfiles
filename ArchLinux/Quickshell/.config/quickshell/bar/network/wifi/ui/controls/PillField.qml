import QtQuick
import QtQuick.Layouts

// Renders a pill-shaped WiFi credential field and emits acceptance intent.
Rectangle {
    id: root

    required property var style

    property alias text: input.text
    property string placeholder: ""
    property int echoMode: TextInput.Normal

    signal accepted

    Layout.preferredHeight: 42
    radius: 999
    color: style.backgroundAlt
    border.width: 1
    border.color: input.activeFocus ? Qt.rgba(style.success.r, style.success.g, style.success.b, 0.7) : style.border
    opacity: enabled ? 1.0 : 0.6
    clip: true

    TextInput {
        id: input

        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        color: root.style.foreground
        font.family: root.style.textFont
        font.pixelSize: 13
        echoMode: root.echoMode
        verticalAlignment: TextInput.AlignVCenter
        selectByMouse: true
        activeFocusOnTab: true
        Keys.onReturnPressed: root.accepted()
    }

    Text {
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        text: root.placeholder
        color: root.style.muted
        font.family: root.style.textFont
        font.pixelSize: 13
        visible: input.text.length === 0 && !input.activeFocus
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.IBeamCursor
        onClicked: input.forceActiveFocus()
    }
}
