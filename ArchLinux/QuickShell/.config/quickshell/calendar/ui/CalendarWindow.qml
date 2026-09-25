pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import "../common/CalendarMath.js" as CalendarMath
import "../common/Theme.js" as Theme

PanelWindow { //qmllint disable uncreatable-type
    id: root

    required property var calendarService
    property date weekDate: new Date()
    property date monthDate: new Date()
    property date agendaDate: new Date()
    property date now: new Date()
    property string currentView: "week"
    property int weekZoomPercent: 70
    property int monthWeeksPerPage: 3
    property int agendaZoomPercent: 100
    readonly property var loadedView: viewLoader.item
    property date monthVisibleDate: monthDate
    property var selectedEvent: null
    property var editorRequest: null
    property bool surfaceVisible: false
    property bool revealed: false
    property bool managerOpen: false
    property bool conflictOpen: false

    visible: root.surfaceVisible
    anchors.top: true
    implicitWidth: Math.min(1020, Math.round((root.screen ? root.screen.width : 1020) * 0.75))
    implicitHeight: 780
    exclusionMode: ExclusionMode.Ignore
    aboveWindows: true
    focusable: true
    color: "transparent"
    surfaceFormat.opaque: false
    WlrLayershell.namespace: "quickshell-calendar"
    WlrLayershell.keyboardFocus: root.surfaceVisible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    mask: Region {
        item: panel
    }

    HyprlandFocusGrab {
        id: focusGrab
        windows: [root]
    }

    Timer {
        id: hideTimer
        interval: 220
        repeat: false
        onTriggered: {
            if (!root.revealed)
                root.surfaceVisible = false;
        }
    }

    function screenForFocusedMonitor() {
        for (const candidate of Quickshell.screens) {
            const monitor = Hyprland.monitorFor(candidate);
            if (monitor && monitor.focused)
                return candidate;
        }

        const focusedMonitor = Hyprland.focusedMonitor;
        if (focusedMonitor) {
            for (const candidate of Quickshell.screens) {
                if (candidate.name === focusedMonitor.name)
                    return candidate;
            }
        }

        return root.screen;
    }

    function showWindow() {
        hideTimer.stop();
        const targetScreen = root.screenForFocusedMonitor();
        if (targetScreen)
            root.screen = targetScreen;
        if (!root.surfaceVisible)
            root.surfaceVisible = true;
        root.revealed = true;
    }

    function hideWindow() {
        root.revealed = false;
        focusGrab.active = false;
        hideTimer.restart();
    }

    function toggleWindow() {
        if (root.revealed)
            root.hideWindow();
        else
            root.showWindow();
        return root.revealed;
    }

    component NavButton: Rectangle {
        id: button

        property bool textOnly: false
        required property string label
        property real buttonWidth: label === "Today" ? 45 : 34
        property bool selected: false
        property bool alert: false
        property int alertCount: 0
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
            color: button.textOnly ? button.alert ? hover.hovered ? Qt.lighter(Theme.currentTime, 1.2) : Theme.currentTime : button.selected ? Theme.accent : hover.hovered ? Theme.text : Theme.textMuted : Theme.text
            font.pixelSize: button.label === "" ? 19 : button.label === "" ? 16 : parent.label === "Today" ? 15 : 13
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

        Rectangle {
            visible: button.alert && button.alertCount > 0
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: -7
            anchors.bottomMargin: 3
            width: badgeText.implicitWidth + 6
            height: badgeText.implicitHeight + 2
            radius: 7
            color: Theme.currentTime
            z: 1

            Text {
                id: badgeText
                anchors.centerIn: parent
                text: button.alertCount > 99 ? "99+" : String(button.alertCount)
                color: Theme.background
                font.pixelSize: 8
                font.weight: Font.DemiBold
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
        if (root.loadedView)
            root.loadedView.clearSelection();
    }

    function navigate(direction) {
        root.clearViewSelection();
        root.closeEventDetails();
        if (root.currentView === "week") {
            root.weekDate = CalendarMath.addDays(root.weekDate, direction * 7);
            return;
        }
        if (root.currentView === "agenda") {
            root.agendaDate = CalendarMath.addDays(root.agendaDate, direction * 14);
            return;
        }
        const target = new Date(root.monthVisibleDate.getTime());
        target.setDate(1);
        target.setMonth(target.getMonth() + direction);
        root.monthDate = target;
        root.monthVisibleDate = target;
    }

    function goToday() {
        root.clearViewSelection();
        root.closeEventDetails();
        const today = new Date();
        if (root.currentView === "week")
            root.weekDate = today;
        else if (root.currentView === "month") {
            root.monthDate = today;
            root.monthVisibleDate = today;
        } else
            root.agendaDate = today;
        if (root.loadedView)
            root.loadedView.resetPosition(today);
    }

    function showWeek() {
        if (root.currentView === "week")
            return;
        root.clearViewSelection();
        root.closeEventDetails();
        root.currentView = "week";
    }

    function showMonth() {
        if (root.currentView === "month")
            return;
        root.clearViewSelection();
        root.closeEventDetails();
        root.monthDate = root.monthVisibleDate;
        root.currentView = "month";
    }

    function showAgenda() {
        if (root.currentView === "agenda")
            return;
        root.clearViewSelection();
        root.closeEventDetails();
        root.currentView = "agenda";
    }

    function showEventDetails(eventData) {
        if (eventData && root.selectedEvent === null && root.editorRequest === null && !detailsCloseTimer.running) {
            const currentEvent = root.calendarService.events.find(event => event.uid === eventData.uid);
            if (root.calendarService.conflictService.isConflicted(currentEvent?.sourceUid || eventData.uid))
                root.openConflicts();
            else
                root.selectedEvent = currentEvent ?? eventData;
        }
    }

    function openConflicts() {
        detailsCloseTimer.stop();
        root.selectedEvent = null;
        root.editorRequest = null;
        root.managerOpen = false;
        root.conflictOpen = true;
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
            weekStart: CalendarMath.weekStart(root.weekDate)
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
            selectedDate: root.monthDate
            now: root.now
            weeksPerPage: root.monthWeeksPerPage
            onWeeksPerPageChanged: root.monthWeeksPerPage = weeksPerPage
            onVisibleDateChanged: {
                root.monthVisibleDate = visibleDate;
            }
            onEventActivated: event => root.showEventDetails(event)
            onCreateRequested: defaults => root.openCreate(defaults)
        }
    }

    Component {
        id: agendaViewComponent
        AgendaView {
            calendarService: root.calendarService
            selectedDate: root.agendaDate
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
            anchors.fill: parent

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
                y: headerBar.height + Math.round((parent.height - headerBar.height - height) / 2)
                width: Math.min(root.editorRequest ? 460 : 430, Math.max(0, parent.width - 48))
                height: Math.min(root.editorRequest ? 800 : 550, Math.max(0, parent.height - headerBar.height - 48))
                sourceComponent: root.editorRequest ? editorPanelComponent : detailsPanelComponent
            }
        }
    }

    ClippingRectangle {
        id: panel

        width: parent.width
        height: parent.height
        y: root.revealed ? 0 : -height
        color: Theme.background
        border.width: 0
        border.color: "transparent"
        topLeftRadius: 0
        topRightRadius: 0
        bottomLeftRadius: 12
        bottomRightRadius: 12

        Behavior on y {
            NumberAnimation {
                duration: 220
                easing.type: Easing.OutCubic
            }
        }

        HoverHandler {
            id: panelHover
            onHoveredChanged: {
                if (!hovered || focusGrab.active)
                    return;
                panel.forceActiveFocus(Qt.MouseFocusReason);
                focusGrab.active = true;
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
                                selected: root.editorRequest !== null
                                opacity: root.editorRequest !== null || enabled ? 1 : 0.45
                                onClicked: root.openCreate(root.headerCreateDefaults())
                            }
                            NavButton {
                                label: "Today"
                                textOnly: true
                                onClicked: root.goToday()
                                onRightClicked: {
                                    if (root.loadedView)
                                        root.loadedView.resetZoom();
                                }
                            }
                            NavButton {
                                label: ""
                                textOnly: true
                                buttonWidth: 12
                                selected: root.managerOpen || root.conflictOpen
                                alert: root.calendarService.conflictService.hasConflict
                                alertCount: root.calendarService.conflictService.conflicts.length
                                onClicked: root.calendarService.conflictService.hasConflict ? root.openConflicts() : root.managerOpen = true
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
                            text: Qt.formatDate(root.currentView === "month" ? root.monthVisibleDate : root.currentView === "week" ? root.weekDate : root.agendaDate, "MMMM yyyy")
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
                                textFormat: Text.PlainText
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
            id: detailsLoader
            anchors.fill: parent
            z: 100
            active: root.selectedEvent !== null || root.editorRequest !== null
            sourceComponent: detailsOverlayComponent
        }

        Loader {
            id: managerLoader
            anchors.fill: parent
            z: 200
            active: root.managerOpen && !root.conflictOpen
            sourceComponent: managerPanelComponent
        }

        Loader {
            id: conflictLoader
            anchors.fill: parent
            z: 300
            active: root.conflictOpen
            sourceComponent: conflictPanelComponent
        }
    }

    Component {
        id: managerPanelComponent
        CalendarManagerPanel {
            calendarService: root.calendarService
            onCloseRequested: root.managerOpen = false
        }
    }

    Component {
        id: conflictPanelComponent
        ConflictResolutionPanel {
            conflictService: root.calendarService.conflictService
            onCloseRequested: root.conflictOpen = false
        }
    }
}
