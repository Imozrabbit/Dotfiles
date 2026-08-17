import QtQuick
import QtQuick.Controls
import Quickshell

import qs.core as Core

Rectangle {
    id: root

    required property Core.Theme theme
    required property bool available
    required property real volume
    required property bool muted

    signal volumeRequested(real value)
    signal muteRequested

    readonly property real displayVolume: Math.max(0.0, Math.min(1.0, root.volume))

    function volumeIcon() {
        if (!root.available || root.muted || root.volume <= 0.0)
            return "";
        if (root.volume < 0.34)
            return "";
        if (root.volume < 0.67)
            return "";
        return "";
    }

    function showPopup() {
        closeTimer.stop();
        volumePopup.visible = true;
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
        text: root.volumeIcon()
        color: !root.available || root.muted || root.volume <= 0.0 ? root.theme.volumeMutedColor : iconMouse.containsMouse ? root.theme.volumeHoverColor : root.theme.volumeColor

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
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor

        onEntered: root.showPopup()
        onExited: root.schedulePopupClose()

        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                Quickshell.execDetached(["pavucontrol-qt"]);
            } else if (root.available) {
                root.muteRequested();
            }
        }
    }

    Timer {
        id: closeTimer

        interval: 250
        repeat: false

        onTriggered: {
            if (!iconMouse.containsMouse && !popupHover.hovered)
                volumePopup.visible = false;
        }
    }

    PopupWindow {
        id: volumePopup

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
                id: connector
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: root.theme.radiusMedium
                color: root.theme.volumeBg
            }

            Slider {
                id: volumeSlider

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
                from: 0.0
                to: 1.0
                value: root.displayVolume
                enabled: root.available

                onMoved: root.volumeRequested(value)

                background: Rectangle {
                    x: volumeSlider.leftPadding + (volumeSlider.availableWidth - width) / 2
                    y: volumeSlider.topPadding
                    width: 5
                    height: volumeSlider.availableHeight
                    radius: width / 2
                    color: root.theme.volumeSliderTrackColor

                    Rectangle {
                        anchors {
                            left: parent.left
                            right: parent.right
                            bottom: parent.bottom
                        }

                        height: parent.height * volumeSlider.value
                        radius: parent.radius
                        color: root.theme.volumeColor
                    }
                }

                handle: Rectangle {
                    x: volumeSlider.leftPadding + (volumeSlider.availableWidth - width) / 2
                    y: volumeSlider.topPadding + (1.0 - volumeSlider.value) * (volumeSlider.availableHeight - height)

                    width: 12
                    height: 12
                    radius: width / 2
                    color: root.theme.volumeSliderHandleColor
                }
            }

            HoverHandler {
                id: popupHover
                onHoveredChanged: {
                    if (hovered) {
                        closeTimer.stop();
                    } else {
                        root.schedulePopupClose();
                    }
                }
            }
        }
    }
}
