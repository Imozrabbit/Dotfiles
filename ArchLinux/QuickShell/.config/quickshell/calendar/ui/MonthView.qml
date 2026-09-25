pragma ComponentBehavior: Bound
import QtQuick
import "../common/CalendarMath.js" as CalendarMath
import "../common/Theme.js" as Theme
import "../common/Zoom.js" as Zoom

Item {
    id: root

    required property var calendarService
    required property date selectedDate
    required property date now
    property int weeksPerPage: 3
    property string selectedEventUid: ""
    property date visibleDate: CalendarMath.weekStart(selectedDate)
    property date pendingPositionDate: selectedDate
    property bool positioning: false

    signal eventActivated(var eventData)
    signal createRequested(var defaults)

    property date bufferStart: CalendarMath.weekStart(selectedDate)
    readonly property date bufferEnd: CalendarMath.addDays(bufferStart, bufferWeeks * 7)
    property int bufferWeeks: 53
    readonly property var rangeEvents: calendarService.eventsInRange(bufferStart, bufferEnd)
    readonly property var rangeHolidays: calendarService.holidaysInRange(bufferStart, bufferEnd)
    readonly property var weeks: buildWeeks()
    readonly property real dayWidth: width / 7
    readonly property var monthColors: ["#60a5fa", "#818cf8", "#a78bfa", "#e879f9", "#f472b6", "#fb7185", "#fb923c", "#fbbf24", "#a3e635", "#4ade80", "#2dd4bf", "#22d3ee"]
    property real nominalWeekHeight: 0
    property bool extendingBuffer: false
    property real pendingPositionOffset: 0
    readonly property int maxBufferWeeks: 104

    function clearSelection() {
        root.selectedEventUid = "";
    }

    function selectEvent(eventData) {
        if (eventData && typeof eventData.uid === "string" && eventData.uid.length > 0)
            root.selectedEventUid = eventData.uid;
    }

    function zoomIn() {
        root.setZoom(Zoom.nextWeeksPerPage(root.weeksPerPage, 1));
    }

    function zoomOut() {
        root.setZoom(Zoom.nextWeeksPerPage(root.weeksPerPage, -1));
    }

    function resetZoom() {
        root.setZoom(3);
    }

    function resetPosition(date) {
        root.extendingBuffer = false;
        root.pendingPositionOffset = 0;
        root.recenterBuffer(date);
        root.schedulePositionDate(date);
    }

    function setZoom(nextWeeks) {
        if (nextWeeks === root.weeksPerPage)
            return;
        const dateToKeep = root.positioning ? root.pendingPositionDate : root.visibleDate;
        root.schedulePositionDate(dateToKeep);
        root.weeksPerPage = nextWeeks;
    }

    function schedulePositionDate(date) {
        root.positioning = true;
        root.pendingPositionDate = date;
        pageFlickable.cancelFlick();
        positionTimer.restart();
    }

    function recenterBuffer(date) {
        root.bufferStart = CalendarMath.addDays(CalendarMath.weekStart(date), -26 * 7);
        root.bufferWeeks = 53;
    }

    function ensureDateInBuffer(date) {
        const target = CalendarMath.weekStart(date).getTime();
        if (target >= root.bufferStart.getTime() && target < root.bufferEnd.getTime())
            return false;
        root.recenterBuffer(date);
        return true;
    }

    function maybeExtendBuffer() {
        if (root.positioning || root.extendingBuffer || root.weeks.length === 0)
            return;
        const index = root.topVisibleWeekIndex();
        if (index < 0)
            return;

        const edgeSize = 8;
        const chunkSize = 13;
        const item = pageFlickable.itemAtIndex(index);
        const offset = item ? pageFlickable.contentY - item.y : 0;
        const anchorDate = root.weeks[index].days[0].date;
        if (index < edgeSize) {
            root.extendingBuffer = true;
            root.pendingPositionOffset = offset;
            root.schedulePositionDate(anchorDate);
            root.bufferStart = CalendarMath.addDays(root.bufferStart, -chunkSize * 7);
            if (root.bufferWeeks < root.maxBufferWeeks)
                root.bufferWeeks = Math.min(root.maxBufferWeeks, root.bufferWeeks + chunkSize);
        } else if (index >= root.weeks.length - edgeSize) {
            root.extendingBuffer = true;
            root.pendingPositionOffset = offset;
            root.schedulePositionDate(anchorDate);
            if (root.bufferWeeks < root.maxBufferWeeks)
                root.bufferWeeks = Math.min(root.maxBufferWeeks, root.bufferWeeks + chunkSize);
            else
                root.bufferStart = CalendarMath.addDays(root.bufferStart, chunkSize * 7);
        }
    }

    function rebuildModel() {
        root.schedulePositionDate(root.positioning ? root.pendingPositionDate : root.visibleDate);
        pageFlickable.model = root.weeks;
    }

    function updateWeekHeight() {
        root.schedulePositionDate(root.positioning ? root.pendingPositionDate : root.visibleDate);
        root.nominalWeekHeight = pageFlickable.height / root.weeksPerPage;
    }

    function handleWeeksPerPageChanged() {
        root.updateWeekHeight();
    }

    function buildWeeks() {
        const result = [];
        const buckets = root.buildEventBuckets();
        for (let weekIndex = 0; weekIndex < root.bufferWeeks; ++weekIndex) {
            const days = [];
            let maxEvents = 0;
            for (let dayIndex = 0; dayIndex < 7; ++dayIndex) {
                const bucket = buckets[weekIndex * 7 + dayIndex];
                const date = bucket.date;
                const events = bucket.events;
                maxEvents = Math.max(maxEvents, events.length);
                days.push({
                    date,
                    events,
                    holidays: bucket.holidays
                });
            }
            result.push({
                days,
                maxEvents,
                hasHolidays: days.some(day => day.holidays.length > 0),
                monthStartIndex: CalendarMath.monthStartIndex(days[0].date)
            });
        }
        return result;
    }

    function buildEventBuckets() {
        const buckets = [];
        const indexes = {};
        let date = CalendarMath.dayStart(root.bufferStart);
        let index = 0;
        while (date.getTime() < root.bufferEnd.getTime()) {
            const key = date.getFullYear() + "-" + date.getMonth() + "-" + date.getDate();
            indexes[key] = index++;
            buckets.push({
                date,
                events: [],
                holidays: []
            });
            date = CalendarMath.addDays(date, 1);
        }

        const rangeStartMs = root.bufferStart.getTime();
        const rangeEndMs = root.bufferEnd.getTime();
        for (const event of root.rangeEvents) {
            if (!event || !Number.isFinite(event.startMs) || !Number.isFinite(event.endMs) || event.endMs <= event.startMs)
                continue;

            const startMs = Math.max(event.startMs, rangeStartMs);
            const endMs = Math.min(event.endMs, rangeEndMs);
            if (endMs <= startMs)
                continue;

            let eventDate = CalendarMath.dayStart(new Date(startMs));
            const endDate = CalendarMath.dayStart(new Date(endMs));
            const lastEventDate = endMs === endDate.getTime() ? CalendarMath.addDays(endDate, -1) : endDate;
            while (eventDate.getTime() <= lastEventDate.getTime()) {
                const key = eventDate.getFullYear() + "-" + eventDate.getMonth() + "-" + eventDate.getDate();
                const dayIndex = indexes[key];
                if (dayIndex !== undefined) {
                    const dayStartMs = eventDate.getTime();
                    const dayEndMs = CalendarMath.dayStart(CalendarMath.addDays(eventDate, 1)).getTime();
                    const interval = CalendarMath.clippedInterval(event.startMs, event.endMs, dayStartMs, dayEndMs);
                    if (interval) {
                        const displayEvent = interval.start === event.startMs && interval.end === event.endMs ? event : Object.assign({}, event, {
                            sourceEvent: event,
                            displayStartMs: interval.start,
                            displayEndMs: interval.end
                        });
                        buckets[dayIndex].events.push(displayEvent);
                    }
                }
                eventDate = CalendarMath.addDays(eventDate, 1);
            }
        }

        const holidays = Array.isArray(root.rangeHolidays) ? root.rangeHolidays : [];
        for (const holiday of holidays) {
            if (!holiday || !Number.isFinite(holiday.startMs) || !Number.isFinite(holiday.endMs) || holiday.endMs <= holiday.startMs)
                continue;

            const startMs = Math.max(holiday.startMs, rangeStartMs);
            const endMs = Math.min(holiday.endMs, rangeEndMs);
            if (endMs <= startMs)
                continue;

            let holidayDate = CalendarMath.dayStart(new Date(startMs));
            const endDate = CalendarMath.dayStart(new Date(endMs));
            const lastHolidayDate = endMs === endDate.getTime() ? CalendarMath.addDays(endDate, -1) : endDate;
            while (holidayDate.getTime() <= lastHolidayDate.getTime()) {
                const key = holidayDate.getFullYear() + "-" + holidayDate.getMonth() + "-" + holidayDate.getDate();
                const dayIndex = indexes[key];
                if (dayIndex !== undefined)
                    buckets[dayIndex].holidays.push(holiday);
                holidayDate = CalendarMath.addDays(holidayDate, 1);
            }
        }
        return buckets;
    }

    function weekHeight(index) {
        const week = root.weeks[index];
        return Math.max(root.nominalWeekHeight, 34 + (week.monthStartIndex >= 0 ? 22 : 0) + week.maxEvents * 24 + (week.hasHolidays ? 20 : 0));
    }

    function weekHeaderInset(index) {
        return root.weeks[index].monthStartIndex >= 0 ? 22 : 0;
    }

    function topVisibleWeekIndex() {
        return pageFlickable.indexAt(pageFlickable.width / 2, pageFlickable.contentY);
    }

    function updateVisibleDate() {
        if (root.positioning || root.weeks.length === 0)
            return;
        const index = root.topVisibleWeekIndex();
        if (index < 0 || index >= root.weeks.length)
            return;
        const days = root.weeks[index].days;
        // A boundary week represents the month whose first day it contains.
        const date = (days.find(day => day.date.getDate() === 1) || days[0]).date;
        if (date.getTime() !== root.visibleDate.getTime())
            root.visibleDate = date;
    }

    function positionDate(date) {
        root.positioning = true;
        pageFlickable.cancelFlick();
        pageFlickable.forceLayout();
        const target = CalendarMath.weekStart(date).getTime();
        for (let index = 0; index < root.weeks.length; ++index) {
            if (root.weeks[index].days[0].date.getTime() === target) {
                pageFlickable.positionViewAtIndex(index, ListView.Beginning);
                // Newly created variable-height rows can change ListView's estimates.
                pageFlickable.forceLayout();
                pageFlickable.positionViewAtIndex(index, ListView.Beginning);
                if (root.pendingPositionOffset !== 0)
                    pageFlickable.contentY += root.pendingPositionOffset;
                break;
            }
        }
        root.pendingPositionOffset = 0;
        root.extendingBuffer = false;
        root.positioning = false;
        root.updateVisibleDate();
    }

    function eventLabel(event) {
        if (event.allDay)
            return event.title;
        const startMs = event.displayStartMs ?? event.startMs;
        return Qt.formatTime(new Date(startMs), "HH:mm") + "  " + event.title;
    }

    Timer {
        id: positionTimer

        interval: 0
        repeat: false
        onTriggered: root.positionDate(root.pendingPositionDate)
    }

    Connections {
        target: root

        function onWeeksPerPageChanged() {
            root.handleWeeksPerPageChanged();
        }
    }

    Item {
        id: weekdayHeader

        width: parent.width
        height: 30

        Repeater {
            model: ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]

            delegate: Text {
                required property int index
                required property string modelData

                x: index * root.dayWidth
                width: root.dayWidth
                anchors.verticalCenter: parent.verticalCenter
                text: modelData
                horizontalAlignment: Text.AlignHCenter
                color: Theme.textMuted
                font.pixelSize: 9
                font.letterSpacing: 1
                font.weight: Font.DemiBold
            }
        }
    }

    ListView {
        id: pageFlickable

        anchors.top: weekdayHeader.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        contentWidth: width
        currentIndex: -1
        cacheBuffer: 0
        footer: Item {
            width: pageFlickable.width
            height: root.weeks.length > 0 ? Zoom.trailingViewportPadding(pageFlickable.height, root.weekHeight(root.weeks.length - 1)) : 0
        }
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick

        onContentYChanged: {
            root.updateVisibleDate();
            root.maybeExtendBuffer();
        }
        onHeightChanged: root.updateWeekHeight()

        WheelHandler {
            target: null
            acceptedModifiers: Qt.ControlModifier

            onWheel: wheel => {
                const delta = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.pixelDelta.y;
                const direction = Zoom.wheelDirection(true, delta);
                if (direction > 0)
                    root.zoomIn();
                else if (direction < 0)
                    root.zoomOut();
            }
        }

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

                if (direction > 0)
                    root.zoomIn();
                else
                    root.zoomOut();
                wheel.accepted = true;
            }
        }

        delegate: Item {
            id: weekRow

            required property int index
            required property var modelData
            readonly property real headerInset: modelData.monthStartIndex >= 0 ? 22 : 0

            x: 0
            width: pageFlickable.width
            height: Math.max(root.nominalWeekHeight, 34 + headerInset + modelData.maxEvents * 24 + (modelData.hasHolidays ? 20 : 0))

            Rectangle {
                readonly property real viewportY: weekRow.y + weekRow.height - pageFlickable.contentY

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                visible: Zoom.separatorVisible(viewportY, pageFlickable.height, height)
                height: 1
                color: Theme.border
            }

            Repeater {
                model: weekRow.modelData.days

                delegate: Item {
                    id: dayColumn

                    required property int index
                    required property var modelData

                    readonly property bool today: modelData.date.getFullYear() === root.now.getFullYear() && modelData.date.getMonth() === root.now.getMonth() && modelData.date.getDate() === root.now.getDate()
                    readonly property color monthColor: root.monthColors[modelData.date.getMonth()]

                    x: index * root.dayWidth
                    width: root.dayWidth
                    height: weekRow.height

                    Rectangle {
                        anchors.fill: parent
                        color: Qt.rgba(dayColumn.monthColor.r, dayColumn.monthColor.g, dayColumn.monthColor.b, 0.03)
                    }

                    Rectangle {
                        anchors.left: parent.left
                        width: dayColumn.index === 0 ? 0 : 1
                        height: parent.height
                        color: Theme.grid
                    }

                    Rectangle {
                        x: 6
                        y: 6 + weekRow.headerInset
                        width: 24
                        height: 20
                        radius: 10
                        color: dayColumn.today ? Theme.currentTime : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: Qt.formatDate(dayColumn.modelData.date, "d")
                            color: dayColumn.today ? Theme.background : Theme.text
                            font.pixelSize: 12
                            font.weight: dayColumn.today ? Font.DemiBold : Font.Normal
                        }
                    }

                    Text {
                        x: 6
                        y: 4
                        visible: dayColumn.index === weekRow.modelData.monthStartIndex
                        text: Qt.formatDate(dayColumn.modelData.date, "MMMM")
                        color: dayColumn.monthColor
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        cursorShape: Qt.ArrowCursor
                        onClicked: root.clearSelection()
                        onDoubleClicked: {
                            const start = CalendarMath.dayStart(dayColumn.modelData.date);
                            const end = CalendarMath.addDays(start, 1);
                            root.createRequested({
                                allDay: true,
                                startMs: start.getTime(),
                                endMs: end.getTime()
                            });
                        }
                    }

                    Repeater {
                        model: dayColumn.modelData.events

                        delegate: Rectangle {
                            id: monthEvent

                            required property int index
                            required property var modelData

                            property color eventColor: modelData.color
                            readonly property var sourceEvent: modelData.sourceEvent ?? modelData
                            readonly property bool selected: root.selectedEventUid === sourceEvent.uid
                            readonly property bool conflicted: root.calendarService.conflictService.isConflicted(sourceEvent.uid)
                            readonly property color selectionColor: Qt.lighter(eventColor, 1.18)

                            x: 6
                            y: 32 + weekRow.headerInset + index * 24
                            width: dayColumn.width - 13
                            height: 25
                            radius: 4
                            color: selected ? Qt.rgba(selectionColor.r, selectionColor.g, selectionColor.b, 0.28) : Qt.rgba(eventColor.r, eventColor.g, eventColor.b, 0.23)
                            border.width: 1
                            border.color: selected ? Qt.rgba(selectionColor.r, selectionColor.g, selectionColor.b, 0.72) : Qt.rgba(eventColor.r, eventColor.g, eventColor.b, 0.58)

                            Text {
                                anchors.fill: parent
                                anchors.leftMargin: 5
                                anchors.rightMargin: monthEvent.conflicted ? 18 : 4
                                text: root.eventLabel(parent.modelData)
                                textFormat: Text.PlainText
                                color: Theme.text
                                font.family: Theme.font
                                font.pixelSize: 9
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                                verticalAlignment: Text.AlignVCenter
                            }

                            Rectangle {
                                visible: monthEvent.conflicted
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.topMargin: 3
                                anchors.rightMargin: 3
                                width: 13
                                height: 13
                                radius: 7
                                color: Theme.currentTime
                                z: 1

                                Text {
                                    anchors.centerIn: parent
                                    anchors.verticalCenterOffset: 1
                                    text: "!"
                                    color: Theme.background
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.selectEvent(monthEvent.sourceEvent)
                                onDoubleClicked: {
                                    root.selectEvent(monthEvent.sourceEvent);
                                    root.eventActivated(monthEvent.sourceEvent);
                                }
                            }
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        visible: dayColumn.modelData.holidays.length > 0
                        z: 1
                        color: "transparent"
                        radius: 3
                        border.width: 2
                        border.color: "#b5aa96"
                    }

                    Text {
                        x: 6
                        width: Math.max(0, dayColumn.width - 12)
                        height: 16
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 6
                        visible: dayColumn.modelData.holidays.length > 0
                        text: CalendarMath.holidayLabel(dayColumn.modelData.holidays)
                        textFormat: Text.PlainText
                        //color: Theme.accent
                        color: "#b5aa96"
                        font.pixelSize: 12
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Rectangle {
                        anchors.fill: parent
                        z: 2
                        visible: dayColumn.today
                        color: "transparent"
                        opacity: 0.9
                        radius: 3
                        border.width: 1
                        border.color: Theme.currentTime
                    }
                }
            }
        }
    }

    Component.onCompleted: {
        root.recenterBuffer(root.selectedDate);
        root.schedulePositionDate(root.selectedDate);
        root.updateWeekHeight();
        root.rebuildModel();
    }
    onSelectedDateChanged: {
        root.schedulePositionDate(root.selectedDate);
        root.ensureDateInBuffer(root.selectedDate);
    }
    onWeeksChanged: root.rebuildModel()
}
