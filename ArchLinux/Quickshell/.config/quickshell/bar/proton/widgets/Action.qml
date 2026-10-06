import QtQuick
import QtQuick.Controls

Button {
    id: action
    required property var theme
    required property var colors
    implicitHeight: 30
    leftPadding: 12
    rightPadding: 12
    topPadding: 6
    bottomPadding: 6
    font.pixelSize: 13
    HoverHandler {
        cursorShape: action.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    }
    contentItem: Text {
        text: action.text
        color: action.flat ? (action.down ? action.colors.pressedText : action.hovered ? action.colors.hoverText : action.colors.secondary) : action.enabled ? (action.down ? action.colors.pressedText : action.hovered ? action.colors.hoverText : action.colors.accent) : action.colors.secondary
        opacity: action.enabled ? 1 : 0.55
        font.family: action.theme.fontFamily
        font.pixelSize: action.font.pixelSize
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
    background: Rectangle {
        visible: !action.flat
        radius: 5
        color: action.enabled && action.down ? action.colors.buttonPressed : action.hovered && action.enabled ? action.colors.buttonHover : action.colors.button
        border.color: action.colors.border
    }
}
