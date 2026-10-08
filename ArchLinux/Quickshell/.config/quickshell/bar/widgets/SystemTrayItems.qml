pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets

import qs.core as Core

RowLayout {
    id: root

    required property Core.Theme theme
    spacing: 6

    onVisibleChanged: {
        if (!root.visible)
            trayMenu.visible = false;
    }

    Repeater {
        model: SystemTray.items

        delegate: IconImage {
            id: trayIcon

            required property SystemTrayItem modelData

            Layout.alignment: Qt.AlignVCenter
            implicitSize: 20
            source: modelData.icon

            QsMenuOpener {
                id: menuOpener
                // qmllint disable incompatible-type
                menu: trayIcon.modelData.menu
                // qmllint enable incompatible-type
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | (trayIcon.modelData.hasMenu && menuOpener.children.values.length > 0 ? Qt.RightButton : Qt.NoButton)
                cursorShape: Qt.PointingHandCursor

                onClicked: mouse => {
                    if (mouse.button === Qt.LeftButton && !trayIcon.modelData.onlyMenu) {
                        trayIcon.modelData.activate();
                    } else if (trayIcon.modelData.hasMenu && menuOpener.children.values.length > 0) {
                        trayMenu.openFor(trayIcon, trayIcon.modelData.menu);
                    }
                }
            }
        }
    }

    TrayMenu {
        id: trayMenu

        theme: root.theme
    }
}
