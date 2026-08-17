pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

import qs.core as Core
import qs.ui.controls as Controls

Item {
    id: first_row

    required property Core.Theme theme
    required property Core.AppState appState
    signal flashRequested

    implicitHeight: controls.implicitHeight

    RowLayout {
        id: controls
        anchors.fill: parent
        spacing: first_row.theme.gapSmall

        Controls.MonitorComboBox {
            id: monitor_menu

            theme: first_row.theme
            appState: first_row.appState
        }

        Item {
            implicitWidth: flash_button.implicitWidth
            implicitHeight: flash_button.implicitHeight
            visible: first_row.appState.chosen_monitor >= 0 ? true : false

            HoverHandler {
                id: flash_hover
            }

            Button {
                id: flash_button

                hoverEnabled: true
                anchors.fill: parent

                enabled: true
                onClicked: {
                    onFlashRequested: {
                        first_row.flashRequested();
                    }
                }

                implicitWidth: flash_button_text.implicitWidth
                implicitHeight: flash_button_text.implicitHeight

                contentItem: Text {
                    id: flash_button_text

                    text: " "
                    color: {
                        if (flash_button.down)
                            return first_row.theme.accentPressed;
                        if (flash_hover.hovered)
                            return first_row.theme.accentHover;
                        return first_row.theme.subTextColor;
                    }
                    font.family: first_row.theme.fontFamily
                    font.pixelSize: first_row.theme.normalText_fontSize + 5
                    font.bold: true

                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                background: null
            }

            ToolTip {
                id: flash_tooltip

                visible: flash_hover.hovered

                text: "Flash Selected Monitor"

                delay: 300
                timeout: 3000

                x: (parent.width - width) / 2
                y: -height - 6

                leftPadding: 10
                rightPadding: 10
                topPadding: 6
                bottomPadding: 6

                font.family: first_row.theme.fontFamily
                font.pixelSize: first_row.theme.toolTip_fontSize
                font.bold: true

                contentItem: Text {
                    text: flash_tooltip.text
                    color: first_row.theme.mainColor
                    font: flash_tooltip.font
                    horizontalAlignment: Text.AlignHCenter
                }

                background: Rectangle {
                    color: first_row.theme.tooltipBg
                    border.color: first_row.theme.tooltipBorder
                    border.width: 1
                    radius: first_row.theme.radiusMedium
                }
            }
        }

        Item {
            Layout.fillWidth: true
        }

        Controls.FitModeComboBox {
            id: mode_menu

            theme: first_row.theme
            appState: first_row.appState
        }
    }

    Controls.WallpaperEngineComboBox {
        id: utility_menu

        anchors.centerIn: parent
        theme: first_row.theme
        appState: first_row.appState
    }
}
