import QtQuick
import QtQuick.Layouts

Rectangle {
    required property var colors
    Layout.fillWidth: true
    color: colors.card
    radius: 8
    border.color: colors.border
}
