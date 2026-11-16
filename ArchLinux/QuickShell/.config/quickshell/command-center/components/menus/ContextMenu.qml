import QtQuick
import QtQuick.Window
import QtQuick.Controls
import "../../common/Theme.js" as Theme

Menu {
    id: root

    property var themeColors: Theme.colors

    popupType: Popup.Item
    width: 152
    padding: 6
    margins: 6
    modal: true
    dim: false
    enter: null
    exit: null
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    // Popup content lives in the window overlay, outside its owner's visibility tree.
    Connections {
        target: root.parent
        function onVisibleChanged() {
            if (!root.parent?.visible)
                root.close();
        }
        function onEnabledChanged() {
            if (!root.parent?.enabled)
                root.close();
        }
    }
    Connections {
        target: root.parent?.Window.window ?? null
        function onVisibleChanged() {
            if (!root.parent?.Window.window?.visible)
                root.close();
        }
    }

    background: Rectangle {
        radius: Theme.radius
        color: root.themeColors.contextMenuBackground
    }
}
