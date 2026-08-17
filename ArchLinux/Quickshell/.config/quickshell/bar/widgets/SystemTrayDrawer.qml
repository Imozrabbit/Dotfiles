pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.SystemTray

import qs.core as Core

Item {
    id: root

    required property Core.Theme theme

    property bool trayOpened: false

    implicitWidth: toggleText.implicitWidth
    implicitHeight: toggleText.implicitHeight

    function togglePopup() {
        if (root.trayOpened) {
            root.trayOpened = false;
        } else if (SystemTray.items.values.length > 0) {
            root.trayOpened = true;
        }
    }

    Text {
        id: toggleText

        anchors.centerIn: parent
        text: "󰀻"
        color: !root.trayOpened ? root.theme.workspaceEmptyColor : (toggleHover.hovered ? root.theme.workspaceHoveredColor : root.theme.workspaceOccupiedColor)
        font {
            family: root.theme.fontFamily
            pixelSize: root.theme.workspaceFontSize
            bold: true
        }
    }

    HoverHandler {
        id: toggleHover
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        onTapped: root.togglePopup()
    }

    Connections {
        target: SystemTray.items

        function onObjectRemovedPost() {
            if (SystemTray.items.values.length === 0)
                root.trayOpened = false;
        }
    }

    TrayBubble {
        opened: root.trayOpened
        onDismissed: root.trayOpened = false
        theme: root.theme
    }
}
