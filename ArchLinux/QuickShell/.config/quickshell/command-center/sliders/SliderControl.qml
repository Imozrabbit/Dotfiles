pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Controls
import "brightness" as Brightness
import "../components/tooltips" as Tooltips
import "../common/Theme.js" as Theme

Item {
    id: root

    property string sliderType: "volume"
    property var themeColors: Theme.colors
    property real value: 0
    property string description: "Unavailable"
    property bool available: true
    property var monitors: []
    property string selectedMonitorId: ""
    property string targetKey: ""
    property bool gestureCancelled: false
    readonly property bool selectorEnabled: root.sliderType === "brightness" && root.monitors.length > 0
    signal valueRequested(real value)
    signal monitorRequested(string id)

    activeFocusOnTab: root.selectorEnabled && (!root.available || root.activeFocus)

    onAvailableChanged: {
        if (root.available && root.activeFocus)
            slider.forceActiveFocus(Qt.TabFocusReason);
    }

    function restoreValue(): void {
        if (!slider.pressed || root.gestureCancelled)
            slider.value = root.value;
        if (!slider.pressed)
            root.gestureCancelled = false;
    }

    onValueChanged: root.restoreValue()
    onTargetKeyChanged: {
        if (slider.pressed)
            root.gestureCancelled = true;
        root.restoreValue();
    }
    Component.onCompleted: root.restoreValue()

    implicitHeight: slider.implicitHeight
    height: implicitHeight

    HoverHandler {
        id: selectorHover
        enabled: root.selectorEnabled
    }
    TapHandler {
        enabled: root.selectorEnabled
        acceptedButtons: Qt.RightButton
        onTapped: point => monitorMenu.popup(point.position.x, point.position.y)
    }
    Keys.onPressed: event => {
        if (root.selectorEnabled && (event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && event.modifiers & Qt.ShiftModifier))) {
            monitorMenu.popup(root.width / 2, root.height / 2);
            event.accepted = true;
        }
    }
    Brightness.MonitorMenu {
        id: monitorMenu
        parent: root
        monitors: root.monitors
        selectedId: root.selectedMonitorId
        themeColors: root.themeColors
        onMonitorRequested: id => root.monitorRequested(id)
        onClosed: {
            if (root.visible && root.enabled)
                (slider.enabled ? slider : root).forceActiveFocus(Qt.PopupFocusReason);
        }
    }
    Tooltips.ActionToolTip {
        objectName: "brightnessMonitorToolTip"
        control: slider
        themeColors: root.themeColors
        text: root.selectorEnabled ? root.description : ""
        visible: root.selectorEnabled && root.visible && root.enabled && !slider.pressed && !monitorMenu.visible && (selectorHover.hovered || slider.visualFocus || root.activeFocus) && (root.parent?.Window.window?.visible ?? false)
    }

    Slider {
        id: slider
        enabled: root.available
        objectName: root.sliderType + "Slider"
        anchors.fill: parent
        implicitHeight: Math.max(implicitBackgroundHeight, implicitHandleHeight)
        padding: 0
        hoverEnabled: true
        from: root.sliderType === "brightness" ? 1 : 0
        to: 100
        stepSize: 1
        Accessible.name: root.sliderType === "volume" ? "Volume" : root.sliderType === "microphone" ? "Microphone volume" : "Brightness"
        Accessible.description: root.description
        onMoved: {
            if (!root.gestureCancelled)
                root.valueRequested(value);
            Qt.callLater(root.restoreValue);
        }
        onPressedChanged: {
            if (pressed)
                root.gestureCancelled = false;
            else
                Qt.callLater(root.restoreValue);
        }

        readonly property color highlightedColor: {
            const brighter = Qt.lighter(root.themeColors.tileActive, 1.15);
            return Qt.colorEqual(brighter, root.themeColors.tileActive) ? Qt.darker(root.themeColors.tileActive, 1.15) : brighter;
        }

        background: Item {
            y: (slider.height - height) / 2
            width: slider.availableWidth
            implicitHeight: 24
            height: implicitHeight

            Rectangle {
                id: filledTrack
                objectName: root.sliderType + "FilledTrack"
                width: Math.max(0, slider.handle.x - 3)
                height: parent.height
                topLeftRadius: 8
                bottomLeftRadius: 8
                topRightRadius: 2
                bottomRightRadius: 2
                color: root.themeColors.tileActive
            }

            Rectangle {
                id: remainingTrack
                objectName: root.sliderType + "RemainingTrack"
                x: Math.min(parent.width, slider.handle.x + slider.handle.width + 3)
                width: Math.max(0, parent.width - x)
                height: parent.height
                topLeftRadius: 2
                bottomLeftRadius: 2
                topRightRadius: 8
                bottomRightRadius: 8
                color: root.themeColors.sliderTrack
            }

            Text {
                id: icon
                objectName: root.sliderType + "Icon"
                readonly property bool onFilledTrack: remainingTrack.width < width + 16
                x: Math.max(0, (onFilledTrack ? filledTrack.width : parent.width) - width - 8)
                width: 20
                height: parent.height
                visible: Math.max(filledTrack.width, remainingTrack.width) >= width + 16
                text: root.sliderType === "volume" ? "󰕾" : root.sliderType === "microphone" ? "󰍬" : "󰃠"
                color: onFilledTrack ? root.themeColors.onActive : root.themeColors.text
                font.family: Theme.iconFont
                font.pixelSize: 14
                leftPadding: Math.max(0, (width - iconMetrics.ink.width) / 2 - iconMetrics.ink.x)
                topPadding: Math.max(0, (height - iconMetrics.ink.height) / 2 - iconMetrics.ascent - iconMetrics.ink.y)
                horizontalAlignment: Text.AlignLeft
                verticalAlignment: Text.AlignTop

                FontMetrics {
                    id: iconMetrics
                    font: icon.font
                    readonly property rect ink: tightBoundingRect(icon.text)
                }
            }
        }

        handle: Rectangle {
            x: slider.visualPosition * Math.max(0, slider.availableWidth - width)
            y: (slider.height - height) / 2
            implicitWidth: 3
            implicitHeight: 32
            width: Math.min(implicitWidth, Math.max(0, slider.availableWidth))
            height: implicitHeight
            radius: width / 2
            color: !slider.enabled ? Qt.darker(root.themeColors.tileActive, root.selectorEnabled && root.activeFocus ? 1.2 : 1.5) : slider.pressed ? Qt.darker(root.themeColors.tileActive, 1.2) : slider.hovered || slider.visualFocus ? slider.highlightedColor : root.themeColors.tileActive
        }
    }
}
