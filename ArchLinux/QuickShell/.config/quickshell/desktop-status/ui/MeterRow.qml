pragma ComponentBehavior: Bound

import QtQuick
import ".." as Desktop

Item {
    id: root

    required property Desktop.Config config
    required property string label
    required property string valueText
    required property real fraction
    property int segments: 20
    signal refreshRequested(bool force)

    implicitHeight: line.implicitHeight + 12

    Text {
        id: line
        anchors.left: parent.left
        anchors.right: value.left
        anchors.rightMargin: 8
        text: root.label
        color: root.config.textColor
        font.family: root.config.fontFamily
        font.pixelSize: root.config.fontSize
        elide: Text.ElideRight
    }
    Text {
        id: value
        anchors.right: parent.right
        text: root.valueText
        color: root.config.textColor
        font.family: root.config.fontFamily
        font.pixelSize: root.config.fontSize
        rightPadding: Math.min(0, valueInk.tightBoundingRect.x + valueInk.tightBoundingRect.width - Math.ceil(valueInk.advanceWidth))
        TextMetrics {
            id: valueInk
            font: value.font
            text: value.text
        }
    }

    Row {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        spacing: 3

        Repeater {
            model: root.segments
            Rectangle {
                required property int index
                width: Math.max(0, (root.width - (root.segments - 1) * 3) / root.segments)
                height: 6
                color: root.fraction >= 0 && index < Math.round(Math.max(0, Math.min(1, root.fraction)) * root.segments) ? root.config.accentColor : root.config.trackColor
            }
        }
    }

    HoverHandler {
        cursorShape: Qt.PointingHandCursor
    }
    TapHandler {
        acceptedButtons: Qt.LeftButton
        onTapped: root.refreshRequested(true)
    }
}
