import QtQuick
import QtQuick.Controls
import "../../common/Theme.js" as Theme

MenuItem {
    id: root

    property var themeColors: Theme.colors
    property string glyph: ""

    implicitHeight: 32
    padding: 6
    Accessible.name: text
    contentItem: Row {
        spacing: 8
        Text {
            objectName: "contextMenuIcon"
            width: 18
            height: root.availableHeight
            visible: root.glyph !== ""
            text: root.glyph
            font.family: Theme.iconFont
            font.pixelSize: 14
            color: root.themeColors.text
            verticalAlignment: Text.AlignVCenter
            textFormat: Text.PlainText
        }
        Text {
            objectName: "contextMenuLabel"
            width: Math.max(0, root.availableWidth - (root.glyph !== "" ? 26 : 0))
            height: root.availableHeight
            text: root.text
            font.family: Theme.textFont
            font.pixelSize: 12
            color: root.themeColors.text
            verticalAlignment: Text.AlignVCenter
            textFormat: Text.PlainText
            elide: Text.ElideRight
        }
    }
    background: Rectangle {
        radius: 6
        color: root.down ? Qt.darker(root.themeColors.tileHover, 1.2) : root.highlighted || root.hovered || root.visualFocus ? root.themeColors.tileHover : "transparent"
    }
}
