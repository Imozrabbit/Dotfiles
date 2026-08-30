import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import qs.core as Core
import qs.services as Services

Item {
    id: root

    required property Core.Theme theme
    required property Services.Weather weatherService

    readonly property int activeIndex: {
        for (let index = 0; index < root.weatherService.locations.length; index++) {
            if (root.weatherService.locations[index].key === root.weatherService.activeLocationKey)
                return index;
        }
        return -1;
    }
    readonly property var activeLocation: root.activeIndex >= 0 ? root.weatherService.locations[root.activeIndex] : null

    function locationLabel(location) {
        if (!location)
            return "No saved locations";
        const details = [location.region, location.country].filter(value => value !== "");
        return location.name + (details.length > 0 ? ", " + details.join(", ") : "");
    }

    function weatherInfo(code, isDay) {
        switch (code) {
        case 0:
            return {
                icon: isDay ? "󰖙" : "󰖔",
                label: "Clear"
            };
        case 1:
        case 2:
        case 3:
            return {
                icon: "󰖕",
                label: "Cloudy"
            };
        case 45:
        case 48:
            return {
                icon: "󰖑",
                label: "Fog"
            };
        case 51:
        case 53:
        case 55:
        case 56:
        case 57:
            return {
                icon: "󰖗",
                label: "Drizzle"
            };
        case 61:
        case 63:
        case 65:
        case 66:
        case 67:
            return {
                icon: "󰖗",
                label: "Rain"
            };
        case 71:
        case 73:
        case 75:
        case 77:
            return {
                icon: "󰖘",
                label: "Snow"
            };
        case 80:
            return {
                icon: "󰖗",
                label: "Light Rain"
            };
        case 81:
            return {
                icon: "󰖗",
                label: "Rain"
            };
        case 82:
            return {
                icon: "󰖗",
                label: "Heavy Rain"
            };
        case 85:
            return {
                icon: "󰖘",
                label: "Light Snow"
            };
        case 86:
            return {
                icon: "󰖘",
                label: "Heavy Snow"
            };
        case 95:
        case 96:
        case 99:
            return {
                icon: "󰖓",
                label: "Thunderstorm"
            };
        default:
            return {
                icon: "󰖐",
                label: "Unknown"
            };
        }
    }

    function dayLabel(date) {
        const parts = date.split("-");
        if (parts.length !== 3)
            return date;
        return Qt.formatDate(new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2])), "ddd");
    }

    component ForecastCard: Item {
        required property Core.Theme cardTheme
        default property alias content: cardContent.data

        Rectangle {
            x: 1
            y: 1
            width: parent.width - 2
            height: parent.height - 3
            radius: parent.cardTheme.radiusMedium
            color: "#18000000"
        }

        Rectangle {
            id: cardFace

            width: parent.width - 2
            height: parent.height - 3
            radius: parent.cardTheme.radiusMedium
            color: Qt.lighter(parent.cardTheme.calendarBackgroundColor, 1.08)
            border.color: parent.cardTheme.weatherCardBorderColor
            border.width: 1
        }

        Item {
            id: cardContent

            anchors.fill: cardFace
            anchors.margins: 7
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            ComboBox {
                id: locationSelector

                Layout.fillWidth: true
                leftPadding: 5

                enabled: root.weatherService.locations.length > 0
                model: root.weatherService.locations
                currentIndex: root.activeIndex
                displayText: root.activeLocation ? root.locationLabel(root.activeLocation) : "No saved locations"
                palette.text: enabled ? root.theme.calendarDayColor : root.theme.calendarAdjacentDayColor
                palette.buttonText: enabled ? root.theme.calendarDayColor : root.theme.calendarAdjacentDayColor
                font {
                    family: root.theme.fontFamily
                    pixelSize: root.theme.calendarDayFontSize + 1
                    bold: false
                }
                onActivated: index => root.weatherService.selectLocation(model[index].key)

                background: Rectangle {
                    color: Qt.darker(root.theme.calendarBackgroundColor, 1.1)
                    border.color: root.theme.calendarBorderColor
                    border.width: 1
                    radius: 4
                }

                delegate: ItemDelegate {
                    required property int index
                    required property var modelData

                    width: locationSelector.width
                    highlighted: locationSelector.highlightedIndex === index

                    contentItem: Text {
                        text: root.locationLabel(parent.modelData)
                        color: parent.highlighted ? root.theme.calendarTodayTextColor : root.theme.calendarDayColor
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                        font.family: root.theme.fontFamily
                        font.pixelSize: root.theme.calendarDayFontSize
                    }

                    background: Rectangle {
                        color: parent.highlighted ? root.theme.calendarTodayColor : "transparent"
                        radius: 3
                    }
                }

                popup: Popup {
                    y: locationSelector.height
                    width: locationSelector.width
                    implicitHeight: Math.min(contentItem.implicitHeight + 8, 220)
                    padding: 4

                    contentItem: ListView {
                        clip: true
                        implicitHeight: contentHeight
                        model: locationSelector.popup.visible ? locationSelector.delegateModel : null
                        currentIndex: locationSelector.highlightedIndex
                        ScrollIndicator.vertical: ScrollIndicator {}
                    }

                    background: Rectangle {
                        color: Qt.darker(root.theme.calendarBackgroundColor, 1.1)
                        border.color: root.theme.calendarBorderColor
                        border.width: 1
                        radius: 4
                    }
                }
            }

            Button {
                enabled: root.activeLocation !== null
                text: "󰆴"
                palette.buttonText: enabled ? root.theme.calendarDayColor : root.theme.calendarAdjacentDayColor
                onClicked: root.weatherService.removeLocation(root.weatherService.activeLocationKey)
                background: null

                HoverHandler {
                    cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            TextField {
                id: searchField

                Layout.fillWidth: true
                leftPadding: 8
                placeholderText: "Search city"
                color: root.theme.calendarDayColor
                placeholderTextColor: root.theme.calendarAdjacentDayColor
                font {
                    family: root.theme.fontFamily
                    pixelSize: root.theme.calendarDayFontSize + 1
                    bold: false
                }
                selectByMouse: true
                onAccepted: root.weatherService.search(text)

                background: Rectangle {
                    color: Qt.darker(root.theme.calendarBackgroundColor, 1.1)
                    border.color: root.theme.calendarBorderColor
                    border.width: 1
                    radius: 4
                }
            }

            Button {
                enabled: !root.weatherService.searching && searchField.text.trim() !== ""
                text: root.weatherService.searching ? "󰇘󰇘 " : "Search"
                font {
                    family: root.theme.fontFamily
                    pixelSize: root.theme.calendarDayFontSize + 1
                    bold: false
                }
                palette.buttonText: enabled ? root.theme.calendarHeaderColor : root.theme.calendarAdjacentDayColor
                onClicked: root.weatherService.search(searchField.text)
                background: null

                HoverHandler {
                    cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: root.weatherService.searchError !== ""
            text: root.weatherService.searchError
            color: root.theme.calendarAdjacentDayColor
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.calendarDayFontSize
        }

        ListView {
            id: resultList

            Layout.fillWidth: true
            Layout.fillHeight: true
            leftMargin: 5
            rightMargin: 5
            visible: root.weatherService.searchResults.length > 0
            clip: true
            spacing: 4
            model: root.weatherService.searchResults

            delegate: Button {
                required property var modelData

                width: resultList.width
                height: 34
                onClicked: {
                    root.weatherService.addLocation(modelData);
                    searchField.clear();
                }
                background: null

                contentItem: Text {
                    text: root.locationLabel(parent.modelData)
                    color: root.theme.calendarDayColor
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.calendarDayFontSize
                }
            }
        }

        ColumnLayout {
            id: forecastContent

            readonly property var current: root.weatherService.currentWeather || ({})
            readonly property var currentInfo: root.weatherInfo(current.code, current.isDay === 1)

            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: resultList.count === 0 && root.weatherService.hasForecast
            spacing: 11

            Item {
                Layout.fillWidth: true
                Layout.topMargin: 7
                implicitHeight: currentRow.implicitHeight

                RowLayout {
                    id: currentRow

                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 15

                    Text {
                        text: forecastContent.currentInfo.icon
                        color: root.theme.calendarHeaderColor
                        font.family: root.theme.fontFamily
                        font.pixelSize: 35
                    }

                    Text {
                        text: Math.round(forecastContent.current.temperature) + "°"
                        color: root.theme.calendarTodayTextColor
                        font.family: root.theme.fontFamily
                        font.pixelSize: 28
                        font.bold: true
                    }

                    ColumnLayout {
                        spacing: 1
                        transform: Translate {
                            x: 10
                        }

                        Text {
                            text: forecastContent.currentInfo.label
                            Layout.alignment: Qt.AlignHCenter
                            color: root.theme.calendarDayColor
                            font.family: root.theme.fontFamily
                            font.pixelSize: root.theme.calendarDayFontSize + 1
                            font.bold: true
                        }

                        Text {
                            text: "Feels " + Math.round(forecastContent.current.apparentTemperature) + "° | " + Math.round(forecastContent.current.high) + "°/" + Math.round(forecastContent.current.low) + "°"
                            Layout.alignment: Qt.AlignHCenter
                            color: root.theme.weatherSecondaryColor
                            font.family: root.theme.fontFamily
                            font.pixelSize: root.theme.calendarDayFontSize - 1
                        }

                        Text {
                            text: Math.round(forecastContent.current.windSpeed) + " km/h | " + Number(forecastContent.current.precipitation).toFixed(1) + " mm"
                            Layout.alignment: Qt.AlignHCenter
                            color: root.theme.weatherSecondaryColor
                            font.family: root.theme.fontFamily
                            font.pixelSize: root.theme.calendarDayFontSize - 1
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: root.weatherService.forecastError !== ""
                text: root.weatherService.forecastError
                color: root.theme.weatherSecondaryColor
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.calendarDayFontSize - 1
            }

            Item {
                id: forecastColumns

                readonly property int sectionGap: 10
                readonly property real sectionWidth: Math.max(0, (width - sectionGap) / 2)

                Layout.fillWidth: true
                Layout.fillHeight: true

                ForecastCard {
                    id: hourlyCard

                    cardTheme: root.theme
                    width: forecastColumns.sectionWidth * 1.15
                    height: Math.max(0, parent.height - 16)
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 0

                        Text {
                            text: "Next few hours"
                            Layout.alignment: Qt.AlignHCenter
                            transform: Translate {
                                y: -14
                            }
                            color: root.theme.calendarWeekdayColor
                            font.family: root.theme.fontFamily
                            font.pixelSize: root.theme.calendarDayFontSize + 1
                            font.bold: false
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            transform: Translate {
                                y: -5
                                x: 2
                            }

                            GridLayout {
                                anchors.centerIn: parent
                                columns: 3
                                columnSpacing: 20
                                rowSpacing: 10

                                Repeater {
                                    model: root.weatherService.hourlyForecast

                                    delegate: ColumnLayout {
                                        id: hourCell

                                        required property var modelData
                                        readonly property var info: root.weatherInfo(modelData.code, modelData.isDay === 1)

                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        spacing: 0

                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: hourCell.modelData.time
                                            color: root.theme.weatherSecondaryColor
                                            font.family: root.theme.fontFamily
                                            font.pixelSize: root.theme.calendarDayFontSize - 1
                                        }

                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: hourCell.info.icon
                                            color: root.theme.calendarDayColor
                                            font.family: root.theme.fontFamily
                                            font.pixelSize: root.theme.calendarDayFontSize + 4
                                        }

                                        RowLayout {
                                            Layout.alignment: Qt.AlignHCenter
                                            spacing: 3

                                            Text {
                                                text: Math.round(hourCell.modelData.temperature) + "°"
                                                color: root.theme.calendarDayColor
                                                font.family: root.theme.fontFamily
                                                font.pixelSize: root.theme.calendarDayFontSize
                                                font.bold: true
                                            }

                                            Text {
                                                text: Math.round(hourCell.modelData.precipitationChance) + "%"
                                                color: root.theme.weatherSecondaryColor
                                                font.family: root.theme.fontFamily
                                                font.pixelSize: root.theme.calendarDayFontSize - 1
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                ForecastCard {
                    cardTheme: root.theme
                    width: forecastColumns.sectionWidth * 0.85
                    height: Math.max(0, parent.height - 16)
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 10

                        Text {
                            text: "Next few days"
                            Layout.alignment: Qt.AlignHCenter
                            transform: Translate {
                                y: -14
                            }
                            color: root.theme.calendarWeekdayColor
                            font.family: root.theme.fontFamily
                            font.pixelSize: root.theme.calendarDayFontSize + 1
                            font.bold: false
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            transform: Translate {
                                y: -9
                                x: 3
                            }

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 10

                                Repeater {
                                    model: root.weatherService.dailyForecast

                                    delegate: RowLayout {
                                        id: dayRow

                                        required property var modelData
                                        readonly property var info: root.weatherInfo(modelData.code, true)

                                        Layout.alignment: Qt.AlignHCenter
                                        spacing: 11

                                        Text {
                                            text: root.dayLabel(dayRow.modelData.date)
                                            color: root.theme.calendarDayColor
                                            font.family: root.theme.fontFamily
                                            font.pixelSize: root.theme.calendarDayFontSize
                                            font.bold: true
                                        }

                                        Text {
                                            text: dayRow.info.icon
                                            color: root.theme.calendarDayColor
                                            font.family: root.theme.fontFamily
                                            font.pixelSize: root.theme.calendarDayFontSize + 7
                                        }

                                        ColumnLayout {
                                            spacing: 1

                                            Text {
                                                text: Math.round(dayRow.modelData.high) + "°/" + Math.round(dayRow.modelData.low) + "°"
                                                color: root.theme.calendarDayColor
                                                font.family: root.theme.fontFamily
                                                font.pixelSize: root.theme.calendarDayFontSize
                                            }

                                            Text {
                                                text: Math.round(dayRow.modelData.precipitationChance) + "%"
                                                color: root.theme.weatherSecondaryColor
                                                font.family: root.theme.fontFamily
                                                font.pixelSize: root.theme.calendarDayFontSize
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: resultList.count === 0 && !root.weatherService.hasForecast
            text: !root.activeLocation ? "Add a location to show weather" : root.weatherService.loading ? "Loading weather…" : root.weatherService.forecastError !== "" ? root.weatherService.forecastError : "Open the panel to load weather"
            color: root.activeLocation ? root.theme.calendarHeaderColor : root.theme.calendarAdjacentDayColor
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.WordWrap
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.calendarDayFontSize
            font.bold: root.activeLocation !== null
        }
    }
}
