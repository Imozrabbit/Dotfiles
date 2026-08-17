pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Wayland
import Quickshell.Widgets

import qs.core as Core

Item {
    id: root

    required property Core.Theme theme
    property bool opened: false

    signal dismissed

    PanelWindow {
        id: trayWindow

        visible: root.opened && SystemTray.items.values.length > 0
        color: "transparent"
        focusable: false

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusiveZone: -1
        WlrLayershell.namespace: "tray-bubble"

        onVisibleChanged: {
            if (visible) {
                bubbleCard.x = -bubbleCard.width;
                slideIn.restart();
            } else if (root.opened) {
                root.dismissed();
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: mouse => {
                const inside = mouse.x >= bubbleCard.x && mouse.x <= bubbleCard.x + bubbleCard.width && mouse.y >= bubbleCard.bodyTop && mouse.y <= bubbleCard.bodyBottom;
                if (!inside)
                    root.dismissed();
            }
        }

        Item {
            id: bubbleCard

            property real bodyHeight: trayColumn.implicitHeight + 25
            property real bodyTop: Math.round((height - bodyHeight) / 2)
            property real bodyBottom: bodyTop + bodyHeight
            property real shoulderRadius: 7
            property real spineWidth: 1

            y: 0
            width: 35
            height: trayWindow.height

            Shape {
                anchors.fill: parent

                ShapePath {
                    fillColor: root.theme.sysTrayBg
                    strokeColor: root.theme.sysTrayBorderColor
                    strokeWidth: 1
                    startX: 0
                    startY: bubbleCard.bodyTop - bubbleCard.shoulderRadius
                    PathLine {
                        x: bubbleCard.spineWidth
                        y: bubbleCard.bodyTop - bubbleCard.shoulderRadius
                    }
                    PathCubic {
                        x: bubbleCard.spineWidth + bubbleCard.shoulderRadius
                        y: bubbleCard.bodyTop
                        control1X: bubbleCard.spineWidth
                        control1Y: bubbleCard.bodyTop - 5
                        control2X: bubbleCard.spineWidth + 5
                        control2Y: bubbleCard.bodyTop
                    }
                    PathLine {
                        x: bubbleCard.width - bubbleCard.shoulderRadius
                        y: bubbleCard.bodyTop
                    }
                    PathCubic {
                        x: bubbleCard.width
                        y: bubbleCard.bodyTop + bubbleCard.shoulderRadius
                        control1X: bubbleCard.width - 5
                        control1Y: bubbleCard.bodyTop
                        control2X: bubbleCard.width
                        control2Y: bubbleCard.bodyTop + 5
                    }
                    PathLine {
                        x: bubbleCard.width
                        y: bubbleCard.bodyBottom - bubbleCard.shoulderRadius
                    }
                    PathCubic {
                        x: bubbleCard.width - bubbleCard.shoulderRadius
                        y: bubbleCard.bodyBottom
                        control1X: bubbleCard.width
                        control1Y: bubbleCard.bodyBottom - 5
                        control2X: bubbleCard.width - 5
                        control2Y: bubbleCard.bodyBottom
                    }
                    PathLine {
                        x: bubbleCard.spineWidth + bubbleCard.shoulderRadius
                        y: bubbleCard.bodyBottom
                    }
                    PathCubic {
                        x: bubbleCard.spineWidth
                        y: bubbleCard.bodyBottom + bubbleCard.shoulderRadius
                        control1X: bubbleCard.spineWidth + 5
                        control1Y: bubbleCard.bodyBottom
                        control2X: bubbleCard.spineWidth
                        control2Y: bubbleCard.bodyBottom + 5
                    }
                    PathLine {
                        x: 0
                        y: bubbleCard.bodyBottom + bubbleCard.shoulderRadius
                    }
                    PathLine {
                        x: 0
                        y: bubbleCard.bodyTop - bubbleCard.shoulderRadius
                    }
                }
            }

            ColumnLayout {
                id: trayColumn

                x: Math.round((bubbleCard.spineWidth + bubbleCard.width - width) / 2)
                y: Math.round((bubbleCard.height - height) / 2)
                spacing: 12

                Repeater {
                    model: SystemTray.items

                    delegate: IconImage {
                        required property var modelData

                        implicitSize: 20
                        source: modelData.icon
                    }
                }
            }
        }

        NumberAnimation {
            id: slideIn

            target: bubbleCard
            property: "x"
            from: -bubbleCard.width
            to: 0
            duration: 140
            easing.type: Easing.OutCubic
        }
    }
}
