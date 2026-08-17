import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

Rectangle {
    id: root

    required property string iconName
    required property real fillLevel
    required property string label

    property int animationDurationMs: 80

    implicitWidth: 280
    implicitHeight: 40
    radius: height / 2
    color: "#4d2c2c2c"

    RowLayout {
        anchors {
            fill: parent
            leftMargin: 16
            rightMargin: 16
        }
        spacing: 10

        IconImage {
            Layout.alignment: Qt.AlignVCenter
            implicitSize: 25
            source: Quickshell.iconPath(root.iconName)
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 8
            Layout.alignment: Qt.AlignVCenter
            radius: height / 2
            color: "#33ffffff"
            clip: true

            Rectangle {
                anchors {
                    left: parent.left
                    top: parent.top
                    bottom: parent.bottom
                }
                width: parent.width * Math.max(0, Math.min(root.fillLevel, 1))
                radius: parent.radius
                color: "#ffffffff"

                Behavior on width {
                    NumberAnimation {
                        duration: root.animationDurationMs
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

        Text {
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: 42
            text: root.label
            color: "#ffffffff"
            font.pixelSize: 14
            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignVCenter
        }
    }
}
