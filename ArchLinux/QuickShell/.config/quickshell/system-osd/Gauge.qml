pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes

Item {
    id: gauge
    // Gauge
    property real value: 0.0
    property int size: 250
    property color activeColor: "#FF5b6cff"
    property color inactiveColor: "#1aFFFFFF"
    property color clockText: "#e6eef2ff"

    // Tick setting
    property int tickCount: 60
    property real startAngle: 180
    property real spanAngle: 270
    property real ringInset: 0
    property int tickWidth: 5
    property int tickHeight: 20
    property int tickRadius: 1
    property int tickDirection: 1

    // Frequency Text
    property string valueText: ""
    property string unitText: ""

    // Temperature Text
    property real tempC
    property real tempMaxC: 100
    property real warnTempC
    property real hotTempC
    property color tempCoolColor: "#FF268cb3"
    property color tempWarnColor: "#ffc98a2f"
    property color tempHotColor: "#ffb83a3a"
    property string centerText: "temp"
    property real centerTextScale: 0.18
    property bool showCenterText: true

    // Temperature Percentage inner arc
    property real rimWidth: 5
    property real rimOffset: 22
    property color rimTrackColor: "#1affffff"
    property color rimCoolColor: tempCoolColor
    property color rimWarnColor: tempWarnColor
    property color rimHotColor: tempHotColor

    // Vram related
    property real vramUsage01: 0
    property real outerrimOffset: -7
    property color outerrimColor: "#ffa06ad9"
    property string vramUnitText: "vram clock"
    property real vramUnitScale: 0.07
    property color vramUnitColor: "#FFB3BCC8"

    // Derived
    property int activeIndex: Math.round(Math.max(0, Math.min(1, value)) * (tickCount - 1))
    property real tempClamped: Math.max(0, Math.min(tempC, tempMaxC))
    property real tempNorm: (tempMaxC > 0) ? (tempClamped / tempMaxC) : 0
    property color rimFillColor: (tempC >= hotTempC) ? rimHotColor : (tempC >= warnTempC) ? rimWarnColor : rimCoolColor

    width: size
    height: size

    Rectangle {
        id: circle
        anchors.fill: parent
        radius: width / 2
        color: "transparent"

        //-------------------- Temperature Bar --------------------//
        Shape {
            id: rim
            anchors.fill: parent
            // Center and radius for the arc
            property real cx: width / 2
            property real cy: height / 2
            property real r: (Math.min(width, height) / 2) - (gauge.rimWidth / 2) - gauge.rimOffset
            // Full track (dim)
            ShapePath {
                fillColor: "transparent"
                strokeColor: gauge.rimTrackColor
                strokeWidth: gauge.rimWidth
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: rim.cx
                    centerY: rim.cy
                    radiusX: rim.r
                    radiusY: rim.r
                    startAngle: gauge.tickDirection === 1 ? gauge.startAngle - 90 : gauge.startAngle
                    sweepAngle: gauge.spanAngle
                }
            }
            // Filling arc
            ShapePath {
                fillColor: "transparent"
                strokeColor: gauge.rimFillColor
                strokeWidth: gauge.rimWidth
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: rim.cx
                    centerY: rim.cy
                    radiusX: rim.r
                    radiusY: rim.r
                    startAngle: gauge.tickDirection === 1 ? gauge.startAngle - 90 : gauge.startAngle + gauge.spanAngle
                    sweepAngle: gauge.tickDirection * gauge.spanAngle * gauge.tempNorm
                }
            }
        }

        //--------------------      Vram Bar      --------------------//
        Shape {
            id: outerrim
            anchors.fill: parent
            visible: gauge.tickDirection === 1 ? false : true
            // Center and radius for the arc
            property real cx: width / 2
            property real cy: height / 2
            property real r: (Math.min(width, height) / 2) - (gauge.rimWidth / 2) - gauge.outerrimOffset
            // Full track (dim)
            ShapePath {
                fillColor: "transparent"
                strokeColor: gauge.rimTrackColor
                strokeWidth: gauge.rimWidth
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: outerrim.cx
                    centerY: outerrim.cy
                    radiusX: outerrim.r
                    radiusY: outerrim.r
                    startAngle: gauge.tickDirection === 1 ? gauge.startAngle - 90 : gauge.startAngle
                    sweepAngle: gauge.spanAngle
                }
            }
            // Filling arc
            ShapePath {
                fillColor: "transparent"
                strokeColor: gauge.outerrimColor
                strokeWidth: gauge.rimWidth
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: outerrim.cx
                    centerY: outerrim.cy
                    radiusX: outerrim.r
                    radiusY: outerrim.r
                    startAngle: gauge.tickDirection === 1 ? gauge.startAngle - 90 : gauge.startAngle + gauge.spanAngle
                    sweepAngle: gauge.tickDirection * gauge.spanAngle * Math.max(0, Math.min(1, gauge.vramUsage01))
                }
            }
        }

        //-------------------- Inside --------------------//
        Repeater {
            model: gauge.tickCount
            Rectangle {
                id: tick
                required property int index
                width: gauge.tickWidth
                height: gauge.tickHeight
                radius: gauge.tickRadius
                color: (index <= gauge.activeIndex) ? gauge.activeColor : gauge.inactiveColor
                x: circle.width / 2 - width / 2
                y: gauge.ringInset
                transform: Rotation {
                    origin.x: tick.width / 2
                    origin.y: circle.height / 2 - gauge.ringInset
                    angle: (gauge.startAngle + gauge.tickDirection * (gauge.spanAngle * tick.index) / (gauge.tickCount - 1))
                }
            }
        }
        //-------------------- Frequency --------------------//
        Column {
            anchors.left: gauge.tickDirection === 1 ? parent.left : undefined
            anchors.right: gauge.tickDirection === -1 ? parent.right : undefined
            anchors.bottom: parent.bottom
            anchors.bottomMargin: gauge.size * 0.06
            anchors.leftMargin: gauge.tickDirection === 1 ? gauge.size * 0.35 : undefined
            anchors.rightMargin: gauge.tickDirection === -1 ? gauge.size * 0.35 : undefined
            width: circle.width
            spacing: 2
            // main numeric readout
            Text {
                font.family: "DSEG7 Modern"
                text: gauge.valueText
                color: gauge.clockText
                font.pixelSize: gauge.size * 0.19
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                width: parent.width
            }
            // optional small label (CPU/GPU)
            Text {
                font.family: "Atkinson Hyperlegible"
                visible: gauge.unitText.length > 0
                text: gauge.unitText
                color: "#FFB3BCC8"
                font.pixelSize: gauge.size * 0.08
                horizontalAlignment: Text.AlignHCenter
                width: parent.width
            }
        }

        //-------------------- VRAM clock --------------------//
        Text {
            visible: gauge.tickDirection === 1 ? false : gauge.vramUnitText.length > 0
            font.family: "Atkinson Hyperlegible"
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -gauge.size * 0.12
            text: gauge.vramUnitText
            color: gauge.vramUnitColor
            font.pixelSize: gauge.size * gauge.vramUnitScale
            horizontalAlignment: Text.AlignHCenter
            width: parent.width
        }

        //-------------------- Temperature --------------------//
        Text {
            font.family: "JetBrainsMono Nerd Font"
            anchors.centerIn: parent
            visible: gauge.showCenterText && gauge.centerText.length > 0
            text: gauge.centerText
            color: (gauge.tempC >= gauge.hotTempC) ? gauge.tempHotColor : (gauge.tempC >= gauge.warnTempC) ? gauge.tempWarnColor : gauge.tempCoolColor
            font.pixelSize: gauge.size * gauge.centerTextScale
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            width: parent.width
        }
    }
}
