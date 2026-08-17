pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic

import Quickshell.Hyprland

import qs.core as Core

ComboBox {
    id: root

    required property Core.Theme theme
    required property Core.AppState appState

    // Start without selecting the first monitor automatically
    currentIndex: -1

    property string placeholderText: "Select Monitor"

    property string selectedMarkerText: "▶"
    property string unselectedMarkerText: "▷"
    property int markerLeftMargin: 15
    property int markerGap: 0

    property int popupGap: 2
    property int popupHorizontalPadding: 4
    property int popupMaxHeight: 220

    property int indicatorLeftMargin: 15
    property int controlRightPadding: 7

    property bool showSelectedDot: true

    property int entryHorizontalPadding: 0
    property int entryHeight: 30

    // General font config, size and behavior
    implicitHeight: 30
    leftPadding: indicatorSpace
    rightPadding: controlRightPadding
    font.family: theme.fontFamily
    font.pixelSize: theme.normalText_fontSize
    font.bold: true
    TextMetrics {
        id: selected_text_metrics
        font: root.font
        text: root.displayText
    }
    TextMetrics {
        id: selected_marker_metrics
        font: root.font
        text: root.selectedMarkerText
    }

    // Dynamic width control
    property int minimumWidth: 130

    readonly property int indicatorSpace: Math.ceil(root.indicator.implicitWidth) + indicatorLeftMargin
    readonly property int selectedMarkerSpace: showSelectedDot ? markerLeftMargin + Math.ceil(selected_marker_metrics.advanceWidth) + markerGap : 0
    readonly property int closedRequiredWidth: indicatorSpace + Math.ceil(selected_text_metrics.advanceWidth) + leftPadding + rightPadding
    readonly property int popupRequiredWidth: Math.max(popupHorizontalPadding * 2 + entryHorizontalPadding * 2 + selectedMarkerSpace + Math.ceil(selected_text_metrics.advanceWidth), closedRequiredWidth)

    implicitWidth: popup.visible ? Math.max(minimumWidth, popupRequiredWidth, closedRequiredWidth) : Math.max(minimumWidth, closedRequiredWidth)

    // Hyprland monitor data and displayed value
    model: Hyprland.monitors.values
    valueRole: "id"
    textRole: "name"
    displayText: currentIndex >= 0 ? currentText : placeholderText

    // Restore the saved monitor, or remain unselected
    function syncSelection() {
        Qt.callLater(function () {
            const saved_index = root.indexOfValue(root.appState.chosen_monitor);

            root.currentIndex = saved_index;
        });
    }
    Component.onCompleted: syncSelection()
    onCountChanged: syncSelection()

    // Store the newly selected monitor in AppState
    onActivated: {
        root.appState.chosen_monitor_name = currentText;
        root.appState.chosen_monitor = currentValue;
    }

    // Text displayed inside the closed ComboBox
    contentItem: Text {
        text: root.displayText
        color: root.appState.chosen_monitor < 0 ? root.theme.subTextColor : root.theme.mainColor
        font: root.font
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    // Icon displayed on the left side of the closed ComboBox
    indicator: Text {
        id: indicator
        text: "󰍹"
        anchors {
            left: parent.left
            leftMargin: root.indicatorLeftMargin
            verticalCenter: parent.verticalCenter
        }
        color: root.hovered || root.popup.visible ? root.theme.mainColor : root.theme.subTextColor
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.normalText_fontSize
    }

    // Background and interaction states of the closed ComboBox
    background: Rectangle {
        radius: root.theme.radiusMedium
        border.width: 1
        border.color: root.theme.borderColor
        color: {
            if (root.down)
                return root.theme.pressed_infillColor;
            if (root.hovered || root.popup.visible)
                return root.theme.hover_infillColor;
            return root.theme.infillColor;
        }
    }

    // Visual representation of each monitor entry inside the popup
    delegate: ItemDelegate {
        id: monitor_entry
        hoverEnabled: true
        required property HyprlandMonitor modelData
        required property int index
        width: ListView.view ? ListView.view.width : root.width - root.popupHorizontalPadding * 2
        height: root.entryHeight
        leftPadding: root.entryHorizontalPadding
        rightPadding: root.entryHorizontalPadding
        highlighted: root.highlightedIndex === monitor_entry.index
        // Monitor name and selected-state indicator
        contentItem: Item {
            Text {
                id: selected_marker
                visible: true
                anchors {
                    left: parent.left
                    leftMargin: root.markerLeftMargin
                    verticalCenter: parent.verticalCenter
                }
                text: root.currentIndex === monitor_entry.index ? root.selectedMarkerText : root.unselectedMarkerText
                font: root.font
                color: root.currentIndex === monitor_entry.index ? root.theme.accentColor : root.theme.inactive_infillColor
            }
            Text {
                id: selected_text
                anchors {
                    left: selected_marker.visible ? selected_marker.right : parent.left
                    right: parent.right
                    leftMargin: selected_marker.visible ? root.markerGap : root.selectedMarkerSpace
                    verticalCenter: parent.verticalCenter
                }
                text: monitor_entry.modelData.name
                color: root.currentIndex === monitor_entry.index ? root.theme.mainColor : root.theme.subTextColor
                font: root.font
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
        }
        // Hovered, highlighted, and selected entry background
        background: Rectangle {
            radius: root.theme.radiusSmall
            color: {
                if (monitor_entry.highlighted || monitor_entry.hovered)
                    return root.theme.hover_infillColor;
                if (root.currentIndex === monitor_entry.index)
                    return root.theme.active_infillColor;
                return "transparent";
            }
        }
    }

    // Popup containing the scrollable monitor list
    popup: Popup {
        id: monitor_popup

        y: root.height + root.popupGap
        width: root.width

        padding: root.popupHorizontalPadding

        implicitHeight: Math.min(monitor_list.contentHeight + topPadding + bottomPadding, root.popupMaxHeight)

        contentItem: ListView {
            id: monitor_list
            clip: true
            implicitHeight: contentHeight
            model: root.popup.visible ? root.delegateModel : null
            currentIndex: root.highlightedIndex
            boundsBehavior: Flickable.StopAtBounds
        }

        // Popup surface and border
        background: Rectangle {
            color: root.theme.tooltipBg
            border.color: root.theme.borderColor
            border.width: 1
            radius: root.theme.radiusMedium
        }
    }

    // Tooltip
    hoverEnabled: true
    HoverHandler {
        id: monitor_hover
    }
    ToolTip {
        id: monitor_tooltip

        visible: monitor_hover.hovered && root.appState.chosen_monitor >= 0

        text: "Identify selected monitor"

        delay: 300

        x: (parent.width - width) / 2
        y: -height - 6

        leftPadding: 10
        rightPadding: 10
        topPadding: 6
        bottomPadding: 6

        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.toolTip_fontSize
        font.bold: true

        contentItem: Text {
            text: monitor_tooltip.text
            color: root.theme.mainColor
            font: monitor_tooltip.font
            horizontalAlignment: Text.AlignHCenter
        }

        background: Rectangle {
            color: root.theme.tooltipBg
            border.color: root.theme.tooltipBorder
            border.width: 1
            radius: root.theme.radiusMedium
        }
    }
}
