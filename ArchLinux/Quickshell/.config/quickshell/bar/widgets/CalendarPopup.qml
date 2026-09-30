pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

import qs.core as Core

PanelWindow { // qmllint disable uncreatable-type
    id: root

    required property bool barRevealed
    required property date currentDate
    required property Core.Theme theme
    required property var weatherService
    required property bool showWeather

    property date displayedDate: currentDate
    function moveMonth(offset) {
        displayedDate = new Date(displayedDate.getFullYear(), displayedDate.getMonth() + offset, 1);
    }

    visible: false
    onVisibleChanged: {
        if (visible) {
            displayedDate = currentDate;
            if (root.showWeather && root.weatherService)
                root.weatherService.refreshIfStale();
            calendarScroll.contentY = 0;
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

        readonly property bool stacked: root.showWeather && width < 680

        width: Math.min(root.showWeather ? 680 : 320, Math.max(0, root.width - anchors.rightMargin - 10))
        height: Math.min(stacked ? calendarContents.y + calendarContents.height + 12 : 320, Math.max(0, root.height - anchors.bottomMargin - 10))
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: root.barRevealed ? 17 : 10
        anchors.bottomMargin: root.barRevealed ? 40 : 10
        color: root.theme.calendarBackgroundColor
        border.color: root.theme.calendarBorderColor
        border.width: 1
        radius: 8
        clip: true

        Flickable {
            id: calendarScroll

            anchors.fill: parent
            contentWidth: width
            contentHeight: calendarCard.stacked ? calendarContents.y + calendarContents.height + 12 : 320
            clip: true
            boundsBehavior: Flickable.StopAtBounds
        }

        Loader {
            id: weatherPanel

            parent: calendarScroll.contentItem
            active: root.showWeather && Boolean(root.weatherService)
            x: 12
            y: 12
            width: calendarCard.stacked ? Math.max(0, parent.width - 24) : 360
            height: 296
            sourceComponent: WeatherPanel {
                anchors.fill: parent
                theme: root.theme
                weatherService: root.weatherService
            }
        }

        Rectangle {
            id: panelSeparator

            parent: calendarScroll.contentItem
            visible: root.showWeather
            x: calendarCard.stacked ? 12 : weatherPanel.x + weatherPanel.width + 12
            y: calendarCard.stacked ? weatherPanel.y + weatherPanel.height + 12 : 16
            width: calendarCard.stacked ? parent.width - 24 : 1
            height: calendarCard.stacked ? 1 : 288
            color: root.theme.calendarBorderColor
            opacity: 0.55
        }

        ColumnLayout {
            id: calendarContents

            parent: calendarScroll.contentItem
            x: !root.showWeather || calendarCard.stacked ? 12 : panelSeparator.x + panelSeparator.width + 12
            y: root.showWeather && calendarCard.stacked ? panelSeparator.y + panelSeparator.height + 12 : 12
            width: Math.max(0, parent.width - x - 12)
            height: 296
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
