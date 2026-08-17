import QtQuick
import QtQuick.Controls
import Quickshell

import qs.core as Core
import qs.services as Services

Rectangle {
    id: root

    required property Core.Theme theme
    required property bool available
    required property real brightness

    signal brightnessRequested(real value)

    property real pendingBrightness: root.brightness
    property Services.Brightness brightnessService: Services.Brightness {}

    readonly property real displayBrightness: Math.max(0.01, Math.min(1.0, root.brightness))

    function brightnessIcon() {
        if (!root.available)
            return "󰃞";
        if (root.brightness < 0.34)
            return "󰃞";
        if (root.brightness < 0.67)
            return "󰃟";
        return "󰃠";
    }

    function showPopup() {
        closeTimer.stop();
        brightnessPopup.visible = true;
    }

    function schedulePopupClose() {
        closeTimer.restart();
    }

    implicitWidth: 38
    implicitHeight: iconText.implicitHeight + 4
    radius: root.theme.radiusMedium
    color: "transparent"

    Text {
        id: iconText

        anchors.centerIn: parent
        text: root.brightnessIcon()
        color: !root.available ? root.theme.volumeMutedColor : iconMouse.containsMouse ? root.theme.volumeHoverColor : root.theme.volumeColor
        font {
            family: root.theme.fontFamily
            pixelSize: root.theme.volumeFontSize
            bold: true
        }
    }

    MouseArea {
        id: iconMouse

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        cursorShape: Qt.PointingHandCursor

        onEntered: root.showPopup()
        onExited: root.schedulePopupClose()
    }

    TapHandler {
        onTapped: root.brightnessService.cycleKeyboardBacklight()
    }

    Timer {
        id: closeTimer

        interval: 250
        repeat: false
        onTriggered: {
            if (!iconMouse.containsMouse && !popupHover.hovered)
                brightnessPopup.visible = false;
        }
    }

    Timer {
        id: setTimer

        interval: 50
        repeat: false
        onTriggered: root.brightnessRequested(root.pendingBrightness)
    }

    PopupWindow {
        id: brightnessPopup

        visible: false
        color: "transparent"
        grabFocus: false
        implicitWidth: root.width - 15
        implicitHeight: 145

        anchor.item: root
        anchor.rect.x: 0
        anchor.rect.y: 1
        anchor.rect.width: root.width
        anchor.rect.height: root.height
        anchor.edges: Edges.Top
        anchor.gravity: Edges.Top

        Rectangle {
            anchors.fill: parent
            radius: root.theme.radiusMedium
            color: root.theme.volumeBg

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: root.theme.radiusMedium
                color: root.theme.volumeBg
            }

            Slider {
                id: brightnessSlider

                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    bottom: parent.bottom
                    leftMargin: 4
                    rightMargin: 4
                    topMargin: 12
                    bottomMargin: root.theme.radiusMedium - 2
                }

                orientation: Qt.Vertical
                from: 0.01
                to: 1.0
                value: root.displayBrightness
                enabled: root.available

                onMoved: {
                    root.pendingBrightness = value;
                    setTimer.restart();
                }

                background: Rectangle {
                    x: brightnessSlider.leftPadding + (brightnessSlider.availableWidth - width) / 2
                    y: brightnessSlider.topPadding
                    width: 5
                    height: brightnessSlider.availableHeight
                    radius: width / 2
                    color: root.theme.volumeSliderTrackColor

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: parent.height * brightnessSlider.position
                        radius: parent.radius
                        color: root.theme.volumeColor
                    }
                }

                handle: Rectangle {
                    x: brightnessSlider.leftPadding + (brightnessSlider.availableWidth - width) / 2
                    y: brightnessSlider.topPadding + brightnessSlider.visualPosition * (brightnessSlider.availableHeight - height)
                    width: 12
                    height: 12
                    radius: width / 2
                    color: root.theme.volumeSliderHandleColor
                }
            }

            HoverHandler {
                id: popupHover
                onHoveredChanged: {
                    if (hovered)
                        closeTimer.stop();
                    else
                        root.schedulePopupClose();
                }
            }
        }
    }
}
