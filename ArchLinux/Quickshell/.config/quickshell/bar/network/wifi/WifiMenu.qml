import QtQuick
import Quickshell
import Quickshell.Wayland

import qs.core as Core
import "."
import "./ui" as UI

// Owns WiFi overlay lifecycle, dismissal, focus, and component composition.
PanelWindow { // qmllint disable uncreatable-type
    id: root

    visible: false

    required property Core.Theme theme
    required property bool barRevealed
    property bool standalone: true
    readonly property bool actionBusy: controller.isBusy

    signal closeRequested

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    focusable: true

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.namespace: "wifi-menu"

    onVisibleChanged: {
        controller.setMenuVisible(visible);
        if (visible)
            menuCard.scrollToTop();
    }

    function dismiss() {
        if (root.standalone)
            Qt.quit();
        else
            root.closeRequested();
    }

    Shortcut {
        sequence: "Esc"
        enabled: root.visible
        onActivated: root.dismiss()
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: mouse => {
            const inside = mouse.x >= menuCard.x && mouse.x <= menuCard.x + menuCard.width && mouse.y >= menuCard.y && mouse.y <= menuCard.y + menuCard.height;
            if (!inside)
                root.dismiss();
        }
    }

    WifiStyle {
        id: style

        theme: root.theme
    }

    WifiController {
        id: controller

        onDismissRequested: root.dismiss()
    }

    UI.WifiMenuCard {
        id: menuCard

        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: root.barRevealed ? 17 : 10
        anchors.bottomMargin: root.barRevealed ? 40 : 10
        availableWidth: root.width - anchors.rightMargin - 10
        availableHeight: root.height - anchors.bottomMargin - 10
        controller: controller
        style: style
    }
}
