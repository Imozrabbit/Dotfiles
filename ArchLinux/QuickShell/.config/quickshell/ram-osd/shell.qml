pragma ComponentBehavior: Bound
import Quickshell
import QtQuick

ShellRoot {
    id: root
    property string targetScreenName: "HDMI-A-1"

    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData
            screen: modelData
            visible: (modelData.name === root.targetScreenName)

            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            aboveWindows: false
            focusable: false
            color: "transparent"
            surfaceFormat.opaque: false

            anchors {
                top: true
                left: true
            }
            margins {
                top: 20
            }

            DottedBar {
                id: bar
                dots: 47
                value: Mem.used01
                w: 3
                h: 6
                r: 3
                gap: 2
                on: "#f2efe1ff"
                off: "#1ac9c4b8"
            }

            implicitWidth: bar.implicitWidth
            implicitHeight: bar.implicitHeight
        }
    }
}
