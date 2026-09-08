pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../common/CalendarMath.js" as CalendarMath
import "../common/Theme.js" as Theme

FloatingWindow {
    id: root

    required property var calendarService
    property date selectedDate: calendarService.mockFocusDate
    property date now: new Date()
    property string currentView: "week"
    property int weekZoomPercent: 100
    property int monthWeeksPerPage: 3
    property int agendaZoomPercent: 100
    property date monthVisibleDate: selectedDate
    property var selectedEvent: null
    property var editorRequest: null

    visible: false
    title: "Calendar"
    implicitWidth: 1220
    implicitHeight: 780
    minimumSize: Qt.size(900, 600)
    color: Theme.background

    component NavButton: Rectangle {
        id: button

        property bool textOnly: false
        required property string label
        property real buttonWidth: label === "Today" ? 45 : 34
        property bool selected: false
        signal clicked
        signal rightClicked

        implicitWidth: buttonWidth
        implicitHeight: 30
        radius: Theme.radius
        color: textOnly ? "transparent" : selected || hover.hovered ? Theme.surfaceRaised : Theme.surface
        border.width: textOnly ? 0 : 1
        border.color: selected ? Theme.accent : Theme.border

        Text {
            anchors.centerIn: parent
            text: button.label
            color: button.textOnly ? button.selected ? Theme.accent : hover.hovered ? Theme.text : Theme.textMuted : Theme.text
            font.pixelSize: button.label === "" ? 19 : parent.label === "Today" ? 15 : 13
            font.weight: parent.label === "<" || parent.label === ">" ? Font.Bold : Font.Medium
        }

        HoverHandler {
            id: hover
        }

        TapHandler {
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onTapped: (eventPoint, tapButton) => {
                if (tapButton === Qt.RightButton)
                    button.rightClicked();
                else
                    button.clicked();
            }
        }
    }

    Timer {
        interval: 60000
        repeat: true
        running: root.visible
        triggeredOnStart: true
        onTriggered: root.now = new Date()
    }

    function clearViewSelection() {
        if (viewLoader.item)
            viewLoader.item.clearSelection();
    }

    function navigate(direction) {
        root.clearViewSelection();
        root.closeEventDetails();
        if (root.currentView === "week") {
            root.selectedDate = CalendarMath.addDays(root.selectedDate, direction * 7);
            return;
        }
        if (root.currentView === "agenda") {
            root.selectedDate = CalendarMath.addDays(root.selectedDate, direction * 14);
            return;
        }
        const target = new Date(root.monthVisibleDate.getTime());
        target.setDate(1);
        target.setMonth(target.getMonth() + direction);
        root.selectedDate = target;
        root.monthVisibleDate = root.selectedDate;
        if (viewLoader.item)
            viewLoader.item.schedulePositionDate(root.selectedDate);
    }

    function goToday() {
        root.clearViewSelection();
        root.closeEventDetails();
        root.selectedDate = new Date();
        if (root.currentView !== "month" || !viewLoader.item)
            root.monthVisibleDate = root.selectedDate;
        if (root.currentView === "month" && viewLoader.item)
            viewLoader.item.schedulePositionDate(root.selectedDate);
        if (root.currentView === "agenda" && viewLoader.item)
            viewLoader.item.resetPosition();
    }

    function showWeek() {
        root.clearViewSelection();
        root.closeEventDetails();
        if (root.currentView === "month")
            root.selectedDate = root.monthVisibleDate;
        root.currentView = "week";
    }

    function showMonth() {
        if (root.currentView === "month")
            return;
        root.clearViewSelection();
        root.closeEventDetails();
        root.monthVisibleDate = root.selectedDate;
        root.currentView = "month";
    }

    function showAgenda() {
        root.clearViewSelection();
        root.closeEventDetails();
        if (root.currentView === "month")
            root.selectedDate = root.monthVisibleDate;
        root.currentView = "agenda";
    }

    function showEventDetails(eventData) {
        if (eventData && root.selectedEvent === null && root.editorRequest === null && !detailsCloseTimer.running) {
            const currentEvent = root.calendarService.events.find(event => event.uid === eventData.uid);
            root.selectedEvent = currentEvent ?? eventData;
        }
    }

    function closeEventDetails() {
        if (root.selectedEvent !== null || root.editorRequest !== null)
            detailsCloseTimer.restart();
    }

    function headerCreateDefaults() {
        const date = new Date();
        const start = new Date(date.getFullYear(), date.getMonth(), date.getDate(), 9);
        return {
            allDay: false,
            startMs: start.getTime(),
            endMs: start.getTime() + 60 * 60 * 1000
        };
    }

    function openCreate(defaults) {
        detailsCloseTimer.stop();
        root.clearViewSelection();
        root.editorRequest = {
            mode: "create",
            eventData: null,
            defaults
        };
        root.selectedEvent = null;
    }

    function openEdit(eventData) {
        if (!eventData || eventData.readOnly)
            return;
        root.editorRequest = {
            mode: "edit",
            eventData,
            defaults: null
        };
    }

    function cancelEditor() {
        if (root.editorRequest && root.editorRequest.mode === "edit") {
            root.editorRequest = null;
            return;
        }
        root.closeEventDetails();
    }

    function editorSaved(eventData) {
        root.selectedEvent = eventData;
        root.editorRequest = null;
    }

    function eventDeleted() {
        root.clearViewSelection();
        root.closeEventDetails();
    }

    Timer {
        id: detailsCloseTimer

        interval: 0
        repeat: false
        onTriggered: {
            root.selectedEvent = null;
            root.editorRequest = null;
        }
    }

    Component {
        id: weekViewComponent
        WeekView {
            calendarService: root.calendarService
            weekStart: CalendarMath.weekStart(root.selectedDate)
            now: root.now
            zoomPercent: root.weekZoomPercent
            onZoomPercentChanged: root.weekZoomPercent = zoomPercent
            onEventActivated: event => root.showEventDetails(event)
            onCreateRequested: defaults => root.openCreate(defaults)
        }
    }

    Component {
        id: monthViewComponent
        MonthView {
            calendarService: root.calendarService
            selectedDate: root.selectedDate
            now: root.now
            weeksPerPage: root.monthWeeksPerPage
            onWeeksPerPageChanged: root.monthWeeksPerPage = weeksPerPage
            onVisibleDateChanged: root.monthVisibleDate = visibleDate
            onEventActivated: event => root.showEventDetails(event)
            onCreateRequested: defaults => root.openCreate(defaults)
        }
    }

    Component {
        id: agendaViewComponent
        AgendaView {
            calendarService: root.calendarService
            selectedDate: root.selectedDate
            now: root.now
            zoomPercent: root.agendaZoomPercent
            onZoomPercentChanged: root.agendaZoomPercent = zoomPercent
            onEventActivated: event => root.showEventDetails(event)
            onCreateRequested: defaults => root.openCreate(defaults)
        }
    }

    Component {
        id: detailsPanelComponent

        EventDetailsPanel {
            eventData: root.selectedEvent
            calendarService: root.calendarService
            onCloseRequested: root.closeEventDetails()
            onEditRequested: event => root.openEdit(event)
            onDeleted: root.eventDeleted()
        }
    }

    Component {
        id: editorPanelComponent

        EventEditorPanel {
            calendarService: root.calendarService
            mode: root.editorRequest ? root.editorRequest.mode : "create"
            eventData: root.editorRequest ? root.editorRequest.eventData : null
            defaults: root.editorRequest ? root.editorRequest.defaults : null
            onSaved: event => root.editorSaved(event)
            onCancelRequested: root.cancelEditor()
        }
    }

    Component {
        id: detailsOverlayComponent
        Item {
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.48)

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                    preventStealing: true
                    onClicked: root.closeEventDetails()
                    onWheel: wheel => wheel.accepted = true
                }
            }
            Loader {
                id: panelLoader
                z: 1
                x: Math.round((parent.width - width) / 2)
                y: Math.round((parent.height - height) / 2)
                width: Math.min(root.editorRequest ? 460 : 430, Math.max(0, parent.width - 48))
                height: Math.min(root.editorRequest ? 800 : 550, Math.max(0, parent.height - 48))
                sourceComponent: root.editorRequest ? editorPanelComponent : detailsPanelComponent
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            id: headerBar
            Layout.fillWidth: true
            Layout.preferredHeight: 55
            color: Theme.background
            border.width: 0
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: Theme.spacing

                Rectangle {
                    color: Theme.surface
                    radius: 20
                    implicitHeight: topLeft.implicitHeight + 3
                    implicitWidth: topLeft.implicitWidth + 30
                    RowLayout {
                        id: topLeft
                        anchors.centerIn: parent
                        spacing: 10
                        NavButton {
                            label: ""
                            textOnly: true
                            buttonWidth: 15
                            transform: Translate {
                                y: -1
                            }
                            enabled: root.editorRequest === null && root.calendarService.calendars.some(calendar => calendar.writable === true)
                            opacity: enabled ? 1 : 0.45
                            onClicked: root.openCreate(root.headerCreateDefaults())
                        }
                        NavButton {
                            label: "Today"
                            textOnly: true
                            onClicked: root.goToday()
                            onRightClicked: {
                                if (viewLoader.item)
                                    viewLoader.item.resetZoom();
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                Rectangle {
                    color: Theme.surface
                    radius: 20
                    implicitHeight: navRow.implicitHeight + 3
                    implicitWidth: navRow.implicitWidth + 20
                    RowLayout {
                        id: navRow
                        anchors.centerIn: parent
                        spacing: 3
                        NavButton {
                            label: "週"
                            buttonWidth: 20
                            textOnly: true
                            selected: root.currentView === "week"
                            onClicked: root.showWeek()
                        }
                        NavButton {
                            label: "月"
                            buttonWidth: 20
                            textOnly: true
                            selected: root.currentView === "month"
                            onClicked: root.showMonth()
                        }
                        NavButton {
                            label: "程"
                            buttonWidth: 20
                            textOnly: true
                            selected: root.currentView === "agenda"
                            onClicked: root.showAgenda()
                        }
                    }
                }
            }

            Rectangle {
                color: Theme.surface
                radius: 20
                implicitHeight: topMiddle.implicitHeight + 3
                implicitWidth: topMiddle.implicitWidth + 10
                anchors.centerIn: parent
                RowLayout {
                    id: topMiddle
                    anchors.centerIn: parent
                    spacing: 1
                    NavButton {
                        label: "<"
                        textOnly: true
                        onClicked: root.navigate(-1)
                    }
                    Text {
                        Layout.preferredWidth: 142
                        text: Qt.formatDate(root.currentView === "month" ? root.monthVisibleDate : root.selectedDate, "MMMM yyyy")
                        font.family: Theme.font
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        color: Theme.text
                        font.pixelSize: 17
                        font.weight: Font.DemiBold
                    }
                    NavButton {
                        label: ">"
                        textOnly: true
                        onClicked: root.navigate(1)
                    }
                }
            }
        }

        Loader {
            id: viewLoader

            Layout.fillWidth: true
            Layout.fillHeight: true
            sourceComponent: root.currentView === "week" ? weekViewComponent : root.currentView === "month" ? monthViewComponent : agendaViewComponent
        }
    }

    Rectangle {
        id: legendCard

        anchors.right: parent.right
        anchors.rightMargin: 15
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 15
        z: 50
        width: legendColumn.implicitWidth + 28
        height: legendColumn.implicitHeight + 23
        radius: Theme.radius
        color: Theme.surface
        border.width: 1
        border.color: Theme.border

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onWheel: wheel => wheel.accepted = true
        }

        ColumnLayout {
            id: legendColumn

            x: 12
            y: 12
            spacing: 8

            Repeater {
                model: root.calendarService.calendars

                delegate: Item {
                    id: calendarEntry

                    required property var modelData

                    Layout.preferredWidth: calendarRow.implicitWidth
                    Layout.preferredHeight: calendarRow.implicitHeight

                    RowLayout {
                        id: calendarRow

                        spacing: 7

                        Rectangle {
                            Layout.preferredWidth: 8
                            Layout.preferredHeight: 8
                            Layout.alignment: Qt.AlignVCenter
                            radius: 4
                            color: calendarEntry.modelData.visible ? calendarEntry.modelData.color : "transparent"
                            border.width: calendarEntry.modelData.visible ? 0 : 1
                            border.color: calendarEntry.modelData.color
                        }

                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            text: calendarEntry.modelData.name
                            color: Theme.textMuted
                            opacity: calendarEntry.modelData.visible || rowMouse.containsMouse ? 1 : 0.5
                            font.pixelSize: 11
                        }
                    }

                    MouseArea {
                        id: rowMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.calendarService.setCalendarVisible(calendarEntry.modelData.id, !calendarEntry.modelData.visible)
                    }
                }
            }
        }
    }

    Loader {
        anchors.top: parent.top
        anchors.topMargin: headerBar.height
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        z: 100
        active: root.selectedEvent !== null || root.editorRequest !== null
        sourceComponent: detailsOverlayComponent
    }
}
