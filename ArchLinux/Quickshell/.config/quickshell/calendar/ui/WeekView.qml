pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../common/CalendarMath.js" as CalendarMath
import "../common/Theme.js" as Theme
import "../common/Zoom.js" as Zoom

Item {
    id: root

    required property var calendarService
    required property date weekStart
    required property date now

    signal eventActivated(var eventData)
    signal createRequested(var defaults)

    property int zoomPercent: 70
    property string selectedEventUid: ""
    readonly property real hourHeight: Zoom.hourHeight(zoomPercent)
    readonly property int gutterWidth: 58
    readonly property real dayWidth: (width - gutterWidth) / 7
    readonly property var days: buildDays()
    readonly property int allDayRows: days.reduce((maximum, day) => Math.max(maximum, day.allDay.length + (day.holidays.length > 0 ? 1 : 0)), 1)
    readonly property date currentWeekStart: CalendarMath.weekStart(root.now)
    readonly property bool showingCurrentWeek: currentWeekStart.getTime() === root.weekStart.getTime()
    readonly property int currentDayIndex: root.now.getDay() === 0 ? 6 : root.now.getDay() - 1

    function clearSelection() {
        root.selectedEventUid = "";
    }

    function selectEvent(eventData) {
        if (eventData && typeof eventData.uid === "string" && eventData.uid.length > 0)
            root.selectedEventUid = eventData.uid;
    }

    function setZoom(newPercent) {
        if (newPercent === root.zoomPercent)
            return;
        const viewportHeight = gridFlickable.height;
        const newHeight = Zoom.hourHeight(newPercent);
        const nextOffset = Zoom.anchoredOffset(gridFlickable.contentY, viewportHeight, root.hourHeight, newHeight, 24 * newHeight - viewportHeight);
        root.zoomPercent = newPercent;
        gridFlickable.contentY = nextOffset;
    }

    function zoomIn() {
        root.setZoom(Zoom.nextPercent(root.zoomPercent, 1));
    }

    function zoomOut() {
        root.setZoom(Zoom.nextPercent(root.zoomPercent, -1));
    }

    function resetZoom() {
        root.setZoom(70);
    }

    function resetPosition() {
        gridFlickable.contentY = 7.5 * root.hourHeight;
    }

    function buildDays() {
        const result = [];
        const rangeEnd = CalendarMath.addDays(root.weekStart, 7);
        const events = root.calendarService.eventsInRange(root.weekStart, rangeEnd);
        const holidays = root.calendarService.holidaysInRange(root.weekStart, rangeEnd);

        for (let index = 0; index < 7; ++index) {
            const date = CalendarMath.addDays(root.weekStart, index);
            const dayStartMs = CalendarMath.dayStart(date).getTime();
            const dayEndMs = CalendarMath.dayStart(CalendarMath.addDays(date, 1)).getTime();
            const allDay = [];
            const dayHolidays = [];
            const timed = [];

            for (const event of events) {
                if (!CalendarMath.rangesOverlap(event.startMs, event.endMs, dayStartMs, dayEndMs))
                    continue;
                if (event.allDay) {
                    allDay.push(event);
                } else {
                    const clippedStart = Math.max(event.startMs, dayStartMs);
                    const clippedEnd = Math.min(event.endMs, dayEndMs);
                    const layoutRange = CalendarMath.wallClockRange(clippedStart, clippedEnd, date);
                    timed.push(Object.assign({}, event, {
                        sourceEvent: event,
                        displayStartMs: event.startMs,
                        displayEndMs: event.endMs,
                        startMs: clippedStart,
                        endMs: clippedEnd,
                        layoutStart: layoutRange.start,
                        layoutEnd: layoutRange.end
                    }));
                }
            }

            for (const holiday of holidays) {
                if (CalendarMath.rangesOverlap(holiday.startMs, holiday.endMs, dayStartMs, dayEndMs))
                    dayHolidays.push(holiday);
            }

            result.push({
                date,
                holidays: dayHolidays,
                allDay,
                timed: CalendarMath.layoutTimedEvents(timed)
            });
        }
        return result;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 3

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 54

            Item {
                width: root.gutterWidth
                height: parent.height
            }

            Repeater {
                model: root.days

                delegate: Item {
                    id: days
                    required property int index
                    required property var modelData

                    x: root.gutterWidth + index * root.dayWidth
                    width: root.dayWidth
                    height: 54

                    readonly property bool today: modelData.date.getFullYear() === root.now.getFullYear() && modelData.date.getMonth() === root.now.getMonth() && modelData.date.getDate() === root.now.getDate()
                    readonly property bool holiday: modelData.holidays.length > 0

                    Rectangle {
                        anchors.centerIn: parent
                        width: 38
                        height: 38
                        radius: 19
                        color: parent.today ? Theme.accent : "transparent"
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 0

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: Qt.formatDate(days.modelData.date, "ddd").toUpperCase()
                            color: days.holiday ? "#b5aa96" : days.today ? Theme.background : Theme.textMuted
                            font.pixelSize: 9
                            font.letterSpacing: 1
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: Qt.formatDate(days.modelData.date, "dd")
                            color: days.holiday ? "#b5aa96" : days.today ? Theme.background : Theme.text
                            font.pixelSize: 16
                            font.weight: Font.DemiBold
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.rightMargin: 3
            Layout.preferredHeight: 15 + root.allDayRows * 30
            color: Theme.surface
            border.width: 1
            border.color: Theme.border
            radius: 5

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.ArrowCursor
                onClicked: root.clearSelection()
                onDoubleClicked: mouse => {
                    const dayIndex = Math.floor((mouse.x - root.gutterWidth) / root.dayWidth);
                    if (dayIndex < 0 || dayIndex > 6)
                        return;
                    const start = CalendarMath.dayStart(CalendarMath.addDays(root.weekStart, dayIndex));
                    const end = CalendarMath.addDays(start, 1);
                    root.createRequested({
                        allDay: true,
                        startMs: start.getTime(),
                        endMs: end.getTime()
                    });
                }
            }

            Text {
                width: root.gutterWidth - 8
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 2
                horizontalAlignment: Text.AlignRight
                text: "ALL DAY"
                color: Theme.textMuted
                font.pixelSize: 8
                font.letterSpacing: 0.9
            }

            Repeater {
                model: root.days

                delegate: Item {
                    id: allDayColumn

                    required property int index
                    required property var modelData

                    x: root.gutterWidth + index * root.dayWidth
                    width: root.dayWidth
                    height: parent.height

                    Rectangle {
                        x: 6
                        y: 3
                        width: allDayColumn.width - 12
                        height: 20
                        visible: allDayColumn.modelData.holidays.length > 0
                        color: "#1f8ba7d6"
                        radius: 4

                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: 4
                            anchors.rightMargin: 4
                            text: CalendarMath.holidayLabel(allDayColumn.modelData.holidays)
                            textFormat: Text.PlainText
                            color: "#b5aa96"
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Repeater {
                        model: allDayColumn.modelData.allDay

                        delegate: EventCard {
                            required property int index
                            required property var modelData

                            x: 4
                            y: 8 + (allDayColumn.modelData.holidays.length > 0 ? 30 : 0) + index * 30
                            width: allDayColumn.width - 8
                            height: 26
                            compact: true
                            eventData: modelData
                            selected: root.selectedEventUid === (modelData.sourceEvent ?? modelData).uid
                            conflicted: root.calendarService.conflictService.isConflicted((modelData.sourceEvent ?? modelData).uid)
                            onSelectionRequested: event => root.selectEvent(event)
                            onActivated: event => root.eventActivated(event)
                        }
                    }
                }
            }
        }

        Flickable {
            id: gridFlickable

            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: 24 * root.hourHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick

            Component.onCompleted: contentY = 7.5 * root.hourHeight

            MouseArea {
                anchors.fill: parent
                z: 1000
                acceptedButtons: Qt.NoButton

                onWheel: wheel => {
                    const delta = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.pixelDelta.y;
                    const direction = Zoom.wheelDirection((wheel.modifiers & Qt.ControlModifier) !== 0, delta);
                    if (direction === 0) {
                        wheel.accepted = false;
                        return;
                    }

                    root.setZoom(Zoom.nextPercent(root.zoomPercent, direction));
                    wheel.accepted = true;
                }
            }

            Item {
                width: gridFlickable.width
                height: gridFlickable.contentHeight

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.ArrowCursor
                    onClicked: root.clearSelection()
                    onDoubleClicked: mouse => {
                        const dayIndex = Math.floor((mouse.x - root.gutterWidth) / root.dayWidth);
                        if (dayIndex < 0 || dayIndex > 6)
                            return;
                        const minutes = Math.max(0, Math.min(1380, Math.floor(mouse.y / root.hourHeight) * 60));
                        const date = CalendarMath.addDays(root.weekStart, dayIndex);
                        const start = new Date(date.getFullYear(), date.getMonth(), date.getDate(), Math.floor(minutes / 60), minutes % 60);
                        root.createRequested({
                            allDay: false,
                            startMs: start.getTime(),
                            endMs: start.getTime() + 60 * 60 * 1000
                        });
                    }
                }

                Repeater {
                    model: 25

                    delegate: Rectangle {
                        required property int index

                        x: root.gutterWidth
                        y: index * root.hourHeight
                        width: parent.width - root.gutterWidth
                        height: 1
                        color: Theme.grid
                    }
                }

                Repeater {
                    model: 24

                    delegate: Text {
                        required property int index

                        x: 0
                        y: index * root.hourHeight - 7
                        width: root.gutterWidth - 8
                        text: String(index).padStart(2, "0") + ":00"
                        horizontalAlignment: Text.AlignRight
                        color: Theme.textMuted
                        font.pixelSize: 9
                    }
                }

                Repeater {
                    model: root.days

                    delegate: Item {
                        id: dayColumn

                        required property int index
                        required property var modelData

                        x: root.gutterWidth + index * root.dayWidth
                        width: root.dayWidth
                        height: parent.height

                        Rectangle {
                            anchors.left: parent.left
                            width: 1
                            height: parent.height
                            color: Theme.grid
                        }

                        Repeater {
                            model: dayColumn.modelData.timed

                            delegate: EventCard {
                                required property var modelData

                                readonly property real laneWidth: (dayColumn.width - 9 - (modelData.columns - 1) * 3) / modelData.columns
                                readonly property real startMinutes: modelData.layoutStart
                                readonly property real endMinutes: modelData.layoutEnd
                                readonly property real durationPixels: (endMinutes - startMinutes) / 60 * root.hourHeight

                                x: 4 + modelData.column * (laneWidth + 3)
                                y: startMinutes / 60 * root.hourHeight + 2
                                width: laneWidth
                                height: durationPixels > 4 ? durationPixels - 4 : durationPixels
                                eventData: modelData
                                selected: root.selectedEventUid === (modelData.sourceEvent ?? modelData).uid
                                conflicted: root.calendarService.conflictService.isConflicted((modelData.sourceEvent ?? modelData).uid)
                                onSelectionRequested: event => root.selectEvent(event)
                                onActivated: event => root.eventActivated(event)
                            }
                        }
                    }
                }

                Rectangle {
                    visible: root.showingCurrentWeek
                    x: root.gutterWidth + root.currentDayIndex * root.dayWidth
                    y: (root.now.getHours() + root.now.getMinutes() / 60) * root.hourHeight
                    width: root.dayWidth
                    height: 1
                    color: Theme.currentTime

                    Rectangle {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 7
                        height: 7
                        radius: 4
                        color: Theme.currentTime
                    }
                }
            }
        }
    }
}
