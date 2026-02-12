pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: root
    property int dots: 10
    property int w: 10
    property int h: 7
    property int r: 3
    property int gap: 3

    property color on: "red"
    property color off: "yellow"

    implicitWidth: w
    implicitHeight: dots * h + (dots - 1) * gap

    property real value: 0.5
    readonly property int filled: Math.max(0, Math.min(dots, Math.round(value * dots)))

    Column {
        spacing: root.gap
        Repeater {
            model: root.dots
            Rectangle {
                required property int index
                // Fill from top to bottom
                readonly property bool active: (index >= root.dots - root.filled)
                width: root.w
                height: root.h
                radius: root.r
                color: (active === true) ? root.on : root.off
            }
        }
    }
}
