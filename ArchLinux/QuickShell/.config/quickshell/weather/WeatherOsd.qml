pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import QtQuick.Layouts

Variants {
    model: Quickshell.screens.filter(s => s.name === "HDMI-A-1")

    PanelWindow {
        property var modelData
        screen: modelData

        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore

        anchors {
            top: true
            right: true
        }
        margins {
            top: 57
            right: 17
        }

        width: 260
        height: 40
        color: "transparent"

        WeatherService {
            id: wx
        }

        RowLayout {
            id: line
            anchors.centerIn: parent
            height: 35
            spacing: 0

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: isNaN(wx.nowTempC) ? "--" : Math.round(wx.nowTempC) + "°"
                color: "#e6e1e1e2"
                font.family: "BigBlueTermPlus Nerd Font"
                font.pixelSize: 22
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: wx.decode(wx.nowCode).i + "   "
                color: "#e6e1e1e2"
                font.pixelSize: 22
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: isNaN(wx.tminC[0]) ? "--" : Math.round(wx.tminC[0]) + "°"
                color: "#e6e1e1e2"
                font.family: "BigBlueTermPlus Nerd Font"
                font.pixelSize: 22
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                width: 100
                height: 5
                radius: 6
                color: "#2c2c2e80"

                // current position as fill, clamped to [0..1]
                property real minT: wx.tminC[0]
                property real maxT: wx.tmaxC[0]
                property real nowT: wx.nowTempC
                property real p: (isNaN(minT) || isNaN(maxT) || isNaN(nowT) || maxT === minT) ? 0 : Math.max(0, Math.min(1, (nowT - minT) / (maxT - minT)))

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    height: parent.height
                    radius: parent.radius
                    color: "#e6e1e1e2"
                    width: parent.width * parent.p
                }
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: " " + ((isNaN(wx.tmaxC[0]) ? "--" : Math.round(wx.tmaxC[0]))) + "°"
                color: "#e6e1e1e2"
                font.family: "BigBlueTermPlus Nerd Font"
                font.pixelSize: 22
            }
        }
    }
}
