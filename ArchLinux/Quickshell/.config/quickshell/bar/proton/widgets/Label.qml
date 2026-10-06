import QtQuick
import QtQuick.Layouts

Text {
    required property var theme
    required property var colors
    color: colors.foreground
    font.family: theme.fontFamily
    font.pixelSize: 14
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
    Layout.fillWidth: true
}
