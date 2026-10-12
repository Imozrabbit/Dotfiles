pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import "../common/CalendarMath.js" as CalendarMath
import "../common/Theme.js" as Theme
import "../common/Recurrence.js" as Recurrence

Rectangle {
    id: root

    required property var calendarService
    required property string mode
    required property var eventData
    required property var defaults

    property string titleText: ""
    property string calendarId: ""
    property bool allDay: false
    property string timingMode: "Timed"
    property string startDateText: ""
    property string endDateText: ""
    property string startTimeText: "09:00"
    property string endTimeText: "10:00"
    property string locationText: ""
    property string descriptionText: ""
    property string errorField: ""
    property string errorMessage: ""
    property string expandedField: ""
    property string repeatFrequency: "Never"
    readonly property bool repeatUsesTimeOnly: root.repeatFrequency !== "Never"
    readonly property bool repeatDraftValid: root.validateRepeatDraft()
    property string repeatIntervalText: "1"
    property string repeatEnd: "Never"
    property string repeatStartDateText: ""
    property string repeatUntilDateText: ""
    property string repeatCountText: "1"
    readonly property bool repeatUntilBeforeStart: {
        if (!root.repeatUsesTimeOnly || root.repeatEnd !== "Until date")
            return false;
        const start = root.parseDate(root.repeatStartDateText);
        const end = root.parseDate(root.repeatUntilDateText);
        if (!start || !end)
            return false;
        if (root.repeatFrequency === "Monthly")
            start.setDate(1);
        else if (root.repeatFrequency === "Yearly")
            start.setMonth(0, 1);
        return end.getTime() < start.getTime();
    }
    property var repeatWeekdays: []
    property var repeatMonthDays: []
    property string repeatMonthPattern: "Month dates"
    property var repeatMonthPositions: []
    property int repeatMonthPosition: 1
    property int repeatMonthWeekday: 0
    readonly property var monthPositionLabels: ["First", "Second", "Third", "Fourth", "Fifth", "Last"]
    readonly property var weekdayLabels: ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    property var repeatYearDates: []
    property int repeatYearMonth: 0
    property int repeatYearDay: 1
    property var reminderDrafts: []
    property bool customReminderVisible: false
    property string customReminderText: ""
    property bool savePending: false
    property bool saveCommitted: false
    property string savedTimezone: ""
    property string loadedTiming: ""
    readonly property int formSpacing: 5
    readonly property int sectionSpacing: 4
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
    readonly property var writableCalendars: {
        const candidates = calendarService.calendars.filter(calendar => calendar.writable === true);
        const sourceCalendar = root.mode === "edit" && root.eventData ? calendarService.calendarById(root.eventData.calendarId) : null;
        if (!sourceCalendar)
            return candidates;
        return sourceCalendar.type === "local" ? candidates.filter(calendar => calendar.type === "local") : candidates.filter(calendar => calendar.id === sourceCalendar.id);
    }

    signal saved(var eventData)
    signal cancelRequested

    Connections {
        target: root.calendarService
        function onEventMutationFinished(result) {
            if (!root.savePending)
                return;
            root.savePending = false;
            if (result.cacheWarning) {
                root.saveCommitted = true;
                root.errorField = "storage";
                root.errorMessage = result.message;
                return;
            }
            if (!result.ok) {
                root.setError(result.field, result.message, null);
                return;
            }
            root.saved(result.event);
        }
    }

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

    component RepeatDateRow: RowLayout {
        id: dateRow

        required property string target
        property bool showMonth: true
        property bool showDay: true
        property bool invalid: false
        property alias yearControl: yearPicker

        Layout.fillWidth: true
        spacing: 4

        InlineWheelField {
            id: yearPicker

            Layout.fillWidth: true
            Layout.preferredWidth: 100
            label: "YEAR"
            model: root.yearValues
            currentIndex: Math.max(0, Math.min(root.yearValues.length - 1, root.datePart(dateRow.target, "year") - (root.pickerCenterYear - 100)))
            displayText: String(root.datePart(dateRow.target, "year"))
            expanded: root.expandedField === dateRow.target + "Year"
            invalid: dateRow.invalid
            onExpansionRequested: root.toggleWheel(dateRow.target + "Year")
            onCollapseRequested: root.expandedField = ""
            onSelectionRequested: (index, value) => root.setDatePart(dateRow.target, "year", value)
        }
        InlineWheelField {
            visible: dateRow.showMonth
            Layout.fillWidth: true
            Layout.preferredWidth: 140
            label: "MONTH"
            model: root.monthValues
            currentIndex: root.datePart(dateRow.target, "month")
            displayText: root.monthValues[root.datePart(dateRow.target, "month")]
            expanded: root.expandedField === dateRow.target + "Month"
            invalid: dateRow.invalid
            onExpansionRequested: root.toggleWheel(dateRow.target + "Month")
            onCollapseRequested: root.expandedField = ""
            onSelectionRequested: (index, value) => root.setDatePart(dateRow.target, "month", index)
        }
        InlineWheelField {
            visible: dateRow.showDay
            Layout.fillWidth: true
            Layout.preferredWidth: 100
            label: "DAY"
            model: root.dayValues(dateRow.target)
            currentIndex: root.datePart(dateRow.target, "day") - 1
            displayText: String(root.datePart(dateRow.target, "day")).padStart(2, "0")
            expanded: root.expandedField === dateRow.target + "Day"
            invalid: dateRow.invalid
            padNumbers: true
            onExpansionRequested: root.toggleWheel(dateRow.target + "Day")
            onCollapseRequested: root.expandedField = ""
            onSelectionRequested: (index, value) => root.setDatePart(dateRow.target, "day", value)
        }
    }

    component ErrorText: Text {
        Layout.fillWidth: true
        Layout.leftMargin: 5
        Layout.rightMargin: 5
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        color: Theme.currentTime
        font.pixelSize: 11
        wrapMode: Text.WordWrap
    }

    component DayToggle: Controls.Button {
        id: dayToggle

        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.preferredHeight: 34
        checkable: true
        HoverHandler {
            enabled: dayToggle.enabled
            cursorShape: Qt.PointingHandCursor
        }
        contentItem: Text {
            text: dayToggle.text
            color: dayToggle.checked ? Theme.background : Theme.text
            font.pixelSize: 11
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: Theme.radius
            color: dayToggle.down ? Qt.darker(dayToggle.checked ? Theme.accent : Theme.surfaceRaised, 1.2)
                : dayToggle.checked ? Theme.accent : dayToggle.hovered ? Theme.surfaceRaised : Theme.background
            border.width: dayToggle.checked ? 0 : 1
            border.color: Theme.border
        }
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
        if (date.getFullYear() !== year || date.getMonth() !== month || date.getDate() !== day || date.getHours() !== Number(match[1]) || date.getMinutes() !== Number(match[2]))
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
        if (target === "repeatStart")
            return root.repeatStartDateText;
        if (target === "repeatUntil")
            return root.repeatUntilDateText;
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
        else if (target === "repeatStart")
            root.repeatStartDateText = text;
        else if (target === "repeatUntil")
            root.repeatUntilDateText = text;
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

    function toggleRepeatWeekday(day) {
        if (!Number.isInteger(day) || day < 0 || day > 6)
            return;
        root.repeatWeekdays = root.repeatWeekdays.includes(day) ? root.repeatWeekdays.filter(value => value !== day) : root.repeatWeekdays.concat([day]).sort((left, right) => left - right);
    }

    function toggleRepeatMonthDay(day) {
        if (!Number.isInteger(day) || day < 1 || day > 31)
            return;
        root.repeatMonthDays = root.repeatMonthDays.includes(day) ? root.repeatMonthDays.filter(value => value !== day) : root.repeatMonthDays.concat([day]).sort((left, right) => left - right);
    }

    function addRepeatYearDate() {
        const month = root.repeatYearMonth + 1;
        const day = root.repeatYearDay;
        if (!Number.isInteger(month) || month < 1 || month > 12 || !Number.isInteger(day) || day < 1 || day > CalendarMath.daysInMonth(2000, month - 1))
            return;
        if (root.repeatYearDates.some(value => value.month === month && value.day === day))
            return;
        root.repeatYearDates = root.repeatYearDates.concat([{ month, day }]).sort((left, right) => left.month - right.month || left.day - right.day);
    }

    function addRepeatMonthPosition() {
        const position = root.repeatMonthPosition;
        const weekday = root.repeatMonthWeekday;
        if (!Number.isInteger(position) || (position !== -1 && (position < 1 || position > 5)) || !Number.isInteger(weekday) || weekday < 0 || weekday > 6)
            return;
        if (root.repeatMonthPositions.some(value => value.position === position && value.weekday === weekday))
            return;
        root.repeatMonthPositions = root.repeatMonthPositions.concat([{ position, weekday }]);
    }

    function removeRepeatMonthPosition(index) {
        root.repeatMonthPositions = root.repeatMonthPositions.filter((value, position) => position !== index);
    }

    function removeRepeatYearDate(index) {
        root.repeatYearDates = root.repeatYearDates.filter((value, position) => position !== index);
    }

    function updateTimingMode() {
        if (root.allDay) {
            root.timingMode = "All-day";
            return;
        }
        const start = root.parseDate(root.startDateText);
        const end = root.parseDate(root.endDateText);
        if (start)
            start.setDate(start.getDate() + 1);
        root.timingMode = start && end && start.getTime() === end.getTime() ? "Overnight" : "Timed";
    }

    function selectTimingMode(value) {
        const previous = root.timingMode;
        root.allDay = value === "All-day";
        if (!root.repeatUsesTimeOnly && (value === "Overnight" || (value === "Timed" && previous === "Overnight"))) {
            const end = root.parseDate(root.startDateText);
            if (end) {
                if (value === "Overnight")
                    end.setDate(end.getDate() + 1);
                root.endDateText = root.dateText(end);
            }
        }
        root.timingMode = value;
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
        root.savedTimezone = editing ? source.timezone || "" : "";
        root.calendarId = editing ? source.calendarId : root.writableCalendars.length > 0 ? root.writableCalendars[0].id : "";

        const start = new Date(source.startMs);
        const end = new Date(source.endMs);
        root.repeatWeekdays = [(start.getDay() + 6) % 7];
        root.repeatMonthDays = [start.getDate()];
        root.repeatMonthPosition = Math.floor((start.getDate() - 1) / 7) + 1;
        root.repeatMonthWeekday = (start.getDay() + 6) % 7;
        root.repeatMonthPositions = [{ position: root.repeatMonthPosition, weekday: root.repeatMonthWeekday }];
        root.repeatYearMonth = start.getMonth();
        root.repeatYearDay = start.getDate();
        root.repeatYearDates = [{ month: start.getMonth() + 1, day: start.getDate() }];
        root.startDateText = root.dateText(start);
        root.repeatStartDateText = root.startDateText;
        root.repeatUntilDateText = root.startDateText;
        root.startTimeText = root.timeText(start);
        if (root.allDay)
            end.setDate(end.getDate() - 1);
        root.endDateText = root.dateText(end);
        root.endTimeText = root.timeText(end);
        root.updateTimingMode();
        root.repeatFrequency = "Never";
        if (editing && source.recurrence)
            root.loadRepeatRule(source.recurrence);
        root.loadedTiming = root.timingSignature();
    }

    function timingSignature() {
        return JSON.stringify([root.allDay, root.timingMode, root.startDateText, root.endDateText, root.startTimeText, root.endTimeText]);
    }

    function loadRepeatRule(rule) {
        root.repeatFrequency = rule.frequency[0].toUpperCase() + rule.frequency.slice(1);
        root.repeatIntervalText = String(rule.interval);
        root.repeatStartDateText = rule.startsOn;
        root.repeatEnd = rule.ends.mode === "count" ? "After N occurrences" : rule.ends.mode === "date" ? "Until date" : "Never";
        if (rule.ends.mode === "date")
            root.repeatUntilDateText = rule.ends.date;
        if (rule.ends.mode === "count")
            root.repeatCountText = String(rule.ends.count);
        if (rule.frequency === "weekly")
            root.repeatWeekdays = rule.pattern.weekdays.slice();
        if (rule.frequency === "monthly") {
            root.repeatMonthPattern = rule.pattern.mode === "dates" ? "Month dates" : "Weekday positions";
            if (rule.pattern.mode === "dates")
                root.repeatMonthDays = rule.pattern.days.slice();
            else
                root.repeatMonthPositions = rule.pattern.positions.map(item => ({ position: item.ordinal, weekday: item.weekday }));
        }
        if (rule.frequency === "yearly")
            root.repeatYearDates = rule.pattern.dates.map(item => ({ month: item.month, day: item.day }));
    }

    function recurrenceDraft() {
        const frequency = root.repeatFrequency.toLowerCase();
        let pattern = {};
        if (frequency === "weekly")
            pattern = { weekdays: root.repeatWeekdays.slice() };
        else if (frequency === "monthly")
            pattern = root.repeatMonthPattern === "Month dates" ? { mode: "dates", days: root.repeatMonthDays.slice() }
                : { mode: "positions", positions: root.repeatMonthPositions.map(item => ({ ordinal: item.position, weekday: item.weekday })) };
        else if (frequency === "yearly")
            pattern = { dates: root.repeatYearDates.map(item => ({ month: item.month, day: item.day })) };
        const ends = root.repeatEnd === "Until date" ? { mode: "date", date: root.repeatUntilDateText }
            : root.repeatEnd === "After N occurrences" ? { mode: "count", count: Number(root.repeatCountText) } : { mode: "never" };
        const result = Recurrence.canonicalRule({ frequency, interval: Number(root.repeatIntervalText),
            startsOn: root.repeatStartDateText, pattern, ends });
        return result.ok ? result.rule : null;
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

    function validRepeatNumber(text) {
        return /^\d+$/.test(text) && Number(text) > 0 && Number(text) <= 2147483647;
    }

    function validateRepeatDraft() {
        if (!root.repeatUsesTimeOnly)
            return true;
        if (!root.parseDate(root.repeatStartDateText) || !root.validRepeatNumber(root.repeatIntervalText))
            return false;
        if (root.repeatEnd === "Until date" && (!root.parseDate(root.repeatUntilDateText) || root.repeatUntilBeforeStart))
            return false;
        if (root.repeatEnd === "After N occurrences" && !root.validRepeatNumber(root.repeatCountText))
            return false;
        if (root.repeatFrequency === "Weekly")
            return root.repeatWeekdays.length > 0;
        if (root.repeatFrequency === "Monthly")
            return root.repeatMonthPattern === "Month dates" ? root.repeatMonthDays.length > 0 : root.repeatMonthPositions.length > 0;
        if (root.repeatFrequency === "Yearly")
            return root.repeatYearDates.length > 0;
        return true;
    }

    function save() {
        if (root.savePending || root.saveCommitted)
            return;
        if (root.repeatUntilBeforeStart) {
            root.setError("repeatUntil", "Repeat end cannot be earlier than repeat start.", repeatUntilDateRow.yearControl);
            return;
        }
        if (!root.repeatDraftValid)
            return;
        root.errorField = "";
        root.errorMessage = "";
        const startDate = root.parseDate(root.startDateText);
        if (!startDate) {
            root.setError("start", "Enter start date as YYYY-MM-DD", startDateField);
            return;
        }
        const endDate = root.parseDate(root.repeatUsesTimeOnly ? root.startDateText : root.endDateText);
        if (!endDate) {
            root.setError("end", "Enter end date as YYYY-MM-DD", endDateField);
            return;
        }

        let start;
        let end;
        if (root.repeatUsesTimeOnly && root.timingMode === "Overnight")
            endDate.setDate(endDate.getDate() + 1);
        if (root.allDay) {
            endDate.setDate(endDate.getDate() + 1);
            start = root.dateText(startDate);
            end = root.dateText(endDate);
        } else {
            const startValue = root.parseDateTime(root.startDateText, root.startTimeText);
            const endValue = root.parseDateTime(root.dateText(endDate), root.endTimeText);
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
            if (root.mode === "edit" && root.eventData.recurrence && root.timingSignature() === root.loadedTiming) {
                start = new Date(root.eventData.startMs).toISOString();
                end = new Date(root.eventData.endMs).toISOString();
            }
        }

        const data = {
            calendarId: root.calendarId,
            title: root.titleText,
            description: root.descriptionText,
            location: root.locationText,
            allDay: root.allDay,
            start,
            end,
            revision: root.mode === "edit" ? root.eventData.revision : undefined,
            reminders: root.reminderDrafts.map(reminder => ({
                        minutesBefore: reminder.minutesBefore
                    }))
        };
        data.recurrence = root.repeatUsesTimeOnly ? root.recurrenceDraft() : null;
        if (root.repeatUsesTimeOnly && !data.recurrence)
            return;
        if (!root.allDay)
            data.timezone = root.savedTimezone || root.calendarService.systemTimezone || undefined;
        const result = root.mode === "edit" ? root.calendarService.updateEvent(root.eventData.uid, data) : root.calendarService.createEvent(data);
        if (!result.ok) {
            root.setError(result.field, result.message, null);
            return;
        }
        if (result.pending) {
            root.savePending = true;
            return;
        }
        root.saved(result.event);
    }

    Component.onCompleted: {
        root.loadDraft();
        root.forceActiveFocus();
    }
    onAllDayChanged: {
        if (root.allDay)
            root.timingMode = "All-day";
        if (root.allDay && (root.expandedField.endsWith("Hour") || root.expandedField.endsWith("Minute")))
            root.expandedField = "";
    }
    onStartDateTextChanged: {
        if (!root.repeatUsesTimeOnly)
            root.updateTimingMode();
    }
    onEndDateTextChanged: {
        if (!root.repeatUsesTimeOnly)
            root.updateTimingMode();
    }
    onRepeatFrequencyChanged: {
        if (!root.repeatUsesTimeOnly)
            root.updateTimingMode();
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
            spacing: root.formSpacing

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
                Layout.preferredHeight: root.sectionSpacing
            }
            FieldLabel {
                text: "CALENDAR"
            }
            Controls.ComboBox {
                id: calendarCombo

                HoverHandler {
                    enabled: calendarCombo.enabled
                    cursorShape: Qt.PointingHandCursor
                }

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
                    textFormat: Text.PlainText
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
                    hoverEnabled: false
                    contentItem: Text {
                        leftPadding: 8
                        text: calendarCombo.textAt(calendarOption.index)
                        textFormat: Text.PlainText
                        color: Theme.text
                        font: calendarCombo.font
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                    background: Rectangle {
                        property bool hovered: calendarOptionHover.hovered
                        radius: Math.max(0, Theme.radius - 2)
                        color: calendarOption.down ? Qt.darker(Theme.surfaceRaised, 1.2)
                            : hovered || calendarOption.highlighted || calendarOption.index === calendarCombo.currentIndex ? Theme.surfaceRaised : "transparent"
                    }
                    HoverHandler {
                        id: calendarOptionHover
                        enabled: calendarOption.enabled
                        cursorShape: Qt.PointingHandCursor
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
                    color: calendarCombo.pressed ? Qt.darker(Theme.surfaceRaised, 1.2) : Theme.background
                    border.width: 1
                    border.color: root.errorField === "calendarId" ? Theme.currentTime : Theme.border
                }
            }

            Item {
                Layout.preferredWidth: 1
                Layout.preferredHeight: root.sectionSpacing
            }

            FieldLabel {
                text: "REPEAT"
            }
            InlineWheelField {
                id: repeatPicker

                Layout.fillWidth: true
                label: ""
                chevronText: ""
                chevronPixelSize: 17
                model: ["Never", "Daily", "Weekly", "Monthly", "Yearly"]
                currentIndex: model.indexOf(root.repeatFrequency)
                displayText: root.repeatFrequency
                expanded: root.expandedField === "repeat"
                onExpansionRequested: root.toggleWheel("repeat")
                onCollapseRequested: root.expandedField = ""
                onSelectionRequested: (index, value) => root.repeatFrequency = value
            }
            Item {
                Layout.preferredWidth: 1
                Layout.preferredHeight: root.sectionSpacing
            }
            FieldLabel {
                text: "TIMING"
            }
            RowLayout {
                id: timingSelector

                Layout.fillWidth: true
                spacing: 4

                Repeater {
                    model: ["Timed", "All-day", "Overnight"]

                    delegate: DayToggle {
                        required property string modelData

                        text: modelData
                        autoExclusive: true
                        checked: root.timingMode === modelData
                        onClicked: root.selectTimingMode(modelData)
                    }
                }
            }

            ColumnLayout {
                id: repeatStartSection

                visible: root.repeatUsesTimeOnly
                Layout.fillWidth: true
                Layout.topMargin: root.sectionSpacing
                spacing: root.formSpacing

                FieldLabel {
                    text: "REPEAT STARTS"
                }
                RepeatDateRow {
                    target: "repeatStart"
                    showMonth: root.repeatFrequency !== "Yearly"
                    showDay: root.repeatFrequency !== "Monthly" && root.repeatFrequency !== "Yearly"
                }
            }

            Item {
                visible: !root.repeatUsesTimeOnly || !root.allDay
                Layout.preferredWidth: 1
                Layout.preferredHeight: root.sectionSpacing
            }

            FieldLabel {
                visible: !root.repeatUsesTimeOnly || !root.allDay
                text: "START"
            }
            RowLayout {
                visible: !root.repeatUsesTimeOnly || !root.allDay
                Layout.fillWidth: true
                spacing: 4

                InlineWheelField {
                    id: startDateField
                    visible: !root.repeatUsesTimeOnly
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
                    visible: !root.repeatUsesTimeOnly
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
                    visible: !root.repeatUsesTimeOnly
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

            Item {
                visible: !root.repeatUsesTimeOnly || !root.allDay
                Layout.preferredWidth: 1
                Layout.preferredHeight: root.sectionSpacing
            }

            FieldLabel {
                visible: !root.repeatUsesTimeOnly || !root.allDay
                text: root.allDay ? "END (INCLUSIVE)" : "END"
            }
            RowLayout {
                visible: !root.repeatUsesTimeOnly || !root.allDay
                Layout.fillWidth: true
                spacing: 4

                InlineWheelField {
                    id: endDateField
                    visible: !root.repeatUsesTimeOnly
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
                    visible: !root.repeatUsesTimeOnly
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
                    visible: !root.repeatUsesTimeOnly
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
                Layout.preferredHeight: root.sectionSpacing
            }
            RowLayout {
                visible: root.repeatFrequency !== "Never"
                Layout.fillWidth: true
                Layout.leftMargin: 5
                spacing: 8

                Text {
                    text: "Every"
                    color: Theme.text
                    font.pixelSize: 12
                }
                FormField {
                    id: repeatIntervalField

                    Layout.fillWidth: false
                    Layout.preferredWidth: 70
                    text: root.repeatIntervalText
                    horizontalAlignment: TextInput.AlignHCenter
                    inputMethodHints: Qt.ImhDigitsOnly
                    validator: IntValidator {
                        bottom: 1
                    }
                    invalid: !acceptableInput
                    onTextEdited: root.repeatIntervalText = text
                }
                Text {
                    Layout.fillWidth: true
                    text: ({
                            Daily: "day",
                            Weekly: "week",
                            Monthly: "month",
                            Yearly: "year"
                        })[root.repeatFrequency] + (Number(root.repeatIntervalText) === 1 ? "" : "s")
                    color: Theme.text
                    font.pixelSize: 12
                }
            }
            ErrorText {
                visible: root.repeatFrequency !== "Never" && !repeatIntervalField.acceptableInput
                text: "Enter a positive whole-number interval."
            }
            Item {
                visible: root.repeatFrequency === "Weekly"
                Layout.preferredHeight: root.sectionSpacing
            }
            ColumnLayout {
                visible: root.repeatFrequency === "Weekly"
                Layout.fillWidth: true
                spacing: root.formSpacing

                FieldLabel {
                    text: "ON DAYS"
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Repeater {
                        model: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

                        delegate: DayToggle {
                            required property int index
                            required property string modelData

                            text: modelData
                            checked: root.repeatWeekdays.includes(index)
                            onClicked: root.toggleRepeatWeekday(index)
                        }
                    }
                }
                ErrorText {
                    visible: root.repeatWeekdays.length === 0
                    text: "Choose at least one weekday."
                    wrapMode: Text.NoWrap
                }
            }
            Item {
                visible: root.repeatFrequency === "Monthly"
                Layout.preferredHeight: root.sectionSpacing
            }
            FieldLabel {
                visible: root.repeatFrequency === "Monthly"
                text: "REPEAT ON"
            }
            InlineWheelField {
                id: repeatMonthPatternPicker

                visible: root.repeatFrequency === "Monthly"
                Layout.fillWidth: true
                label: ""
                chevronText: ""
                chevronPixelSize: 17
                model: ["Month dates", "Weekday positions"]
                currentIndex: model.indexOf(root.repeatMonthPattern)
                displayText: root.repeatMonthPattern
                expanded: root.expandedField === "repeatMonthPattern"
                onExpansionRequested: root.toggleWheel("repeatMonthPattern")
                onCollapseRequested: root.expandedField = ""
                onSelectionRequested: (index, value) => root.repeatMonthPattern = value
            }
            Item {
                visible: root.repeatFrequency === "Monthly" && root.repeatMonthPattern === "Month dates"
                Layout.preferredHeight: root.sectionSpacing
            }
            ColumnLayout {
                id: monthlyRepeatDates

                visible: root.repeatFrequency === "Monthly" && root.repeatMonthPattern === "Month dates"
                Layout.fillWidth: true
                spacing: root.formSpacing

                FieldLabel {
                    text: "ON MONTH DATES"
                }
                GridLayout {
                    Layout.fillWidth: true
                    columns: 7
                    rowSpacing: 4
                    columnSpacing: 4

                    Repeater {
                        model: root.buildRange(1, 31)

                        delegate: DayToggle {
                            required property int modelData

                            text: String(modelData)
                            checked: root.repeatMonthDays.includes(modelData)
                            onClicked: root.toggleRepeatMonthDay(modelData)
                        }
                    }
                }
                ErrorText {
                    visible: root.repeatMonthDays.length === 0
                    text: "Choose at least one month date."
                }
            }
            Item {
                visible: root.repeatFrequency === "Monthly" && root.repeatMonthPattern === "Weekday positions"
                Layout.preferredHeight: root.sectionSpacing
            }
            ColumnLayout {
                id: monthlyRepeatPositions

                visible: root.repeatFrequency === "Monthly" && root.repeatMonthPattern === "Weekday positions"
                Layout.fillWidth: true
                spacing: root.formSpacing

                FieldLabel {
                    text: "ON WEEKDAY POSITIONS"
                }
                Repeater {
                    model: root.repeatMonthPositions

                    delegate: RowLayout {
                        id: monthPositionRow

                        required property int index
                        required property var modelData

                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            Layout.fillWidth: true
                            Layout.leftMargin: 5
                            text: root.monthPositionLabels[monthPositionRow.modelData.position === -1 ? 5 : monthPositionRow.modelData.position - 1] + " " + root.weekdayLabels[monthPositionRow.modelData.weekday]
                            color: Theme.text
                            font.pixelSize: 12
                        }
                        ActionButton {
                            label: "Remove"
                            onClicked: root.removeRepeatMonthPosition(monthPositionRow.index)
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    InlineWheelField {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 100
                        label: "POSITION"
                        model: root.monthPositionLabels
                        currentIndex: root.repeatMonthPosition === -1 ? 5 : root.repeatMonthPosition - 1
                        displayText: root.monthPositionLabels[currentIndex]
                        expanded: root.expandedField === "repeatMonthPosition"
                        onExpansionRequested: root.toggleWheel("repeatMonthPosition")
                        onCollapseRequested: root.expandedField = ""
                        onSelectionRequested: (index, value) => root.repeatMonthPosition = index === 5 ? -1 : index + 1
                    }
                    InlineWheelField {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 140
                        label: "WEEKDAY"
                        model: root.weekdayLabels
                        currentIndex: root.repeatMonthWeekday
                        displayText: root.weekdayLabels[root.repeatMonthWeekday]
                        expanded: root.expandedField === "repeatMonthWeekday"
                        onExpansionRequested: root.toggleWheel("repeatMonthWeekday")
                        onCollapseRequested: root.expandedField = ""
                        onSelectionRequested: (index, value) => root.repeatMonthWeekday = index
                    }
                    ActionButton {
                        Layout.alignment: Qt.AlignBottom
                        label: "Add"
                        enabled: !root.repeatMonthPositions.some(value => value.position === root.repeatMonthPosition && value.weekday === root.repeatMonthWeekday)
                        onClicked: root.addRepeatMonthPosition()
                    }
                }
                ErrorText {
                    visible: root.repeatMonthPositions.length === 0
                    text: "Choose at least one weekday position."
                }
            }
            Item {
                visible: root.repeatFrequency === "Yearly"
                Layout.preferredHeight: root.sectionSpacing
            }
            ColumnLayout {
                id: yearlyRepeatDates

                visible: root.repeatFrequency === "Yearly"
                Layout.fillWidth: true
                spacing: root.formSpacing

                FieldLabel {
                    text: "ON MONTH / DATE PAIRS"
                }
                Repeater {
                    model: root.repeatYearDates

                    delegate: RowLayout {
                        id: yearDateRow

                        required property int index
                        required property var modelData

                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            Layout.fillWidth: true
                            Layout.leftMargin: 5
                            text: root.monthValues[yearDateRow.modelData.month - 1] + " " + yearDateRow.modelData.day
                            color: Theme.text
                            font.pixelSize: 12
                        }
                        ActionButton {
                            label: "Remove"
                            onClicked: root.removeRepeatYearDate(yearDateRow.index)
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    InlineWheelField {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 140
                        label: "MONTH"
                        model: root.monthValues
                        currentIndex: root.repeatYearMonth
                        displayText: root.monthValues[root.repeatYearMonth]
                        expanded: root.expandedField === "repeatYearMonth"
                        onExpansionRequested: root.toggleWheel("repeatYearMonth")
                        onCollapseRequested: root.expandedField = ""
                        onSelectionRequested: (index, value) => {
                            root.repeatYearMonth = index;
                            root.repeatYearDay = Math.min(root.repeatYearDay, CalendarMath.daysInMonth(2000, index));
                        }
                    }
                    InlineWheelField {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 70
                        label: "DAY"
                        model: root.dayModels[CalendarMath.daysInMonth(2000, root.repeatYearMonth) - 28]
                        currentIndex: root.repeatYearDay - 1
                        displayText: String(root.repeatYearDay).padStart(2, "0")
                        expanded: root.expandedField === "repeatYearDay"
                        padNumbers: true
                        onExpansionRequested: root.toggleWheel("repeatYearDay")
                        onCollapseRequested: root.expandedField = ""
                        onSelectionRequested: (index, value) => root.repeatYearDay = value
                    }
                    ActionButton {
                        Layout.alignment: Qt.AlignBottom
                        label: "Add"
                        enabled: !root.repeatYearDates.some(value => value.month === root.repeatYearMonth + 1 && value.day === root.repeatYearDay)
                        onClicked: root.addRepeatYearDate()
                    }
                }
                ErrorText {
                    visible: root.repeatYearDates.length === 0
                    text: "Choose at least one month/date pair."
                }
            }
            Item {
                visible: root.repeatUsesTimeOnly
                Layout.preferredHeight: root.sectionSpacing
            }
            FieldLabel {
                visible: root.repeatUsesTimeOnly
                text: "REPEAT ENDS"
            }
            InlineWheelField {
                visible: root.repeatUsesTimeOnly
                Layout.fillWidth: true
                label: ""
                chevronText: ""
                chevronPixelSize: 17
                model: ["Never", "Until date", "After N occurrences"]
                currentIndex: model.indexOf(root.repeatEnd)
                displayText: root.repeatEnd
                expanded: root.expandedField === "repeatEnd"
                onExpansionRequested: root.toggleWheel("repeatEnd")
                onCollapseRequested: root.expandedField = ""
                onSelectionRequested: (index, value) => root.repeatEnd = value
            }
            RepeatDateRow {
                id: repeatUntilDateRow

                visible: root.repeatUsesTimeOnly && root.repeatEnd === "Until date"
                target: "repeatUntil"
                invalid: root.repeatUntilBeforeStart
            }
            ErrorText {
                visible: root.repeatUntilBeforeStart
                text: "Repeat end cannot be earlier than repeat start."
            }
            RowLayout {
                visible: root.repeatUsesTimeOnly && root.repeatEnd === "After N occurrences"
                Layout.fillWidth: true
                spacing: 8

                FormField {
                    id: repeatCountField

                    Layout.fillWidth: false
                    Layout.preferredWidth: 70
                    text: root.repeatCountText
                    horizontalAlignment: TextInput.AlignHCenter
                    inputMethodHints: Qt.ImhDigitsOnly
                    validator: IntValidator {
                        bottom: 1
                    }
                    invalid: !acceptableInput
                    onTextEdited: root.repeatCountText = text
                }
                Text {
                    text: Number(root.repeatCountText) === 1 ? "occurrence" : "occurrences"
                    color: Theme.text
                    font.pixelSize: 12
                }
            }

            ErrorText {
                visible: root.repeatUsesTimeOnly && root.repeatEnd === "After N occurrences" && !repeatCountField.acceptableInput
                text: "Enter a positive whole-number occurrence count."
            }

            Item {
                Layout.preferredWidth: 1
                Layout.preferredHeight: root.sectionSpacing
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
                        color: removeReminderMouse.pressed ? Qt.darker(Theme.surfaceRaised, 1.2) : removeReminderHover.hovered ? Theme.surfaceRaised : Theme.background
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
                            id: removeReminderMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: root.removeReminder(reminderType.index)
                        }
                    }
                }
            }

            Controls.ComboBox {
                id: reminderPreset

                HoverHandler {
                    enabled: reminderPreset.enabled
                    cursorShape: Qt.PointingHandCursor
                }

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
                    hoverEnabled: false
                    contentItem: Text {
                        leftPadding: 8
                        text: reminderPreset.textAt(reminderOption.index)
                        color: Theme.text
                        font: reminderPreset.font
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                    background: Rectangle {
                        property bool hovered: reminderOptionHover.hovered
                        radius: Math.max(0, Theme.radius - 2)
                        color: reminderOption.down ? Qt.darker(Theme.surfaceRaised, 1.2)
                            : hovered || reminderOption.highlighted || reminderOption.index === reminderPreset.currentIndex ? Theme.surfaceRaised : "transparent"
                    }
                    HoverHandler {
                        id: reminderOptionHover
                        enabled: reminderOption.enabled
                        cursorShape: Qt.PointingHandCursor
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
                    color: reminderPreset.pressed ? Qt.darker(Theme.surfaceRaised, 1.2) : Theme.background
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
                    color: addReminderMouse.pressed ? Qt.darker(Theme.accent, 1.2) : Theme.accent

                    Text {
                        anchors.centerIn: parent
                        text: "Add"
                        color: Theme.background
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: addReminderMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: root.addCustomReminder()
                    }
                }
            }

            ErrorText {
                visible: root.errorField === "reminders"
                text: root.errorMessage
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
            }

            Item {
                Layout.preferredWidth: 1
                Layout.preferredHeight: root.sectionSpacing
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
                Layout.preferredHeight: root.sectionSpacing
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

            ErrorText {
                visible: root.errorMessage.length > 0 && root.errorField !== "reminders" && root.errorField !== "repeatUntil"
                topPadding: 9
                bottomPadding: 9
                text: root.errorMessage
                textFormat: Text.PlainText
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
            label: root.savePending ? "Saving..." : (root.mode === "edit" ? "Save" : "Create")
            primary: true
            enabled: !root.savePending && !root.saveCommitted && root.repeatDraftValid
            onClicked: root.save()
        }

        ActionButton {
            anchors.right: parent.right
            anchors.rightMargin: 17
            label: "Cancel"
            enabled: !root.savePending
            onClicked: root.cancelRequested()
        }
    }
}
