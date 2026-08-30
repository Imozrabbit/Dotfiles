pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

import qs.core as Core
import qs.services as Services

PanelWindow {
    id: root

    required property bool barRevealed
    required property date currentDate
    required property Core.Theme theme
    required property Services.Weather weatherService

    property date displayedDate: currentDate
    function moveMonth(offset) {
        displayedDate = new Date(displayedDate.getFullYear(), displayedDate.getMonth() + offset, 1);
    }

    visible: false
    onVisibleChanged: {
        if (visible) {
            displayedDate = currentDate;
            root.weatherService.refreshIfStale();
        }
    }

    color: "transparent"
    focusable: true

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.namespace: "calendar-menu"

    Shortcut {
        sequence: "Esc"
        enabled: root.visible
        onActivated: root.visible = false
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: mouse => {
            const inside = calendarCard.x <= mouse.x && mouse.x <= calendarCard.x + calendarCard.width && calendarCard.y <= mouse.y && mouse.y <= calendarCard.y + calendarCard.height;
            if (!inside)
                root.visible = false;
        }
    }

    Rectangle {
        id: calendarCard

        width: 680
        height: 320
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: root.barRevealed ? 17 : 10
        anchors.bottomMargin: root.barRevealed ? 40 : 10
        color: root.theme.calendarBackgroundColor
        border.color: root.theme.calendarBorderColor
        border.width: 1
        radius: 8

        WeatherPanel {
            id: weatherPanel

            width: 360
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: 12
            theme: root.theme
            weatherService: root.weatherService
        }

        Rectangle {
            id: panelSeparator

            width: 1
            anchors.left: weatherPanel.right
            anchors.leftMargin: 12
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.topMargin: 16
            anchors.bottomMargin: 16
            color: root.theme.calendarBorderColor
            opacity: 0.55
        }

        ColumnLayout {
            anchors.left: panelSeparator.right
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: 12
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Button {
                    text: "<"
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    palette.buttonText: root.theme.calendarHeaderColor
                    font {
                        family: root.theme.fontFamily
                        pixelSize: root.theme.calendarHeaderFontSize
                    }
                    onClicked: root.moveMonth(-1)
                    HoverHandler {
                        cursorShape: Qt.PointingHandCursor
                    }
                    background: null
                }

                Button {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 2
                    onClicked: {
                        root.displayedDate = root.currentDate;
                    }
                    HoverHandler {
                        cursorShape: Qt.PointingHandCursor
                    }
                    contentItem: Text {
                        id: currentDateTime_text
                        text: Qt.formatDateTime(root.displayedDate, "MMMM yyyy")
                        color: root.theme.calendarHeaderColor
                        font.family: root.theme.fontFamily
                        font.pixelSize: root.theme.calendarHeaderFontSize
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: null
                }

                Button {
                    text: ">"
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    palette.buttonText: root.theme.calendarHeaderColor
                    font {
                        family: root.theme.fontFamily
                        pixelSize: root.theme.calendarHeaderFontSize
                    }
                    onClicked: root.moveMonth(1)
                    HoverHandler {
                        cursorShape: Qt.PointingHandCursor
                    }
                    background: null
                }
            }

            DayOfWeekRow {
                Layout.fillWidth: true
                delegate: Text {
                    required property string shortName
                    text: shortName
                    color: root.theme.calendarWeekdayColor
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font {
                        family: root.theme.fontFamily
                        pixelSize: root.theme.calendarDayFontSize
                        bold: true
                    }
                }
            }

            MonthGrid {
                id: month_grid

                Layout.fillWidth: true
                Layout.fillHeight: true

                month: root.displayedDate.getMonth()
                year: root.displayedDate.getFullYear()

                delegate: Rectangle {
                    id: day_cell

                    required property var model

                    color: day_cell.model.today ? root.theme.calendarTodayColor : "transparent"
                    radius: 4

                    Text {
                        anchors.centerIn: parent
                        text: day_cell.model.day
                        color: day_cell.model.today ? root.theme.calendarTodayTextColor : day_cell.model.month === month_grid.month ? root.theme.calendarDayColor : root.theme.calendarAdjacentDayColor
                        font {
                            family: root.theme.fontFamily
                            pixelSize: root.theme.calendarDayFontSize
                            bold: day_cell.model.today
                        }
                    }
                }
            }
        }
    }
}
