pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import "../common/CalendarMath.js" as CalendarMath
import "../common/Theme.js" as Theme

Rectangle {
    id: root

    required property var calendarService
    required property string mode
    required property var eventData
    required property var defaults

    property string titleText: ""
    property string calendarId: ""
    property bool allDay: false
    property string startDateText: ""
    property string endDateText: ""
    property string startTimeText: "09:00"
    property string endTimeText: "10:00"
    property string locationText: ""
    property string descriptionText: ""
    property string errorField: ""
    property string errorMessage: ""
    property string expandedField: ""
    property var reminderDrafts: []
    property bool customReminderVisible: false
    property string customReminderText: ""
    readonly property int pickerCenterYear: new Date().getFullYear()
    readonly property var yearValues: buildRange(pickerCenterYear - 100, pickerCenterYear + 100)
    readonly property var monthValues: ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    readonly property var dayModels: [buildRange(1, 28), buildRange(1, 29), buildRange(1, 30), buildRange(1, 31)]
    readonly property var hourValues: buildRange(0, 23)
    readonly property var minuteValues: buildRange(0, 55, 5)
    readonly property var reminderPresets: [
        {
            label: "Add reminder...",
            minutes: -1
        },
        {
            label: "At start time",
            minutes: 0
        },
        {
            label: "5 minutes before",
            minutes: 5
        },
        {
            label: "10 minutes before",
            minutes: 10
        },
        {
            label: "15 minutes before",
            minutes: 15
        },
        {
            label: "30 minutes before",
            minutes: 30
        },
        {
            label: "1 hour before",
            minutes: 60
        },
        {
            label: "1 day before",
            minutes: 1440
        },
        {
            label: "Custom...",
            minutes: -1,
            custom: true
        }
    ]
    readonly property var writableCalendars: calendarService.calendars.filter(calendar => calendar.writable === true)

    signal saved(var eventData)
    signal cancelRequested

    color: Theme.surface
    radius: 13
    border.width: 1
    border.color: Theme.border
    focus: true

    Keys.onEscapePressed: event => {
        if (root.expandedField.length > 0)
            root.expandedField = "";
        else
            root.cancelRequested();
        event.accepted = true;
    }

    component FieldLabel: Text {
        Layout.leftMargin: 5
        color: Theme.textMuted
        font.pixelSize: 9
        font.letterSpacing: 1.2
        font.weight: Font.DemiBold
    }

    component FormField: Controls.TextField {
        id: textfield
        property bool invalid: false

        Layout.fillWidth: true
        Layout.preferredHeight: 34
        color: Theme.text
        placeholderTextColor: Theme.textMuted
        selectionColor: Theme.accent
        selectedTextColor: Theme.background
        font.pixelSize: 13
        font.family: Theme.font
        leftPadding: 10
        rightPadding: 10
        Keys.onEscapePressed: event => root.releaseEditorFocus(event)
        background: Rectangle {
            radius: Theme.radius
            color: Theme.background
            border.width: 1
            border.color: textfield.invalid ? Theme.currentTime : Theme.border
        }
    }

    component ActionButton: Rectangle {
        id: actionButton

        required property string label
        property bool primary: false
        signal clicked

        width: Math.max(80, buttonLabel.implicitWidth + 28)
        height: 34
        radius: Theme.radius
        color: primary ? Theme.accent : buttonHover.hovered ? Theme.surfaceRaised : Theme.background
        border.width: primary ? 0 : 1
        border.color: Theme.border

        Text {
            id: buttonLabel

            anchors.centerIn: parent
            text: actionButton.label
            color: actionButton.primary ? Theme.background : Theme.text
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }

        HoverHandler {
            id: buttonHover
            cursorShape: Qt.PointingHandCursor
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: actionButton.clicked()
        }
    }

    function dateText(date) {
        return date.getFullYear() + "-" + String(date.getMonth() + 1).padStart(2, "0") + "-" + String(date.getDate()).padStart(2, "0");
    }

    function timeText(date) {
        return String(date.getHours()).padStart(2, "0") + ":" + String(date.getMinutes()).padStart(2, "0");
    }

    function parseDate(text) {
        const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text);
        if (!match)
            return null;
        const date = new Date(0);
        date.setFullYear(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
        date.setHours(0, 0, 0, 0);
        return date.getFullYear() === Number(match[1]) && date.getMonth() === Number(match[2]) - 1 && date.getDate() === Number(match[3]) ? date : null;
    }

    function parseDateTime(dateValue, timeValue) {
        const date = root.parseDate(dateValue);
        const match = /^(\d{2}):(\d{2})$/.exec(timeValue);
        if (!date || !match || Number(match[1]) > 23 || Number(match[2]) > 59)
            return null;
        const year = date.getFullYear();
        const month = date.getMonth();
        const day = date.getDate();
        date.setHours(Number(match[1]), Number(match[2]), 0, 0);
        if (date.getFullYear() !== year || date.getMonth() !== month
                || date.getDate() !== day || date.getHours() !== Number(match[1])
                || date.getMinutes() !== Number(match[2]))
            return null;
        return date;
    }

    function buildRange(start, end, step) {
        const result = [];
        const increment = step ?? 1;
        for (let value = start; value <= end; value += increment)
            result.push(value);
        return result;
    }

    function targetDateText(target) {
        return target === "start" ? root.startDateText : root.endDateText;
    }

    function targetTimeText(target) {
        return target === "start" ? root.startTimeText : root.endTimeText;
    }

    function dateValue(target) {
        return root.parseDate(root.targetDateText(target)) ?? new Date();
    }

    function datePart(target, part) {
        const date = root.dateValue(target);
        if (part === "year")
            return date.getFullYear();
        if (part === "month")
            return date.getMonth();
        return date.getDate();
    }

    function dayValues(target) {
        const count = CalendarMath.daysInMonth(root.datePart(target, "year"), root.datePart(target, "month"));
        return root.dayModels[count - 28];
    }

    function setDatePart(target, part, value) {
        const date = root.dateValue(target);
        let year = date.getFullYear();
        let month = date.getMonth();
        let day = date.getDate();
        if (part === "year")
            year = value;
        else if (part === "month")
            month = value;
        else
            day = value;
        day = Math.min(day, CalendarMath.daysInMonth(year, month));
        const text = root.dateText(new Date(year, month, day));
        if (target === "start")
            root.startDateText = text;
        else
            root.endDateText = text;
    }

    function timePartText(target, part) {
        const values = root.targetTimeText(target).split(":");
        return part === "hour" ? values[0] ?? "" : values[1] ?? "";
    }

    function timePartIndex(target, part) {
        const value = Number(root.timePartText(target, part));
        if (part === "hour")
            return Number.isInteger(value) && value >= 0 && value <= 23 ? value : 0;
        const minute = Number.isInteger(value) && value >= 0 && value <= 59 ? CalendarMath.roundMinuteToStep(value, 5) : 0;
        return minute / 5;
    }

    function setTimePartText(target, part, value) {
        let hour = root.timePartText(target, "hour");
        let minute = root.timePartText(target, "minute");
        if (part === "hour")
            hour = value;
        else
            minute = value;
        const text = hour + ":" + minute;
        if (target === "start")
            root.startTimeText = text;
        else
            root.endTimeText = text;
    }

    function setTimePart(target, part, value) {
        root.setTimePartText(target, part, String(value).padStart(2, "0"));
    }

    function toggleWheel(field) {
        if (root.expandedField === field) {
            root.expandedField = "";
            return;
        }
        if (field.endsWith("Minute")) {
            const target = field.startsWith("start") ? "start" : "end";
            const value = Number(root.timePartText(target, "minute"));
            if (Number.isInteger(value) && value >= 0 && value <= 59)
                root.setTimePart(target, "minute", CalendarMath.roundMinuteToStep(value, 5));
        }
        root.expandedField = field;
    }

    function clearReminderError() {
        if (root.errorField !== "reminders")
            return;
        root.errorField = "";
        root.errorMessage = "";
    }

    function addReminder(minutes) {
        if (!Number.isSafeInteger(minutes) || minutes < 0) {
            root.setError("reminders", "Enter nonnegative whole minutes", customReminderField);
            return false;
        }
        if (root.reminderDrafts.some(reminder => reminder.minutesBefore === minutes)) {
            root.setError("reminders", "That reminder already exists", reminderPreset);
            return false;
        }
        root.reminderDrafts = root.reminderDrafts.concat([
            {
                minutesBefore: minutes
            }
        ]);
        root.clearReminderError();
        return true;
    }

    function removeReminder(index) {
        if (index < 0 || index >= root.reminderDrafts.length)
            return;
        root.reminderDrafts = root.reminderDrafts.slice(0, index).concat(root.reminderDrafts.slice(index + 1));
        root.clearReminderError();
    }

    function selectReminderPreset(index) {
        if (index <= 0 || index >= root.reminderPresets.length)
            return;
        const preset = root.reminderPresets[index];
        reminderPreset.currentIndex = 0;
        if (preset.custom === true) {
            root.customReminderVisible = true;
            customReminderField.forceActiveFocus();
            return;
        }
        root.customReminderVisible = false;
        root.customReminderText = "";
        root.addReminder(preset.minutes);
    }

    function addCustomReminder() {
        const text = root.customReminderText.trim();
        if (!/^\d+$/.test(text)) {
            root.setError("reminders", "Enter nonnegative whole minutes", customReminderField);
            return;
        }
        if (!root.addReminder(Number(text)))
            return;
        root.customReminderText = "";
        root.customReminderVisible = false;
        reminderPreset.forceActiveFocus();
    }

    function loadDraft() {
        const editing = root.mode === "edit" && root.eventData;
        const source = editing ? root.eventData : root.defaults;
        if (!source)
            return;

        root.titleText = editing ? source.title : "";
        root.locationText = editing ? source.location : "";
        root.descriptionText = editing ? source.description : "";
        root.reminderDrafts = editing && Array.isArray(source.reminders) ? source.reminders.map(reminder => ({
                    minutesBefore: reminder.minutesBefore
                })) : [];
        root.allDay = source.allDay === true;
        root.calendarId = editing ? source.calendarId : root.writableCalendars.length > 0 ? root.writableCalendars[0].id : "";

        const start = new Date(source.startMs);
        const end = new Date(source.endMs);
        root.startDateText = root.dateText(start);
        root.startTimeText = root.timeText(start);
        if (root.allDay)
            end.setDate(end.getDate() - 1);
        root.endDateText = root.dateText(end);
        root.endTimeText = root.timeText(end);
    }

    function focusField(field) {
        if (field === "calendarId")
            calendarCombo.forceActiveFocus();
        else if (field === "start")
            startDateField.forceActiveFocus();
        else if (field === "end")
            endDateField.forceActiveFocus();
        else if (field === "reminders")
            reminderPreset.forceActiveFocus();
    }

    function setError(field, message, control) {
        root.errorField = field;
        root.errorMessage = message;
        if (control)
            control.forceActiveFocus();
        else
            root.focusField(field);
    }

    function releaseEditorFocus(event) {
        root.forceActiveFocus();
        event.accepted = true;
    }

    function save() {
        root.errorField = "";
        root.errorMessage = "";
        const startDate = root.parseDate(root.startDateText);
        if (!startDate) {
            root.setError("start", "Enter start date as YYYY-MM-DD", startDateField);
            return;
        }
        const endDate = root.parseDate(root.endDateText);
        if (!endDate) {
            root.setError("end", "Enter end date as YYYY-MM-DD", endDateField);
            return;
        }

        let start;
        let end;
        if (root.allDay) {
            endDate.setDate(endDate.getDate() + 1);
            start = root.dateText(startDate);
            end = root.dateText(endDate);
        } else {
            const startValue = root.parseDateTime(root.startDateText, root.startTimeText);
            const endValue = root.parseDateTime(root.endDateText, root.endTimeText);
            if (!startValue) {
                root.setError("start", "Enter start time as HH:mm", startHourField);
                return;
            }
            if (!endValue) {
                root.setError("end", "Enter end time as HH:mm", endHourField);
                return;
            }
            start = startValue.toISOString();
            end = endValue.toISOString();
        }

        const data = {
            calendarId: root.calendarId,
            title: root.titleText,
            description: root.descriptionText,
            location: root.locationText,
            allDay: root.allDay,
            start,
            end,
            reminders: root.reminderDrafts.map(reminder => ({
                        minutesBefore: reminder.minutesBefore
                    }))
        };
        const result = root.mode === "edit" ? root.calendarService.updateEvent(root.eventData.uid, data) : root.calendarService.createEvent(data);
        if (!result.ok) {
            root.setError(result.field, result.message, null);
            return;
        }
        root.saved(result.event);
    }

    Component.onCompleted: {
        root.loadDraft();
        root.forceActiveFocus();
    }
    onAllDayChanged: {
        if (root.allDay && (root.expandedField.endsWith("Hour") || root.expandedField.endsWith("Minute")))
            root.expandedField = "";
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        preventStealing: true
        onPressed: root.forceActiveFocus()
        onWheel: wheel => wheel.accepted = true
    }

    Rectangle {
        id: editorHeader

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 13
        radius: 13
        height: 50
        color: Theme.surfaceRaised

        Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.mode === "edit" ? "Edit event" : "New event"
            color: Theme.text
            font.pixelSize: 21
            font.weight: Font.DemiBold
            font.family: Theme.font
        }
    }

    Flickable {
        id: formFlickable

        anchors.top: editorHeader.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: footer.top
        contentWidth: width
        contentHeight: formColumn.height + 40
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick

        ColumnLayout {
            id: formColumn

            x: 20
            y: 20
            width: Math.max(0, formFlickable.width - 40)
            spacing: 5

            FieldLabel {
                text: "TITLE"
            }
            FormField {
                id: titleField
                text: root.titleText
                placeholderText: "Untitled"
                onTextEdited: root.titleText = text
            }

            Item {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 4
            }
            FieldLabel {
                text: "CALENDAR"
            }
            Controls.ComboBox {
                id: calendarCombo

                Layout.fillWidth: true
                Layout.preferredHeight: 34
                leftPadding: 6
                model: root.writableCalendars
                textRole: "name"
                valueRole: "id"
                font.pixelSize: 13
                currentIndex: Math.max(0, root.writableCalendars.findIndex(calendar => calendar.id === root.calendarId))
                palette.text: Theme.text
                palette.buttonText: Theme.text
                palette.windowText: Theme.text
                palette.base: Theme.background
                palette.window: Theme.surfaceRaised
                palette.highlight: Theme.accent
                onActivated: index => root.calendarId = root.writableCalendars[index].id
                Keys.onEscapePressed: event => {
                    if (calendarCombo.popup.opened)
                        calendarCombo.popup.close();
                    else
                        root.forceActiveFocus();
                    event.accepted = true;
                }
                contentItem: Text {
                    leftPadding: calendarCombo.leftPadding
                    rightPadding: calendarCombo.indicator.width + 10
                    text: calendarCombo.displayText
                    color: Theme.text
                    font: calendarCombo.font
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }
                indicator: Text {
                    x: calendarCombo.width - width - 12
                    y: Math.round((calendarCombo.height - height) / 2)
                    text: ""
                    color: Theme.textMuted
                    font.family: Theme.font
                    font.pixelSize: 17
                    font.weight: Font.DemiBold
                }
                delegate: Controls.ItemDelegate {
                    id: calendarOption

                    required property int index

                    width: calendarCombo.width - 8
                    height: 34
                    highlighted: calendarCombo.highlightedIndex === index
                    contentItem: Text {
                        leftPadding: 8
                        text: calendarCombo.textAt(calendarOption.index)
                        color: Theme.text
                        font: calendarCombo.font
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                    background: Rectangle {
                        radius: Math.max(0, Theme.radius - 2)
                        color: calendarOption.highlighted || calendarOption.index === calendarCombo.currentIndex ? Theme.surfaceRaised : "transparent"
                    }
                }
                popup: Controls.Popup {
                    y: calendarCombo.height + 4
                    width: calendarCombo.width
                    implicitHeight: Math.min(contentItem.implicitHeight + 8, 180)
                    padding: 4
                    clip: true
                    contentItem: ListView {
                        clip: true
                        implicitHeight: contentHeight
                        model: calendarCombo.popup.visible ? calendarCombo.delegateModel : null
                        currentIndex: calendarCombo.highlightedIndex
                        boundsBehavior: Flickable.StopAtBounds
                        Controls.ScrollIndicator.vertical: Controls.ScrollIndicator {}
                    }
                    background: Rectangle {
                        radius: Theme.radius
                        color: Theme.background
                        border.width: 1
                        border.color: Theme.border
                    }
                }
                background: Rectangle {
                    radius: Theme.radius
                    color: Theme.background
                    border.width: 1
                    border.color: root.errorField === "calendarId" ? Theme.currentTime : Theme.border
                }
            }

            Item {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 4
            }

            FieldLabel {
                text: "ALL-DAY"
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 25
                Rectangle {
                    id: allDayToggle

                    anchors.left: parent.left
                    anchors.leftMargin: 1
                    anchors.verticalCenter: parent.verticalCenter
                    width: 42
                    height: 22
                    radius: 11
                    color: root.allDay ? Theme.accent : Theme.border

                    Rectangle {
                        width: 18
                        height: 18
                        radius: 9
                        y: 2
                        x: root.allDay ? parent.width - width - 2 : 2
                        color: Theme.text

                        Behavior on x {
                            NumberAnimation {
                                duration: 120
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.allDay = !root.allDay
                    }
                }
            }

            Item {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 4
            }

            FieldLabel {
                text: "START"
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                InlineWheelField {
                    id: startDateField
                    Layout.alignment: Qt.AlignVCenter
                    Layout.fillWidth: true
                    Layout.preferredWidth: root.allDay ? 100 : 75
                    label: "YEAR"
                    model: root.yearValues
                    currentIndex: Math.max(0, Math.min(root.yearValues.length - 1, root.datePart("start", "year") - (root.pickerCenterYear - 100)))
                    displayText: String(root.datePart("start", "year"))
                    expanded: root.expandedField === "startYear"
                    invalid: root.errorField === "start"
                    onExpansionRequested: root.toggleWheel("startYear")
                    onCollapseRequested: root.expandedField = ""
                    onSelectionRequested: (index, value) => root.setDatePart("start", "year", value)
                }

                InlineWheelField {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.fillWidth: true
                    Layout.preferredWidth: root.allDay ? 140 : 106
                    label: "MONTH"
                    model: root.monthValues
                    currentIndex: root.datePart("start", "month")
                    displayText: root.monthValues[root.datePart("start", "month")]
                    expanded: root.expandedField === "startMonth"
                    invalid: root.errorField === "start"
                    onExpansionRequested: root.toggleWheel("startMonth")
                    onCollapseRequested: root.expandedField = ""
                    onSelectionRequested: (index, value) => root.setDatePart("start", "month", index)
                }

                InlineWheelField {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.fillWidth: true
                    Layout.preferredWidth: root.allDay ? 100 : 54
                    label: "DAY"
                    model: root.dayValues("start")
                    currentIndex: root.datePart("start", "day") - 1
                    displayText: String(root.datePart("start", "day")).padStart(2, "0")
                    expanded: root.expandedField === "startDay"
                    invalid: root.errorField === "start"
                    padNumbers: true
                    trimModelEnds: true
                    onExpansionRequested: root.toggleWheel("startDay")
                    onCollapseRequested: root.expandedField = ""
                    onSelectionRequested: (index, value) => root.setDatePart("start", "day", value)
                }

                InlineWheelField {
                    id: startHourField

                    visible: !root.allDay
                    Layout.alignment: Qt.AlignVCenter
                    Layout.fillWidth: true
                    Layout.preferredWidth: 85
                    label: "HOUR"
                    model: root.hourValues
                    currentIndex: root.timePartIndex("start", "hour")
                    displayText: root.timePartText("start", "hour")
                    editable: true
                    text: root.timePartText("start", "hour")
                    expanded: root.expandedField === "startHour"
                    invalid: root.errorField === "start"
                    padNumbers: true
                    onExpansionRequested: root.toggleWheel("startHour")
                    onCollapseRequested: root.expandedField = ""
                    onSelectionRequested: (index, value) => root.setTimePart("start", "hour", value)
                    onTextEdited: text => root.setTimePartText("start", "hour", text)
                }

                InlineWheelField {
                    visible: !root.allDay
                    Layout.alignment: Qt.AlignVCenter
                    Layout.fillWidth: true
                    Layout.preferredWidth: 84
                    label: "MIN"
                    model: root.minuteValues
                    currentIndex: root.timePartIndex("start", "minute")
                    displayText: root.timePartText("start", "minute")
                    editable: true
                    text: root.timePartText("start", "minute")
                    expanded: root.expandedField === "startMinute"
                    invalid: root.errorField === "start"
                    padNumbers: true
                    onExpansionRequested: root.toggleWheel("startMinute")
                    onCollapseRequested: root.expandedField = ""
                    onSelectionRequested: (index, value) => root.setTimePart("start", "minute", value)
                    onTextEdited: text => root.setTimePartText("start", "minute", text)
                }
            }

            FieldLabel {
                text: root.allDay ? "END (INCLUSIVE)" : "END"
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                InlineWheelField {
                    id: endDateField
                    Layout.alignment: Qt.AlignVCenter
                    Layout.fillWidth: true
                    Layout.preferredWidth: root.allDay ? 100 : 75
                    label: "YEAR"
                    model: root.yearValues
                    currentIndex: Math.max(0, Math.min(root.yearValues.length - 1, root.datePart("end", "year") - (root.pickerCenterYear - 100)))
                    displayText: String(root.datePart("end", "year"))
                    expanded: root.expandedField === "endYear"
                    invalid: root.errorField === "end"
                    onExpansionRequested: root.toggleWheel("endYear")
                    onCollapseRequested: root.expandedField = ""
                    onSelectionRequested: (index, value) => root.setDatePart("end", "year", value)
                }

                InlineWheelField {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.fillWidth: true
                    Layout.preferredWidth: root.allDay ? 140 : 106
                    label: "MONTH"
                    model: root.monthValues
                    currentIndex: root.datePart("end", "month")
                    displayText: root.monthValues[root.datePart("end", "month")]
                    expanded: root.expandedField === "endMonth"
                    invalid: root.errorField === "end"
                    onExpansionRequested: root.toggleWheel("endMonth")
                    onCollapseRequested: root.expandedField = ""
                    onSelectionRequested: (index, value) => root.setDatePart("end", "month", index)
                }

                InlineWheelField {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.fillWidth: true
                    Layout.preferredWidth: root.allDay ? 100 : 54
                    label: "DAY"
                    model: root.dayValues("end")
                    currentIndex: root.datePart("end", "day") - 1
                    displayText: String(root.datePart("end", "day")).padStart(2, "0")
                    expanded: root.expandedField === "endDay"
                    invalid: root.errorField === "end"
                    padNumbers: true
                    trimModelEnds: true
                    onExpansionRequested: root.toggleWheel("endDay")
                    onCollapseRequested: root.expandedField = ""
                    onSelectionRequested: (index, value) => root.setDatePart("end", "day", value)
                }

                InlineWheelField {
                    id: endHourField

                    visible: !root.allDay
                    Layout.alignment: Qt.AlignVCenter
                    Layout.fillWidth: true
                    Layout.preferredWidth: 85
                    label: "HOUR"
                    model: root.hourValues
                    currentIndex: root.timePartIndex("end", "hour")
                    displayText: root.timePartText("end", "hour")
                    editable: true
                    text: root.timePartText("end", "hour")
                    expanded: root.expandedField === "endHour"
                    invalid: root.errorField === "end"
                    padNumbers: true
                    onExpansionRequested: root.toggleWheel("endHour")
                    onCollapseRequested: root.expandedField = ""
                    onSelectionRequested: (index, value) => root.setTimePart("end", "hour", value)
                    onTextEdited: text => root.setTimePartText("end", "hour", text)
                }

                InlineWheelField {
                    visible: !root.allDay
                    Layout.alignment: Qt.AlignVCenter
                    Layout.fillWidth: true
                    Layout.preferredWidth: 84
                    label: "MIN"
                    model: root.minuteValues
                    currentIndex: root.timePartIndex("end", "minute")
                    displayText: root.timePartText("end", "minute")
                    editable: true
                    text: root.timePartText("end", "minute")
                    expanded: root.expandedField === "endMinute"
                    invalid: root.errorField === "end"
                    padNumbers: true
                    onExpansionRequested: root.toggleWheel("endMinute")
                    onCollapseRequested: root.expandedField = ""
                    onSelectionRequested: (index, value) => root.setTimePart("end", "minute", value)
                    onTextEdited: text => root.setTimePartText("end", "minute", text)
                }
            }

            Item {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 4
            }
            FieldLabel {
                text: "REMINDERS"
            }

            Repeater {
                model: root.reminderDrafts

                delegate: RowLayout {
                    id: reminderType
                    required property int index
                    required property var modelData

                    Layout.fillWidth: true
                    Layout.preferredHeight: 30
                    spacing: 6

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 30
                        radius: Theme.radius
                        color: Theme.background
                        border.width: 1
                        border.color: Theme.border

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: CalendarMath.reminderLabel(reminderType.modelData.minutesBefore)
                            color: Theme.text
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 66
                        Layout.preferredHeight: 30
                        radius: Theme.radius
                        color: removeReminderHover.hovered ? Theme.surfaceRaised : Theme.background
                        border.width: 1
                        border.color: Theme.border

                        Text {
                            anchors.centerIn: parent
                            text: "Remove"
                            color: Theme.textMuted
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }

                        HoverHandler {
                            id: removeReminderHover
                            cursorShape: Qt.PointingHandCursor
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.removeReminder(reminderType.index)
                        }
                    }
                }
            }

            Controls.ComboBox {
                id: reminderPreset

                Layout.fillWidth: true
                Layout.preferredHeight: 34
                model: root.reminderPresets
                textRole: "label"
                currentIndex: 0
                leftPadding: 5
                rightPadding: 30
                font.pixelSize: 12
                palette.text: Theme.text
                palette.buttonText: Theme.text
                palette.windowText: Theme.text
                palette.base: Theme.background
                palette.window: Theme.surfaceRaised
                palette.highlight: Theme.accent
                onActivated: index => root.selectReminderPreset(index)
                contentItem: Text {
                    leftPadding: reminderPreset.leftPadding
                    rightPadding: reminderPreset.rightPadding
                    text: reminderPreset.displayText
                    color: Theme.text
                    font: reminderPreset.font
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }
                indicator: Text {
                    x: reminderPreset.width - width - 12
                    y: Math.round((reminderPreset.height - height) / 2)
                    text: ""
                    color: Theme.textMuted
                    font.family: Theme.font
                    font.pixelSize: 17
                    font.weight: Font.DemiBold
                }
                delegate: Controls.ItemDelegate {
                    id: reminderOption

                    required property int index

                    width: reminderPreset.width - 8
                    height: 34
                    highlighted: reminderPreset.highlightedIndex === index
                    contentItem: Text {
                        leftPadding: 8
                        text: reminderPreset.textAt(reminderOption.index)
                        color: Theme.text
                        font: reminderPreset.font
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                    background: Rectangle {
                        radius: Math.max(0, Theme.radius - 2)
                        color: reminderOption.highlighted || reminderOption.index === reminderPreset.currentIndex ? Theme.surfaceRaised : "transparent"
                    }
                }
                popup: Controls.Popup {
                    y: reminderPreset.height + 4
                    width: reminderPreset.width
                    implicitHeight: Math.min(contentItem.implicitHeight + 8, 180)
                    padding: 4
                    clip: true
                    contentItem: ListView {
                        clip: true
                        implicitHeight: contentHeight
                        model: reminderPreset.popup.visible ? reminderPreset.delegateModel : null
                        currentIndex: reminderPreset.highlightedIndex
                        boundsBehavior: Flickable.StopAtBounds
                        Controls.ScrollIndicator.vertical: Controls.ScrollIndicator {}
                    }
                    background: Rectangle {
                        radius: Theme.radius
                        color: Theme.background
                        border.width: 1
                        border.color: Theme.border
                    }
                }
                background: Rectangle {
                    radius: Theme.radius
                    color: Theme.background
                    border.width: 1
                    border.color: root.errorField === "reminders" ? Theme.currentTime : Theme.border
                }
            }

            RowLayout {
                visible: root.customReminderVisible
                Layout.fillWidth: true
                Layout.preferredHeight: visible ? 34 : 0
                spacing: 6

                Controls.TextField {
                    id: customReminderField

                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    text: root.customReminderText
                    placeholderText: "Minutes before"
                    color: Theme.text
                    placeholderTextColor: Theme.textMuted
                    selectionColor: Theme.accent
                    selectedTextColor: Theme.background
                    font.pixelSize: 12
                    leftPadding: 10
                    rightPadding: 10
                    inputMethodHints: Qt.ImhDigitsOnly
                    validator: RegularExpressionValidator {
                        regularExpression: /^\d*$/
                    }
                    Keys.onEscapePressed: event => root.releaseEditorFocus(event)
                    Keys.onReturnPressed: root.addCustomReminder()
                    onTextEdited: root.customReminderText = text
                    background: Rectangle {
                        radius: Theme.radius
                        color: Theme.background
                        border.width: 1
                        border.color: root.errorField === "reminders" ? Theme.currentTime : Theme.border
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 62
                    Layout.preferredHeight: 34
                    radius: Theme.radius
                    color: Theme.accent

                    Text {
                        anchors.centerIn: parent
                        text: "Add"
                        color: Theme.background
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.addCustomReminder()
                    }
                }
            }

            Text {
                visible: root.errorField === "reminders"
                Layout.fillWidth: true
                Layout.leftMargin: 5
                text: root.errorMessage
                color: Theme.currentTime
                font.pixelSize: 11
                wrapMode: Text.Wrap
            }

            Item {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 4
            }
            FieldLabel {
                text: "LOCATION"
            }
            FormField {
                text: root.locationText
                placeholderText: "Optional"
                onTextEdited: root.locationText = text
            }

            Item {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 4
            }
            FieldLabel {
                text: "DESCRIPTION"
            }
            Controls.TextArea {
                Layout.fillWidth: true
                Layout.preferredHeight: 110
                text: root.descriptionText
                color: Theme.text
                placeholderText: "Optional"
                placeholderTextColor: Theme.textMuted
                selectionColor: Theme.accent
                selectedTextColor: Theme.background
                wrapMode: TextEdit.Wrap
                padding: 10
                leftPadding: 9
                Keys.onEscapePressed: event => root.releaseEditorFocus(event)
                onTextChanged: root.descriptionText = text
                background: Rectangle {
                    radius: Theme.radius
                    color: Theme.background
                    border.width: 1
                    border.color: Theme.border
                }
            }

            Text {
                visible: root.errorMessage.length > 0 && root.errorField !== "reminders"
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                topPadding: 9
                bottomPadding: 9
                text: root.errorMessage
                color: Theme.currentTime
                font.pixelSize: 12
                wrapMode: Text.Wrap
            }
        }
    }

    Item {
        id: footer

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 50

        ActionButton {
            anchors.left: parent.left
            anchors.leftMargin: 17
            label: root.mode === "edit" ? "Save" : "Create"
            primary: true
            onClicked: root.save()
        }

        ActionButton {
            anchors.right: parent.right
            anchors.rightMargin: 17
            label: "Cancel"
            onClicked: root.cancelRequested()
        }
    }
}
