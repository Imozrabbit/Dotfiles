pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../common/CalendarMath.js" as CalendarMath
import "../common/Theme.js" as Theme
import "../common/Zoom.js" as Zoom

Item {
    id: root

    required property var calendarService
    required property date selectedDate
    required property date now

    signal eventActivated(var eventData)
    signal createRequested(var defaults)

    property string selectedEventUid: ""
    property int zoomPercent: 100
    readonly property real zoomScale: zoomPercent / 100
    readonly property date rangeStart: CalendarMath.dayStart(selectedDate)
    readonly property date rangeEnd: CalendarMath.addDays(rangeStart, 14)
    readonly property var rangeEvents: calendarService.eventsInRange(rangeStart, rangeEnd)
    readonly property var days: CalendarMath.buildAgendaDays(rangeEvents, rangeStart, 14)

    function clearSelection() {
        root.selectedEventUid = "";
    }

    function resetPosition() {
        agendaFlickable.contentY = 0;
    }

    function setZoom(newPercent) {
        if (newPercent === root.zoomPercent)
            return;
        const oldScale = root.zoomScale;
        const nextScale = newPercent / 100;
        root.zoomPercent = newPercent;
        agendaFlickable.contentY = Math.max(0, agendaFlickable.contentY * nextScale / oldScale);
    }

    function zoomIn() {
        root.setZoom(Zoom.nextPercent(root.zoomPercent, 1));
    }

    function zoomOut() {
        root.setZoom(Zoom.nextPercent(root.zoomPercent, -1));
    }

    function resetZoom() {
        root.setZoom(100);
    }

    onSelectedDateChanged: root.resetPosition()

    function selectEvent(eventData) {
        if (eventData && typeof eventData.uid === "string" && eventData.uid.length > 0)
            root.selectedEventUid = eventData.uid;
    }

    function sameDay(left, right) {
        return left.getFullYear() === right.getFullYear() && left.getMonth() === right.getMonth() && left.getDate() === right.getDate();
    }

    function eventTimeLabel(event) {
        const start = new Date(event.startMs);
        const end = new Date(event.endMs);
        if (event.allDay) {
            const displayEnd = CalendarMath.addDays(end, -1);
            return root.sameDay(start, displayEnd) ? "ALL DAY" : "ALL DAY  " + Qt.formatDate(start, "MMM d") + "–" + Qt.formatDate(displayEnd, "MMM d");
        }
        if (root.sameDay(start, end))
            return Qt.formatTime(start, "HH:mm") + "–" + Qt.formatTime(end, "HH:mm");
        return Qt.formatDate(start, "MMM d") + " " + Qt.formatTime(start, "HH:mm") + " – " + Qt.formatDate(end, "MMM d") + " " + Qt.formatTime(end, "HH:mm");
    }

    Flickable {
        id: agendaFlickable

        anchors.fill: parent
        contentWidth: width
        contentHeight: agendaColumn.height + 32
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick

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

        ColumnLayout {
            id: agendaColumn

            x: 18
            y: 16
            width: Math.max(0, agendaFlickable.width - 36)
            spacing: 0

            Repeater {
                model: root.days

                delegate: Item {
                    id: dayRow

                    required property int index
                    required property var modelData

                    readonly property bool today: root.sameDay(modelData.date, root.now)
                    readonly property int eventCount: modelData.events.length

                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.max(72 * root.zoomScale, (20 + eventCount * 46) * root.zoomScale)

                    Rectangle {
                        anchors.fill: parent
                        color: dayRow.index % 2 === 0 ? Theme.background : Theme.surface
                        opacity: dayRow.index % 2 === 0 ? 1 : 0.32
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 1
                        color: Theme.border
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        cursorShape: Qt.ArrowCursor
                        onClicked: root.clearSelection()
                        onDoubleClicked: {
                            const start = CalendarMath.dayStart(dayRow.modelData.date);
                            const end = CalendarMath.addDays(start, 1);
                            root.createRequested({
                                allDay: true,
                                startMs: start.getTime(),
                                endMs: end.getTime()
                            });
                        }
                    }

                    Item {
                        id: dateRail

                        width: 112
                        height: parent.height

                        Text {
                            x: 4
                            y: 12 * root.zoomScale
                            text: Qt.formatDate(dayRow.modelData.date, "ddd").toUpperCase()
                            color: dayRow.today ? Theme.currentTime : Theme.textMuted
                            font.pixelSize: 10 * root.zoomScale
                            font.letterSpacing: 1
                            font.weight: Font.DemiBold
                        }

                        Rectangle {
                            x: 4
                            y: 30 * root.zoomScale
                            width: 78 * root.zoomScale
                            height: 28 * root.zoomScale
                            radius: 14 * root.zoomScale
                            color: dayRow.today ? Theme.currentTime : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: Qt.formatDate(dayRow.modelData.date, "MMM d")
                                color: dayRow.today ? Theme.background : Theme.text
                                font.pixelSize: 14 * root.zoomScale
                                font.weight: Font.DemiBold
                            }
                        }
                    }

                    ColumnLayout {
                        id: eventColumn

                        x: 128
                        y: 10
                        width: Math.max(0, dayRow.width - x)
                        spacing: 6

                        Repeater {
                            model: dayRow.modelData.events

                            delegate: Rectangle {
                                id: agendaEvent

                                required property int index
                                required property var modelData

                                property color eventColor: modelData.color
                                readonly property bool selected: root.selectedEventUid === modelData.uid
                                readonly property color selectionColor: Qt.lighter(eventColor, 1.18)

                                Layout.fillWidth: true
                            Layout.preferredHeight: 40 * root.zoomScale
                            radius: 5 * root.zoomScale
                                color: selected ? Qt.rgba(selectionColor.r, selectionColor.g, selectionColor.b, 0.28) : Qt.rgba(eventColor.r, eventColor.g, eventColor.b, 0.16)
                                border.width: 1
                                border.color: selected ? Qt.rgba(selectionColor.r, selectionColor.g, selectionColor.b, 0.72) : Qt.rgba(eventColor.r, eventColor.g, eventColor.b, 0.52)

                                Rectangle {
                                    width: 3 * root.zoomScale
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    anchors.left: parent.left
                                    anchors.topMargin: 1.5
                                    anchors.bottomMargin: 1.5
                                    anchors.leftMargin: 0.7
                                    radius: 20
                                    color: agendaEvent.selected ? agendaEvent.selectionColor : agendaEvent.eventColor
                                }

                                Text {
                                    x: 14 * root.zoomScale
                                    width: 170 * root.zoomScale
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.eventTimeLabel(parent.modelData)
                                    color: Theme.textMuted
                                    font.pixelSize: 10 * root.zoomScale
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                }

                                Text {
                                    x: 192 * root.zoomScale
                                    width: Math.max(0, parent.width - x - 12 * root.zoomScale)
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: parent.modelData.location ? parent.modelData.title + "  ·  " + parent.modelData.location : parent.modelData.title
                                    color: Theme.text
                                    font.pixelSize: 12 * root.zoomScale
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    acceptedButtons: Qt.LeftButton
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.selectEvent(agendaEvent.modelData)
                                    onDoubleClicked: {
                                        root.selectEvent(agendaEvent.modelData);
                                        root.eventActivated(agendaEvent.modelData);
                                    }
                                }
                            }
                        }

                        Text {
                            visible: dayRow.eventCount === 0
                            Layout.preferredHeight: visible ? 40 * root.zoomScale : 0
                            verticalAlignment: Text.AlignVCenter
                            text: "No events"
                            color: Theme.textMuted
                            font.pixelSize: 12 * root.zoomScale
                            font.italic: true
                        }
                    }
                }
            }
        }
    }
}
