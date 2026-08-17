pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

Scope {
    HWInfoProvider {
        id: hw
    }
    Variants {
        //model: Quickshell.screens.filter(s => s.name === "DP-2")
        model: Quickshell.screens.filter(s => s.name === "HDMI-A-1")
        PanelWindow {
            id: space
            required property var modelData
            screen: modelData
            anchors.bottom: true
            WlrLayershell.namespace: "system-osd"

            // OSD behavior
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            aboveWindows: false
            focusable: false

            // Color and Size
            implicitWidth: 515
            implicitHeight: 520
            color: "transparent"
            readonly property color boxBg: "#4d121a1a"
            readonly property color boxBorder: "#5a273535"

            Item {
                anchors.fill: parent
                Rectangle {
                    anchors.fill: parent
                    radius: 22
                    color: "transparent"
                }
                ColumnLayout {
                    anchors.fill: parent
                    //------------------------------         CPU         ------------------------------//
                    Item {
                        implicitWidth: space.implicitWidth
                        implicitHeight: cpuRow.implicitHeight
                        Layout.alignment: Qt.AlignHCenter
                        Rectangle {
                            anchors.fill: parent
                            radius: 18
                            color: space.boxBg
                            border.width: 1
                            border.color: space.boxBorder
                        }
                        RowLayout {
                            id: cpuRow
                            spacing: 30
                            //--------------------           Gauge           --------------------//
                            Gauge {
                                Layout.leftMargin: 22
                                Layout.topMargin: 20
                                Layout.bottomMargin: 20
                                size: 200
                                value: hw.effValue
                                valueText: hw.effText
                                unitText: "MHz"
                                tempC: hw.cpuTempC
                                warnTempC: 75
                                hotTempC: 85
                                centerText: Math.round(hw.cpuTempC) + "°C"
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignTop
                                Layout.leftMargin: 21
                                Layout.topMargin: 18
                                //--------------------           Title           --------------------//
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "5800X3D"
                                    color: "#ffe6eaf0"
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 30
                                    font.bold: true
                                }
                                //--------------------           Stats           --------------------//
                                Stat {
                                    Layout.topMargin: 10
                                    barWidth: 220
                                    barHeight: 8
                                    value: hw.cpuUsage01
                                    wattage: hw.cpuPkgWatt
                                    minValue: 0
                                    maxValue: hw.maxMHz
                                    graphSamples: hw.effSamples
                                }
                            }
                        }
                    }

                    //------------------------------         GPU         ------------------------------//
                    Item {
                        implicitWidth: space.implicitWidth
                        implicitHeight: gpuRow.implicitHeight
                        Layout.alignment: Qt.AlignHCenter
                        Rectangle {
                            anchors.fill: parent
                            radius: 18
                            color: space.boxBg
                            border.width: 1
                            border.color: space.boxBorder
                        }
                        RowLayout {
                            id: gpuRow
                            spacing: 30
                            ColumnLayout {
                                Layout.alignment: Qt.AlignTop
                                Layout.topMargin: 20
                                Layout.leftMargin: 22
                                //--------------------           Title           --------------------//
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "RX 9070XT"
                                    color: "#ffe6eaf0"
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 30
                                    font.bold: true
                                }
                                //--------------------           Stats           --------------------//
                                Stat {
                                    Layout.topMargin: 10
                                    ifcpu: 0
                                    barWidth: 220
                                    barHeight: 8
                                    value: hw.gpuUsage01
                                    wattage: hw.gpuPowerW
                                    voltage: hw.gpuVoltText
                                    minValue: 0
                                    maxValue: hw.gpuSclkMaxMHz
                                    graphSamples: hw.gpuSclkSamples
                                }
                            }
                            //--------------------           Gauge           --------------------//
                            Gauge {
                                Layout.leftMargin: 20
                                Layout.topMargin: 25
                                Layout.bottomMargin: 25
                                size: 200
                                tickDirection: -1
                                value: hw.gpuSclkValue
                                valueText: hw.gpuSclkText
                                unitText: "MHz"
                                tempC: hw.gpuTempC
                                warnTempC: 80
                                hotTempC: 85
                                centerText: this.tempC + "°C"
                                vramUsage01: hw.gpuVramUsage01
                                vramUnitText: hw.gpuMclkText + "GHz"
                            }
                        }
                    }
                }
            }
        }
    }
}
