const assert = require("node:assert/strict")
const CalendarMath = require("../common/CalendarMath.js")

{
    const result = CalendarMath.weekStart(new Date(2026, 8, 2, 15, 30))

    assert.equal(result.getFullYear(), 2026)
    assert.equal(result.getMonth(), 7)
    assert.equal(result.getDate(), 31)
    assert.equal(result.getDay(), 1)
    assert.equal(result.getHours(), 0)
}

assert.equal(CalendarMath.rangesOverlap(100, 200, 200, 300), false)
assert.equal(CalendarMath.rangesOverlap(100, 201, 200, 300), true)

{
    const result = CalendarMath.layoutTimedEvents([
        { uid: "a", startMs: 100, endMs: 300 },
        { uid: "b", startMs: 200, endMs: 400 },
        { uid: "c", startMs: 300, endMs: 500 }
    ])

    assert.deepEqual(result.map(event => ({
        uid: event.uid,
        column: event.column,
        columns: event.columns
    })), [
        { uid: "a", column: 0, columns: 2 },
        { uid: "b", column: 1, columns: 2 },
        { uid: "c", column: 0, columns: 2 }
    ])
}

{
    const source = [
        { uid: "a", startMs: 100, endMs: 300 },
        { uid: "b", startMs: 200, endMs: 400 }
    ]
    const before = JSON.stringify(source)

    CalendarMath.layoutTimedEvents(source)

    assert.equal(JSON.stringify(source), before)
}

{
    const result = CalendarMath.layoutTimedEvents([
        {
            uid: "first-fallback-hour",
            startMs: 100,
            endMs: 200,
            layoutStart: 120,
            layoutEnd: 180
        },
        {
            uid: "second-fallback-hour",
            startMs: 300,
            endMs: 400,
            layoutStart: 120,
            layoutEnd: 180
        }
    ])

    assert.deepEqual(result.map(event => ({
        column: event.column,
        columns: event.columns
    })), [
        { column: 0, columns: 2 },
        { column: 1, columns: 2 }
    ])
}

const calendars = [
    {
        id: "university", name: "University", color: "#6688aa",
        writable: false, visible: true
    },
    {
        id: "personal", name: "Personal", color: "#88aa66",
        writable: true, visible: true
    },
    {
        id: "hidden", name: "Hidden", color: "#aa6688",
        writable: true, visible: false
    }
]

{
    const source = calendars.slice(0, 2)
    const before = JSON.stringify(source)
    const hidden = CalendarMath.withCalendarVisibility(source, "personal", false)

    assert.notStrictEqual(hidden, source)
    assert.strictEqual(hidden[0], source[0])
    assert.notStrictEqual(hidden[1], source[1])
    assert.equal(hidden[1].visible, false)
    assert.equal(JSON.stringify(source), before)

    const restored = CalendarMath.withCalendarVisibility(hidden, "personal", true)
    assert.equal(restored[1].visible, true)
    assert.strictEqual(
        CalendarMath.withCalendarVisibility(restored, "personal", true), restored)
    assert.strictEqual(
        CalendarMath.withCalendarVisibility(restored, "missing", false), restored)
    assert.strictEqual(
        CalendarMath.withCalendarVisibility(restored, "personal", "no"), restored)
}

{
    const visible = CalendarMath.filterEventsInRange([
        { uid: "before", calendarId: "personal", startMs: 100, endMs: 200 },
        { uid: "inside", calendarId: "personal", startMs: 200, endMs: 300 },
        { uid: "hidden", calendarId: "hidden", startMs: 200, endMs: 300 }
    ], calendars, 200, 400)

    assert.deepEqual(visible.map(event => event.uid), ["inside"])
}

{
    const allHidden = calendars.map(calendar =>
        Object.assign({}, calendar, { visible: false }))
    const visible = CalendarMath.filterEventsInRange([
        { uid: "university", calendarId: "university", startMs: 200, endMs: 300 },
        { uid: "personal", calendarId: "personal", startMs: 200, endMs: 300 }
    ], allHidden, 200, 400)

    assert.deepEqual(visible, [])
}

{
    const day = new Date(2026, 9, 25)
    const morning = new Date(2026, 9, 25, 9, 30)
    const nextMidnight = new Date(2026, 9, 26)

    assert.equal(CalendarMath.wallClockMinutes(morning.getTime(), day), 570)
    assert.equal(CalendarMath.wallClockMinutes(nextMidnight.getTime(), day), 1440)

    const foldRange = CalendarMath.wallClockRange(
        Date.parse("2026-10-25T02:30:00+02:00"),
        Date.parse("2026-10-25T02:30:00+01:00"),
        day)
    assert.deepEqual(foldRange, { start: 150, end: 210 })
}

{
    const gridStart = CalendarMath.monthGridStart(new Date(2026, 8, 15))
    const gridEnd = CalendarMath.addDays(gridStart, 42)

    assert.equal(gridStart.getFullYear(), 2026)
    assert.equal(gridStart.getMonth(), 7)
    assert.equal(gridStart.getDate(), 31)
    assert.equal(gridStart.getDay(), 1)
    assert.equal(gridEnd.getMonth(), 9)
    assert.equal(gridEnd.getDate(), 12)
}

{
    const february = CalendarMath.addMonthsClamped(new Date(2026, 0, 31), 1)
    const january = CalendarMath.addMonthsClamped(february, -1)

    assert.equal(february.getFullYear(), 2026)
    assert.equal(february.getMonth(), 1)
    assert.equal(february.getDate(), 28)
    assert.equal(january.getMonth(), 0)
    assert.equal(january.getDate(), 28)
}

assert.deepEqual(CalendarMath.clippedInterval(100, 300, 200, 400), {
    start: 200,
    end: 300
})
assert.equal(CalendarMath.clippedInterval(100, 200, 200, 300), null)

assert.equal(CalendarMath.monthStartIndex(new Date(2025, 3, 28)), 3)
assert.equal(CalendarMath.monthStartIndex(new Date(2025, 4, 5)), -1)
assert.equal(CalendarMath.monthStartIndex(new Date(2025, 11, 29)), 3)

assert.equal(CalendarMath.weekCount(
    new Date(2026, 2, 23), new Date(2026, 3, 6)), 2)
assert.equal(CalendarMath.weekCount(
    new Date(2026, 3, 6), new Date(2026, 2, 23)), 0)
assert.equal(CalendarMath.weekCount(
    CalendarMath.weekStart(new Date(2026, 0, 1)),
    CalendarMath.addDays(CalendarMath.weekStart(new Date(2026, 11, 31)), 7)), 53)
assert.equal(CalendarMath.weekCount(
    CalendarMath.weekStart(new Date(2012, 0, 1)),
    CalendarMath.addDays(CalendarMath.weekStart(new Date(2012, 11, 31)), 7)), 54)

assert.equal(CalendarMath.daysInMonth(2024, 1), 29)
assert.equal(CalendarMath.daysInMonth(2025, 1), 28)
assert.equal(CalendarMath.daysInMonth(2026, 3), 30)
assert.equal(CalendarMath.daysInMonth(2026, 6), 31)

assert.equal(CalendarMath.roundMinuteToStep(0, 5), 0)
assert.equal(CalendarMath.roundMinuteToStep(12, 5), 10)
assert.equal(CalendarMath.roundMinuteToStep(13, 5), 15)
assert.equal(CalendarMath.roundMinuteToStep(58, 5), 55)

{
    const events = [
        {
            uid: "all-day",
            allDay: true,
            startMs: new Date(2026, 2, 24).getTime(),
            endMs: new Date(2026, 2, 25).getTime()
        },
        {
            uid: "timed",
            allDay: false,
            startMs: new Date(2026, 2, 24, 9).getTime(),
            endMs: new Date(2026, 2, 24, 10).getTime()
        },
        {
            uid: "multi-day",
            allDay: true,
            startMs: new Date(2026, 2, 25).getTime(),
            endMs: new Date(2026, 2, 28).getTime()
        },
        {
            uid: "ongoing-before",
            allDay: false,
            startMs: new Date(2026, 2, 22, 20).getTime(),
            endMs: new Date(2026, 2, 23, 10).getTime()
        }
    ]
    const before = JSON.stringify(events)
    const days = CalendarMath.buildAgendaDays(events, new Date(2026, 2, 23), 14)

    assert.equal(days.length, 14)
    assert.equal(days[0].date.getDate(), 23)
    assert.equal(days[6].date.getDate(), 29)
    assert.equal(days[13].date.getMonth(), 3)
    assert.equal(days[13].date.getDate(), 5)
    assert.equal(days.every(day => day.date.getHours() === 0), true)
    assert.deepEqual(days[0].events, [])
    assert.deepEqual(days[1].events.map(event => event.uid), ["all-day", "timed"])
    assert.deepEqual(days[2].events.map(event => event.uid), ["multi-day"])
    assert.equal(days.reduce((count, day) => count + day.events.length, 0), 3)
    assert.strictEqual(days[1].events[0], events[0])
    assert.equal(JSON.stringify(events), before)
}

assert.equal(CalendarMath.eventDetails(null, calendars), null)
assert.equal(CalendarMath.eventDetails({ startMs: NaN, endMs: 10 }, calendars), null)
assert.equal(CalendarMath.reminderLabel(0), "At start time")
assert.equal(CalendarMath.reminderLabel(1), "1 minute before")
assert.equal(CalendarMath.reminderLabel(15), "15 minutes before")
assert.equal(CalendarMath.reminderLabel(60), "1 hour before")
assert.equal(CalendarMath.reminderLabel(1440), "1 day before")
assert.equal(CalendarMath.reminderLabel("bad"), "Reminder")

{
    const source = {
        calendarId: "missing",
        title: "   ",
        color: "invalid",
        location: "   ",
        description: "   ",
        allDay: true,
        readOnly: true,
        startMs: new Date(2026, 2, 28).getTime(),
        endMs: new Date(2026, 2, 31).getTime(),
        reminders: [
            { minutesBefore: 0 },
            { minutesBefore: 1 },
            { minutesBefore: 15 },
            { minutesBefore: "bad" },
            { minutesBefore: "" },
            { minutesBefore: false }
        ]
    }
    const before = JSON.stringify(source)
    const details = CalendarMath.eventDetails(source, calendars)

    assert.equal(details.title, "Untitled")
    assert.equal(details.calendarName, "Unknown calendar")
    assert.equal(details.color, "#8ba7d6")
    assert.equal(details.location, "No location")
    assert.equal(details.description, "No description")
    assert.deepEqual(details.reminders, [
        "At start time", "1 minute before", "15 minutes before", "Reminder",
        "Reminder", "Reminder"
    ])
    assert.equal(details.status, "Read-only")
    assert.equal(new Date(details.displayEndMs).getDate(), 30)
    assert.equal(new Date(details.displayEndMs).getHours(), 0)
    assert.equal(JSON.stringify(source), before)
}

assert.equal(CalendarMath.eventDetails({
    calendarId: "blank",
    title: "Title",
    startMs: 100,
    endMs: 200
}, [{ id: "blank", name: "   ", color: "#123456" }]).calendarName,
"Unknown calendar")

{
    const details = CalendarMath.eventDetails({
        calendarId: "personal",
        title: "Review",
        location: "Library",
        description: "Bring notes",
        allDay: false,
        readOnly: false,
        startMs: 100,
        endMs: 200,
        reminders: []
    }, calendars)

    assert.equal(details.calendarName, "Personal")
    assert.equal(details.color, "#88aa66")
    assert.equal(details.location, "Library")
    assert.equal(details.description, "Bring notes")
    assert.deepEqual(details.reminders, [])
    assert.equal(details.displayEndMs, 200)
    assert.equal(details.status, "Writable")
}

console.log("CalendarMath tests passed")
