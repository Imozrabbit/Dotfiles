import QtQuick
import QtQuick.Controls
import "../common/Theme.js" as Theme

Button {
    id: root

    property string glyph: ""
    property string tooltip: ""
    property bool highlightChecked: true
    property var themeColors: Theme.colors
    property color iconColor: root.checked ? root.themeColors.onActive : root.themeColors.text
    property color fillColor: root.themeColors.tile
    property color hoverColor: root.themeColors.tileHover
    property color lineColor: root.themeColors.tileBorder

    implicitWidth: 64
    implicitHeight: 36
    padding: 0
    hoverEnabled: true
    Accessible.name: root.tooltip || root.glyph

    contentItem: Text {
        text: root.glyph
        color: root.enabled ? root.iconColor : Qt.darker(root.iconColor, 1.5)
        font.family: Theme.iconFont
        font.pixelSize: 18
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        textFormat: Text.PlainText
        maximumLineCount: 1
        elide: Text.ElideRight
        clip: true
    }

    background: Rectangle {
        radius: Theme.radius
        color: root.highlightChecked && root.checked ? (root.down ? Qt.darker(root.themeColors.tileActive, 1.2) : root.hovered || root.visualFocus ? Qt.lighter(root.themeColors.tileActive, 1.15) : root.themeColors.tileActive) : (root.down ? Qt.darker(root.hoverColor, 1.2) : root.hovered || root.visualFocus ? root.hoverColor : root.fillColor)
        border.width: border.color.a > 0 ? 1 : 0
        border.color: root.highlightChecked && root.checked ? root.themeColors.activeBorder : root.hovered || root.visualFocus ? root.themeColors.hoverBorder : root.lineColor

        Rectangle {
            visible: root.fillColor.a > 0 && color.a > 0
            x: 7
            y: 1
            width: parent.width - 14
            height: 1
            color: root.themeColors.bevel
        }

        Behavior on color {
            enabled: root.fillColor.a > 0
            ColorAnimation {
                duration: 150
            }
        }
    }

    HoverHandler {
        cursorShape: Qt.PointingHandCursor
    }
}
