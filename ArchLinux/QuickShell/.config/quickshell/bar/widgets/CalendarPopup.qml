pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

import qs.core as Core

PopupWindow {
    id: root

    required property Item anchorItem
    required property date currentDate
    required property Core.Theme theme

    property date displayedDate: currentDate
    function moveMonth(offset) {
        displayedDate = new Date(displayedDate.getFullYear(), displayedDate.getMonth() + offset, 1);
    }

    visible: false
    onVisibleChanged: {
        if (visible)
            displayedDate = currentDate;
    }

    implicitWidth: 280
    implicitHeight: 240
    color: "transparent"
    grabFocus: true

    anchor.item: anchorItem
    anchor.rect.x: 9
    anchor.rect.y: -8
    anchor.rect.width: anchorItem.width
    anchor.rect.height: anchorItem.height

    anchor.edges: Edges.Top | Edges.Right
    anchor.gravity: Edges.Top | Edges.Left

    Rectangle {
        anchors.fill: parent
        color: root.theme.calendarBackgroundColor
        border.color: root.theme.calendarBorderColor
        border.width: 1
        radius: 8

        ColumnLayout {
            anchors.fill: parent
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
