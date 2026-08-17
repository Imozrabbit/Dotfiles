pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: stat
    property int ifcpu: 1
    //---------- Inputs ----------//
    property real value
    property real voltage
    property real wattage

    //---------- Sizing ----------//
    property int barWidth
    property int barHeight
    property real barRadius: barHeight / 2
    property int textBoxHeight: 20
    property int textPixelSize: 20
    property int gap: 5

    //---------- Color ----------//
    property color trackColor: "#1aFFFFFF"
    property color fillColor: "#FFbfc9d4"
    property color textColor: "#ffb3bcc8"

    //---------- Sparkline ----------//
    property var graphSamples: []
    property int graphHeight: 38
    property color graphColor: "#ff239d87"
    property real graphLineWidth: 2
    property int graphGap: 45
    property int minValue: 0
    property int maxValue: 0

    width: barWidth
    height: barHeight + gap + textBoxHeight + graphGap + graphHeight

    //---------- Bar ----------//
    Rectangle {
        id: track
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: stat.barHeight
        radius: stat.barRadius
        color: stat.trackColor
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * Math.max(0, Math.min(1, stat.value))
            radius: parent.radius
            color: stat.fillColor
        }
    }

    //---------- Text ----------//
    Item {
        id: boxes
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: track.bottom
        anchors.topMargin: stat.gap
        height: stat.textBoxHeight

        // Left: Usage
        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: Math.round(stat.value * 100) + "%"
            color: stat.textColor
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: stat.textPixelSize
            font.bold: true
        }
        // Center: Voltage
        Text {
            visible: stat.ifcpu === 1 ? false : true
            anchors.centerIn: parent
            anchors.verticalCenter: parent.verticalCenter
            text: stat.voltage + "V"
            color: stat.textColor
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: stat.textPixelSize
            font.bold: true
        }
        // Right box: wattage
        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: stat.wattage + "W"
            color: stat.textColor
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: stat.textPixelSize
            font.bold: true
        }
    }

    //---------- Sparkline ----------//
    Sparkline {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: boxes.bottom
        anchors.topMargin: stat.graphGap
        anchors.leftMargin: 15
        anchors.rightMargin: 5
        height: stat.graphHeight

        samples: stat.graphSamples
        lineColor: stat.graphColor
        lineWidth: stat.graphLineWidth
    }
}
