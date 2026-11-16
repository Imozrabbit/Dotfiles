import QtQuick
import QtQuick.Window
import QtQuick.Controls
import "../../common/Theme.js" as Theme
import "State.js" as State

ToolTip {
    id: root

    required property var control
    property var themeColors: Theme.colors
    property bool showWhenDisabled: false

    objectName: "actionToolTip"
    parent: root.control
    popupType: Popup.Item
    delay: 500
    padding: 8
    margins: 6
    enter: null
    exit: null
    width: Math.min(implicitWidth, Math.max(1, (root.control.Window.window?.width ?? 300) - 12))
    visible: root.text !== "" && root.control.visible && (root.control.enabled || root.showWhenDisabled) && !root.control.down && !root.control.pressed && (root.control.hovered || root.control.visualFocus || disabledHover.hovered) && (root.control.Window.window?.visible ?? false)
    onAboutToShow: State.claim(root)
    onClosed: State.release(root)
    Component.onDestruction: State.release(root)

    HoverHandler {
        id: disabledHover
        parent: root.control
        enabled: root.showWhenDisabled && !root.control.enabled
    }

    contentItem: Text {
        objectName: "actionToolTipText"
        text: root.text
        color: root.themeColors.text
        font.family: Theme.textFont
        font.pixelSize: 12
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
    }

    background: Rectangle {
        radius: Theme.radius
        color: root.themeColors.contextMenuBackground
    }
}
