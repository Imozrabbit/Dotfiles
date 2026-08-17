pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic

import qs.core as Core

Item {
    id: container

    required property Core.Theme theme
    required property Core.AppState appState

    property bool ifActive: appState.chosen_utility !== ""
    property string disabledTooltip: "Pick a wallpaper utility first"

    implicitWidth: root.implicitWidth
    implicitHeight: root.implicitHeight

    HoverHandler {
        id: container_hover
    }

    ComboBox {
        id: root

        anchors.fill: parent

        enabled: container.ifActive

        // Start withtout selecting the first fit mode automatically
        currentIndex: -1

        property string placeholderText: "Select Fit Mode"

        property string selectedMarkerText: "▶"
        property string unselectedMarkerText: "▷"
        property int markerLeftMargin: 15
        property int markerGap: 0

        property int popupGap: 2
        property int popupHorizontalPadding: 4
        property int popupMaxHeight: 220

        property int indicatorLeftMargin: 15
        property int controlRightPadding: 3

        property bool showSelectedDot: true

        property int entryHorizontalPadding: 0
        property int entryHeight: 30

        // General font config, size and behavior
        hoverEnabled: true
        implicitHeight: 30
        leftPadding: indicatorSpace
        rightPadding: controlRightPadding
        font.family: container.theme.fontFamily
        font.pixelSize: container.theme.normalText_fontSize
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
        TextMetrics {
            id: placeholder_metrics
            font: root.font
            text: root.placeholderText
        }

        // Dynamic width control
        property int minimumWidth: 130
        readonly property int indicatorSpace: Math.ceil(root.indicator.implicitWidth) + indicatorLeftMargin
        readonly property int selectedMarkerSpace: showSelectedDot ? markerLeftMargin + Math.ceil(selected_marker_metrics.advanceWidth) + markerGap : 0
        readonly property int closedRequiredWidth: indicatorSpace + Math.ceil(selected_text_metrics.advanceWidth) + leftPadding + rightPadding
        readonly property int popupRequiredWidth: Math.max(popupHorizontalPadding * 2 + entryHorizontalPadding * 2 + selectedMarkerSpace + Math.ceil(selected_text_metrics.advanceWidth), closedRequiredWidth)
        implicitWidth: popup.visible ? Math.max(minimumWidth, popupRequiredWidth) : Math.max(minimumWidth, closedRequiredWidth)

        // Fit mode data
        model: container.appState.modes
        //displayText: currentIndex >= 0 ? currentText : placeholderText
        displayText: container.appState.chosen_mode !== "" ? container.appState.chosen_mode : placeholderText

        // Synchronize the ComboBox with modes stored in AppState
        function syncSelection() {
            Qt.callLater(function () {
                root.currentIndex = container.appState.modes.indexOf(container.appState.chosen_mode);
            });
        }
        Component.onCompleted: syncSelection()
        onCountChanged: syncSelection()

        // Store the newly selected mode in AppState
        onActivated: {
            container.appState.chosen_mode = currentText;
        }

        // Text displayed inside the closed ComboBox
        contentItem: Text {
            text: root.displayText
            color: container.appState.chosen_mode === "" ? container.theme.subTextColor : container.theme.mainColor
            font: root.font
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }

        // Icon displayed on the left side of the closed ComboBox
        indicator: Text {
            id: indicator
            text: "󰻶"
            anchors {
                left: parent.left
                leftMargin: root.indicatorLeftMargin
                verticalCenter: parent.verticalCenter
            }
            //color: root.hovered || root.popup.visible ? container.theme.mainColor : container.theme.subTextColor
            color: {
                if (container.ifActive) {
                    if (root.hovered || root.popup.visible) {
                        return container.theme.mainColor;
                    } else {
                        return container.theme.subTextColor;
                    }
                }
                return container.theme.subTextColor;
            }
            font.family: container.theme.fontFamily
            font.pixelSize: container.theme.normalText_fontSize
        }

        // Background and interaction states of the closed ComboBox
        background: Rectangle {
            radius: container.theme.radiusMedium
            border.width: 1
            border.color: container.theme.borderColor
            color: {
                if (container.ifActive) {
                    if (root.down)
                        return container.theme.pressed_infillColor;
                    if (root.hovered || root.popup.visible)
                        return container.theme.hover_infillColor;
                    return container.theme.infillColor;
                }
                return container.theme.infillColor;
            }
        }

        // Visual representation of each mode entry inside the popup
        delegate: ItemDelegate {
            id: mode_entry
            hoverEnabled: true
            required property string modelData
            required property int index
            width: ListView.view ? ListView.view.width : root.width - root.popupHorizontalPadding * 2
            height: root.entryHeight
            leftPadding: root.entryHorizontalPadding
            rightPadding: root.entryHorizontalPadding
            highlighted: root.highlightedIndex === mode_entry.index
            // Mode name and selected-state indicator
            contentItem: Item {
                Text {
                    id: selected_marker
                    //visible: root.showSelectedDot && root.currentIndex === monitor_entry.index
                    visible: true
                    anchors {
                        left: parent.left
                        leftMargin: root.markerLeftMargin
                        verticalCenter: parent.verticalCenter
                    }
                    text: root.currentIndex === mode_entry.index ? root.selectedMarkerText : root.unselectedMarkerText
                    font: root.font
                    color: root.currentIndex === mode_entry.index ? container.theme.accentColor : container.theme.inactive_infillColor
                }
                Text {
                    id: selected_text
                    anchors {
                        left: selected_marker.visible ? selected_marker.right : parent.left
                        right: parent.right
                        leftMargin: selected_marker.visible ? root.markerGap : root.selectedMarkerSpace
                        verticalCenter: parent.verticalCenter
                    }
                    text: mode_entry.modelData
                    color: root.currentIndex === mode_entry.index ? container.theme.mainColor : container.theme.subTextColor
                    font: root.font
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }
            }
            // Hovered, highlighted, and selected entry background
            background: Rectangle {
                radius: container.theme.radiusSmall
                color: {
                    if (mode_entry.highlighted || mode_entry.hovered)
                        return container.theme.hover_infillColor;
                    if (root.currentIndex === mode_entry.index)
                        return container.theme.active_infillColor;
                    return "transparent";
                }
            }
        }

        // Popup containing the scrollable fit mode list
        popup: Popup {
            id: mode_popup

            y: root.height + root.popupGap
            width: root.width

            padding: root.popupHorizontalPadding

            implicitHeight: Math.min(mode_list.contentHeight + topPadding + bottomPadding, root.popupMaxHeight)

            contentItem: ListView {
                id: mode_list
                clip: true
                implicitHeight: contentHeight
                model: root.popup.visible ? root.delegateModel : null
                currentIndex: root.highlightedIndex
                boundsBehavior: Flickable.StopAtBounds
            }

            // Popup surface and border
            background: Rectangle {
                color: container.theme.tooltipBg
                border.color: container.theme.borderColor
                border.width: 1
                radius: container.theme.radiusMedium
            }
        }
    }

    ToolTip {
        id: fitMode_disabledText
        visible: container_hover.hovered && !root.enabled
        text: container.disabledTooltip
        delay: 300

        x: (parent.width - width) / 2
        y: -height - 6

        leftPadding: 10
        rightPadding: 10
        topPadding: 6
        bottomPadding: 6

        font.family: container.theme.fontFamily
        font.pixelSize: container.theme.toolTip_fontSize
        font.bold: true

        contentItem: Text {
            text: fitMode_disabledText.text
            color: container.theme.mainColor
            font: fitMode_disabledText.font
            horizontalAlignment: Text.AlignHCenter
        }

        background: Rectangle {
            color: container.theme.tooltipBg
            border.color: container.theme.tooltipBorder
            border.width: 1
            radius: container.theme.radiusMedium
        }
    }
}
