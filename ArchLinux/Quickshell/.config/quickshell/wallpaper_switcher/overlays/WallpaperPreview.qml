import Quickshell
import Quickshell.Wayland
import QtQuick

import qs.core as Core

PanelWindow {
    id: root

    required property Core.Theme theme
    required property Core.AppState appState

    property ShellScreen previewScreen: null

    exclusiveZone: 0
    focusable: false
    visible: root.appState.if_preview
    color: "black"

    WlrLayershell.layer: WlrLayer.Overlay
    screen: previewScreen

    function togglePreview(): void {
        if (root.previewScreen === null || root.appState.chosen_wallpaper_url.toString().length === 0 || root.appState.chosen_mode === "") {
            root.appState.if_preview = false;
            return;
        }

        root.appState.if_preview = !root.appState.if_preview;
    }

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    Image {
        id: preview_image
        anchors.fill: parent

        source: root.appState.chosen_wallpaper_url
        clip: true
        asynchronous: true

        horizontalAlignment: Image.AlignHCenter
        verticalAlignment: Image.AlignVCenter

        fillMode: root.appState.imageFillMode
    }

    // Handle loading and error message
    Text {
        anchors.centerIn: parent
        z: 1
        visible: preview_image.status === Image.Loading
        text: "Loading preview..."
        color: root.theme.mainColor
    }
    Text {
        anchors.centerIn: parent
        z: 1
        visible: preview_image.status === Image.Error
        text: "Failed to load preview"
        color: root.theme.mainColor
    }

    // Click anywhere to close the preview.
    MouseArea {
        anchors.fill: parent
        onClicked: root.appState.if_preview = false
    }
    Shortcut {
        sequence: "Escape"
        enabled: root.visible
        onActivated: root.appState.if_preview = false
    }

    // Disable shortcuts
    ShortcutInhibitor {
        window: root
        enabled: root.visible
    }
}
