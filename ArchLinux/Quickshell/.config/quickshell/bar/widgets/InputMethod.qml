import QtQuick
import Quickshell

import qs.core as Core

Rectangle {
    id: root

    required property Core.Theme theme
    required property string currentMethod

    signal cycleRequested

    readonly property bool knownMethod: root.currentMethod === "keyboard-us" || root.currentMethod === "keyboard-fr" || root.currentMethod === "rime"

    function methodIcon() {
        switch (root.currentMethod) {
        case "keyboard-us":
            return "󰬌";
        case "keyboard-fr":
            return "󰬍";
        case "rime":
            return "󰬊";
        default:
            return "󰌌";
        }
    }

    implicitWidth: 34
    implicitHeight: iconText.implicitHeight + 4
    radius: root.theme.radiusMedium
    color: "transparent"

    Text {
        id: iconText

        anchors.centerIn: parent
        text: root.methodIcon()
        color: iconMouse.containsMouse ? root.theme.volumeHoverColor : root.knownMethod ? root.theme.volumeColor : root.theme.volumeMutedColor
        font {
            family: root.theme.fontFamily
            pixelSize: root.theme.inputMethodFontSize
            bold: true
        }
    }

    MouseArea {
        id: iconMouse

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor

        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                root.cycleRequested();
            } else {
                Quickshell.execDetached(["fcitx5-configtool"]);
            }
        }
    }
}
