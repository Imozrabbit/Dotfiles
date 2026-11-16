pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import "../common/Theme.js" as Theme

Button {
    id: control
    required property color fillColor
    property string fontFamily: Theme.iconFont
    readonly property color hoverColor: Qt.lighter(control.fillColor, 1.5)
    padding: 7
    topPadding: 5
    bottomPadding: 5
    hoverEnabled: true
    contentItem: Text {
        text: control.text
        color: control.enabled ? "#c3c3c5" : "#8e8fe0"
        font.family: control.fontFamily
        font.pixelSize: 12
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
    }
    background: Rectangle {
        radius: 6
        color: control.down ? Qt.darker(control.hoverColor, 1.2) : control.hovered || control.visualFocus ? control.hoverColor : control.fillColor
        border.width: control.visualFocus ? 1 : 0
        border.color: "#8e8fe0"
    }
    HoverHandler {
        enabled: control.enabled
        cursorShape: Qt.PointingHandCursor
    }
}
