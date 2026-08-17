pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import qs.core as Core
import qs.services as Services

RowLayout {
    id: root

    required property Core.Theme theme
    required property Core.AppState appState
    required property Services.WallpaperService wallpaperService

    signal previewRequested

    spacing: root.theme.gapSmall

    Item {
        implicitWidth: search_button.implicitWidth
        implicitHeight: search_button.implicitHeight

        HoverHandler {
            id: search_hover
        }

        Button {
            id: search_button

            hoverEnabled: true
            anchors.fill: parent

            enabled: true
            onClicked: {
                root.appState.if_searchIsland = !root.appState.if_searchIsland;
            }

            implicitWidth: search_button_text.implicitWidth
            implicitHeight: search_button_text.implicitHeight

            contentItem: Text {
                id: search_button_text

                text: "󰥸 "
                color: {
                    if (search_button.down)
                        return root.theme.accentPressed;
                    if (search_hover.hovered)
                        return root.theme.accentHover;
                    return root.theme.subTextColor;
                }
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.normalText_fontSize + 5
                font.bold: true

                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            background: null
        }

        ToolTip {
            id: search_tooltip

            visible: search_hover.hovered

            text: "Toggle search"

            delay: 300
            timeout: 3000

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
                text: search_tooltip.text
                color: root.theme.mainColor
                font: search_tooltip.font
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

    Item {
        implicitWidth: preview_button.implicitWidth
        implicitHeight: preview_button.implicitHeight

        HoverHandler {
            id: preview_hover
        }

        Button {
            id: preview_button

            hoverEnabled: true
            anchors.fill: parent

            enabled: root.appState.chosen_wallpaper !== "" && root.appState.chosen_monitor >= 0 && root.appState.chosen_mode !== ""
            onClicked: root.previewRequested()

            TextMetrics {
                id: preview_text_metrics
                text: preview_button_text.text
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.normalText_fontSize
                font.bold: true
            }

            implicitWidth: preview_text_metrics.advanceWidth + 24
            implicitHeight: preview_button_text.implicitHeight + 10

            contentItem: Text {
                id: preview_button_text

                text: root.appState.if_preview ? "Stop" : "Preview"
                color: root.theme.mainColor

                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.normalText_fontSize
                font.bold: true

                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            background: Rectangle {
                radius: root.theme.radiusMedium
                border.width: 1
                border.color: {
                    if (preview_button.enabled) {
                        return preview_button.hovered ? root.theme.hover_borderColor : root.theme.borderColor;
                    }
                    return root.theme.borderColor;
                }
                color: {
                    if (preview_button.enabled) {
                        if (preview_button.down)
                            return root.theme.pressed_infillColor;
                        if (preview_button.hovered)
                            return root.theme.hover_infillColor;
                        return root.theme.infillColor;
                    }
                    return root.theme.infillColor;
                }
            }
        }

        ToolTip {
            id: preview_tooltip

            visible: preview_hover.hovered && !preview_button.enabled

            text: {
                if (root.appState.chosen_monitor < 0)
                    return "Select a monitor";
                if (root.appState.chosen_mode === "")
                    return "Select a fit mode";
                if (root.appState.chosen_wallpaper === "")
                    return "Select a wallpaper";
                return "";
            }

            delay: 300
            timeout: 3000

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
                text: preview_tooltip.text
                color: root.theme.mainColor
                font: preview_tooltip.font
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

    Item {
        implicitWidth: confirm_button.implicitWidth
        implicitHeight: confirm_button.implicitHeight

        HoverHandler {
            id: confirm_hover
        }

        Button {
            id: confirm_button
            hoverEnabled: true

            enabled: root.appState.chosen_wallpaper !== "" && root.appState.chosen_monitor >= 0 && root.appState.chosen_mode !== ""
            onClicked: {
                root.wallpaperService.apply(root.appState.chosen_utility, root.appState.chosen_monitor_name, root.appState.chosen_wallpaper, root.appState.chosen_mode);
            }

            implicitWidth: confirm_button_text.implicitWidth + 24
            implicitHeight: confirm_button_text.implicitHeight + 10

            contentItem: Text {
                id: confirm_button_text

                text: "Confirm"
                color: root.theme.mainColor

                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.normalText_fontSize
                font.bold: true

                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            background: Rectangle {
                radius: root.theme.radiusMedium
                border.width: 1
                border.color: {
                    if (confirm_button.enabled) {
                        return confirm_button.hovered ? root.theme.hover_borderColor : root.theme.borderColor;
                    }
                    return root.theme.borderColor;
                }
                color: {
                    if (confirm_button.enabled) {
                        if (confirm_button.down)
                            return root.theme.pressed_infillColor;
                        if (confirm_button.hovered)
                            return root.theme.hover_infillColor;
                        return root.theme.infillColor;
                    }
                    return root.theme.infillColor;
                }
            }
        }

        ToolTip {
            id: confirm_tooltip

            visible: confirm_hover.hovered && !confirm_button.enabled

            text: {
                if (root.appState.chosen_monitor < 0)
                    return "Select a monitor";
                if (root.appState.chosen_mode === "")
                    return "Select a fit mode";
                if (root.appState.chosen_wallpaper === "")
                    return "Select a wallpaper";
                return "";
            }

            delay: 300
            timeout: 3000

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
                text: preview_tooltip.text
                color: root.theme.mainColor
                font: preview_tooltip.font
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
}
