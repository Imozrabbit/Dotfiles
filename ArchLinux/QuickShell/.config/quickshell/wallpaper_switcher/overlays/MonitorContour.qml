pragma ComponentBehavior: Bound

import QtQuick

import Quickshell
import Quickshell.Wayland

import qs.core as Core

PanelWindow {
    id: contour

    required property Core.Theme theme
    required property ShellScreen targetScreen

    readonly property var flash_colors: [theme.contourColor1, theme.contourColor2, theme.contourColor3]
    property int flash_color_index: 0

    screen: contour.targetScreen

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // Leaves room so the rounded corners are visible.
    margins {
        top: contour.theme.contourMargin
        bottom: contour.theme.contourMargin
        left: contour.theme.contourMargin
        right: contour.theme.contourMargin
    }

    color: "transparent"
    surfaceFormat.opaque: false

    // Do not affect the usable workspace.
    exclusionMode: ExclusionMode.Ignore

    // Do not take keyboard focus.
    focusable: false

    // Empty clickable region: mouse input passes through.
    mask: Region {}

    // Show above ordinary windows.
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "wallpaper-switcher-contour"

    // Temporary border used for the 3 color falsh
    Rectangle {
        id: flash_layer

        anchors.fill: parent
        color: "transparent"
        radius: contour.theme.contourRadius

        border.width: contour.theme.contourWidth + 2
        border.color: contour.flash_colors[0]

        opacity: 0
    }

    function flash() {
        contour.flash_color_index = 0;
        flash_animation.restart();
    }

    SequentialAnimation {
        id: flash_animation
        loops: 6

        // Select the next color at the start of each loop
        ScriptAction {
            script: {
                flash_layer.border.color = contour.flash_colors[contour.flash_color_index];
                contour.flash_color_index = (contour.flash_color_index + 1) % contour.flash_colors.length;
            }
        }

        // Reset the flash before starting
        PropertyAction {
            target: flash_layer
            property: "opacity"
            value: 0
        }

        NumberAnimation {
            target: flash_layer
            property: "opacity"
            from: 0
            to: 1
            duration: 70
        }

        PauseAnimation {
            duration: 80
        }

        NumberAnimation {
            target: flash_layer
            property: "opacity"
            from: 1
            to: 0
            duration: 180
        }

        PauseAnimation {
            duration: 70
        }
    }
}
