pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell

import qs.core as Core

Rectangle {
    id: root

    required property Core.Theme theme
    required property var outputScreen
    required property bool dnd
    required property bool hasNotifications
    required property date currentDate
    required property var weatherService
    required property bool batteryAvailable
    required property int batteryCapacity
    required property string batteryStatus
    required property bool acOnline
    required property bool barRevealed
    required property bool showBattery
    required property bool showClock
    required property bool showCalendar
    required property bool showWeather
    required property bool showNotifications
    required property real batteryEnergyNowUwh
    required property real batteryEnergyFullUwh
    required property real batteryEnergyFullDesignUwh
    required property real batteryPowerNowUw
    required property int batteryChargeStartThreshold
    required property int batteryChargeEndThreshold
    required property int batteryCycleCount
    required property string batteryPowerProfile
    required property bool batteryActionBusy
    required property string batteryActionError

    signal notificationsRequested
    signal batteryPanelOpened
    signal batteryPowerProfileRequested(string profile)
    signal batteryChargeThresholdsRequested(int startValue, int endValue)

    readonly property bool batteryDetailsVisible: root.showBattery && battery.watchingThresholds

    implicitWidth: contentLayout.implicitWidth
    implicitHeight: contentLayout.implicitHeight
    visible: root.showBattery || root.showClock || root.showCalendar || root.showNotifications
    radius: root.theme.radiusMedium
    color: root.theme.timeDateBg

    RowLayout {
        id: contentLayout

        anchors.fill: parent
        spacing: -10

        Item {
            visible: root.showBattery
            implicitWidth: battery.implicitWidth + 11
            implicitHeight: Math.max(battery.implicitHeight, batterySeparator.implicitHeight)

            Battery {
                id: battery

                outputScreen: root.outputScreen
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                available: root.batteryAvailable
                capacity: root.batteryCapacity
                status: root.batteryStatus
                acOnline: root.acOnline
                energyNowUwh: root.batteryEnergyNowUwh
                energyFullUwh: root.batteryEnergyFullUwh
                energyFullDesignUwh: root.batteryEnergyFullDesignUwh
                powerNowUw: root.batteryPowerNowUw
                chargeStartThreshold: root.batteryChargeStartThreshold
                chargeEndThreshold: root.batteryChargeEndThreshold
                cycleCount: root.batteryCycleCount
                activePowerProfile: root.batteryPowerProfile
                actionBusy: root.batteryActionBusy
                actionError: root.batteryActionError
                barRevealed: root.barRevealed
                theme: root.theme
                onPanelOpened: root.batteryPanelOpened()
                onPowerProfileRequested: profile => root.batteryPowerProfileRequested(profile)
                onChargeThresholdsRequested: (startValue, endValue) => root.batteryChargeThresholdsRequested(startValue, endValue)
            }

            Rectangle {
                id: batterySeparator

                visible: root.showBattery && (root.showClock || root.showCalendar || root.showNotifications)
                anchors.left: battery.right
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: 1
                implicitHeight: root.theme.timeDateFontSize
                color: root.theme.timeDateColor
                opacity: 0.25
            }
        }

        Item {
            visible: root.showClock || root.showCalendar
            implicitWidth: clock_button.implicitWidth + 20
            implicitHeight: clock_button.implicitHeight + 4

            Button {
                id: clock_button
                anchors.fill: parent
                enabled: root.showCalendar

                hoverEnabled: true
                HoverHandler {
                    id: clock_hover
                    cursorShape: root.showCalendar ? Qt.PointingHandCursor : Qt.ArrowCursor
                }

                onClicked: {
                    // qmllint disable missing-property
                    if (calendarLoader.item)
                        calendarLoader.item.visible = !calendarLoader.item.visible;
                    // qmllint enable missing-property
                }

                implicitWidth: search_button_text.implicitWidth
                implicitHeight: search_button_text.implicitHeight

                contentItem: Text {
                    id: search_button_text
                    text: root.showClock ? Qt.formatDateTime(root.currentDate, "hh:mm:ss") : "󰃭"
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
        }

        Item {
            visible: root.showNotifications
            implicitWidth: notificationText.implicitWidth + 20
            implicitHeight: notificationText.implicitHeight + 4

            Text {
                id: notificationText

                anchors.centerIn: parent
                text: root.dnd ? (root.hasNotifications ? "󰂛" : "󰪑") : (root.hasNotifications ? "" : "")
                color: notificationMouse.containsMouse ? root.theme.timeDateHoverColor : root.theme.timeDateColor
                font {
                    family: root.theme.fontFamily
                    pixelSize: root.theme.timeDateFontSize
                    bold: true
                }
            }

            MouseArea {
                id: notificationMouse

                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: root.notificationsRequested()
            }
        }
    }

    LazyLoader {
        id: calendarLoader
        active: root.showCalendar

        CalendarPopup {
            screen: root.outputScreen
            barRevealed: root.barRevealed
            currentDate: root.currentDate
            theme: root.theme
            weatherService: root.weatherService
            showWeather: root.showWeather
        }
    }
}
