import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell

import qs.core as Core

RowLayout {
    id: root

    required property Core.Theme theme

    Item {
        implicitWidth: clock_button.implicitWidth + 20
        implicitHeight: clock_button.implicitHeight + 4

        Rectangle {
            anchors.fill: parent
            radius: root.theme.radiusMedium
            color: root.theme.timeDateBg
        }

        Button {
            id: clock_button
            anchors.fill: parent
            enabled: true

            hoverEnabled: true
            HoverHandler {
                id: clock_hover
                cursorShape: Qt.PointingHandCursor
            }

            onClicked: calendar_popup.visible = !calendar_popup.visible

            implicitWidth: search_button_text.implicitWidth
            implicitHeight: search_button_text.implicitHeight

            contentItem: Text {
                id: search_button_text
                text: Qt.formatDateTime(clock.date, "hh:mm:ss dddd")
                color: clock_hover.hovered ? root.theme.timeDateHoverColor : root.theme.timeDateColor
                font {
                    family: root.theme.fontFamily
                    pixelSize: root.theme.timeDateFontSize
                    bold: true
                }
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            background: null
        }

        SystemClock {
            id: clock
            precision: SystemClock.Seconds
        }
    }

    CalendarPopup {
        id: calendar_popup

        anchorItem: clock_button
        currentDate: clock.date
        theme: root.theme
    }
}
