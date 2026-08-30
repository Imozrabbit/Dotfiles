import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell

import qs.core as Core
import qs.services as Services

Rectangle {
    id: root

    required property Core.Theme theme
    required property bool dnd
    required property bool hasNotifications
    required property Services.Weather weatherService
    required property bool batteryAvailable
    required property int batteryCapacity
    required property string batteryStatus
    required property bool acOnline
    required property bool barRevealed
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

    implicitWidth: contentLayout.implicitWidth
    implicitHeight: contentLayout.implicitHeight
    radius: root.theme.radiusMedium
    color: root.theme.timeDateBg

    RowLayout {
        id: contentLayout

        anchors.fill: parent
        spacing: -10

        Item {
            implicitWidth: battery.implicitWidth + 11
            implicitHeight: Math.max(battery.implicitHeight, batterySeparator.implicitHeight)

            Battery {
                id: battery

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

                anchors.left: battery.right
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: 1
                implicitHeight: root.theme.timeDateFontSize
                color: root.theme.timeDateColor
                opacity: 0.25
            }
        }

        Item {
            implicitWidth: clock_button.implicitWidth + 20
            implicitHeight: clock_button.implicitHeight + 4

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
                    text: Qt.formatDateTime(clock.date, "hh:mm:ss")
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

        Item {
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

    CalendarPopup {
        id: calendar_popup

        barRevealed: root.barRevealed
        currentDate: clock.date
        theme: root.theme
        weatherService: root.weatherService
    }
}
