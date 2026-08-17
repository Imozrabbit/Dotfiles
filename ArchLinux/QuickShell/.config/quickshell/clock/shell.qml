pragma ComponentBehavior: Bound
import Quickshell
import QtQuick

ShellRoot {
    id: root
    property string targetScreenName: "HDMI-A-1"
    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: window
            required property var modelData
            screen: modelData

            // Only show on the target monitor
            visible: (modelData.name === root.targetScreenName)

            // OSD behavior
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            aboveWindows: false
            focusable: false

            // transparency from the start
            color: "transparent"
            surfaceFormat.opaque: false

            // size wraps content
            implicitWidth: content.implicitWidth
            implicitHeight: content.implicitHeight

            // Position
            anchors {
                top: true
                left: true
            }
            margins {
                top: 15
                left: 10
            }

            // Actual Clock + date
            property int sizeHM: 120
            property int sizeSec: 90
            property int dateSize: 40
            property int padx: 100
            property int pady: 10
            Item {
                id: content
                implicitWidth: 515
                implicitHeight: clockCol.implicitHeight + window.pady * 2
                // Date (top-right of the clock block)
                Row {
                    id: dateCol
                    spacing: 35
                    anchors.right: parent.right
                    anchors.rightMargin: 32
                    Text {
                        id: week
                        text: Qt.formatDate(clock.date, "ddd")
                        font.family: "BigBlueTermPlus Nerd Font"
                        font.pixelSize: window.dateSize
                        color: "#e9e1e1e2"
                    }
                    Text {
                        id: day
                        text: Qt.formatDate(clock.date, "d")
                        font.family: "BigBlueTermPlus Nerd Font"
                        font.pixelSize: window.dateSize
                        color: "#e9e1e1e2"
                    }
                    Text {
                        id: month
                        text: Qt.formatDate(clock.date, "MMM")
                        font.family: "BigBlueTermPlus Nerd Font"
                        font.pixelSize: window.dateSize
                        color: "#e9e1e1e2"
                    }
                }
                // Clock (centered)
                Column {
                    id: clockCol
                    anchors.left: parent.left
                    anchors.leftMargin: 9
                    anchors.top: parent.top
                    anchors.topMargin: 7
                    spacing: 20
                    Text {
                        id: hour
                        width: clockCol.width
                        text: Qt.formatTime(clock.date, "HH")
                        font.family: "ttyclock"
                        font.pixelSize: window.sizeHM
                        color: "#f2efe1ff"
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Text {
                        id: min
                        width: clockCol.width
                        text: Qt.formatTime(clock.date, "mm")
                        font.family: "ttyclock"
                        font.pixelSize: window.sizeHM
                        color: "#f2efe1ff"
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Text {
                        id: sec
                        width: clockCol.width
                        text: Qt.formatTime(clock.date, "ss")
                        font.family: "ttyclock"
                        font.pixelSize: window.sizeSec
                        color: "#cfcfcfff"
                        horizontalAlignment: Text.AlignHCenter
                    }
                    // Make column width stable (so seconds stays centered)
                    width: Math.max(hour.implicitWidth, min.implicitWidth)
                }
            }
        }
    }
}
