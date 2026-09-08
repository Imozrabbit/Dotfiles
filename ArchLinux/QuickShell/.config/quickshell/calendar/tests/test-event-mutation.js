const assert = require("node:assert/strict")
const EventMutation = require("../common/EventMutation.js")

const calendars = [
    {
        id: "readonly", name: "Read only", color: "#6688aa",
        writable: false, visible: true
    },
    {
        id: "personal", name: "Personal", color: "#88aa66",
        writable: true, visible: true
    }
]

const rawEvents = [
    {
        uid: "readonly-event",
        calendarId: "readonly",
        title: "Lecture",
        start: "2026-09-02T09:00:00+02:00",
        end: "2026-09-02T10:00:00+02:00",
        allDay: false,
        reminders: []
    },
    {
        uid: "personal-event",
        calendarId: "personal",
        title: "Review",
        start: "2026-09-02T10:00:00+02:00",
        end: "2026-09-02T11:00:00+02:00",
        allDay: false,
        reminders: [{ minutesBefore: 15 }]
    }
]

const validDraft = {
    calendarId: "personal",
    title: "New event",
    description: "Notes",
    location: "Library",
    start: "2026-09-03T09:00:00+02:00",
    end: "2026-09-03T10:00:00+02:00",
    allDay: false
}

assert.equal(EventMutation.normalizeEvent(null, calendars), null)

{
    const event = EventMutation.normalizeEvent(rawEvents[0], calendars)

    assert.equal(event.readOnly, true)
    assert.equal(event.color, "#6688aa")
    assert.equal(event.endMs - event.startMs, 60 * 60 * 1000)
}

{
    const event = EventMutation.normalizeEvent({
        uid: "invalid-color",
        calendarId: "personal",
        color: "not-a-color",
        start: "2026-09-02T09:00:00Z",
        end: "2026-09-02T10:00:00Z"
    }, calendars)

    assert.equal(event.color, "#88aa66")
}

assert.equal(EventMutation.normalizeEvent({
    uid: "unknown-calendar",
    calendarId: "missing",
    start: "2026-09-02T09:00:00+02:00",
    end: "2026-09-02T10:00:00+02:00"
}, calendars), null)

{
    const source = {
        uid: "filtered-reminders",
        calendarId: "personal",
        start: "2026-09-02T09:00:00+02:00",
        end: "2026-09-02T10:00:00+02:00",
        reminders: [
            { minutesBefore: 15 },
            { minutesBefore: -1 },
            { minutesBefore: 15 },
            { minutesBefore: 0 },
            null
        ]
    }
    const event = EventMutation.normalizeEvent(source, calendars)

    assert.deepEqual(event.reminders, [
        { minutesBefore: 15 },
        { minutesBefore: 0 }
    ])
    source.reminders[0].minutesBefore = 30
    assert.equal(event.reminders[0].minutesBefore, 15)
}

assert.equal(EventMutation.normalizeEvent({
    uid: "bad-range",
    calendarId: "personal",
    start: "2026-09-02T11:00:00+02:00",
    end: "2026-09-02T10:00:00+02:00"
}, calendars), null)

{
    const event = EventMutation.normalizeEvent({
        uid: "all-day",
        calendarId: "personal",
        start: "2026-09-02",
        end: "2026-09-03",
        allDay: true
    }, calendars)

    assert.equal(new Date(event.startMs).getDate(), 2)
    assert.equal(new Date(event.endMs).getDate(), 3)
}

{
    const before = JSON.stringify(rawEvents)
    const result = EventMutation.createEvent(
        rawEvents, calendars, validDraft, "mock-1")

    assert.equal(result.ok, true)
    assert.equal(result.event.uid, "mock-1")
    assert.equal(result.event.readOnly, false)
    assert.equal(result.rawEvents.length, 3)
    assert.equal(JSON.stringify(rawEvents), before)
}

{
    const reminders = [{ minutesBefore: 15 }, { minutesBefore: 60 }]
    const result = EventMutation.createEvent(rawEvents, calendars,
        Object.assign({}, validDraft, { reminders }), "mock-reminders")

    assert.equal(result.ok, true)
    assert.deepEqual(result.event.reminders, reminders)
    assert.deepEqual(result.rawEvents[2].reminders, reminders)
    reminders[0].minutesBefore = 30
    assert.equal(result.event.reminders[0].minutesBefore, 15)
    assert.equal(result.rawEvents[2].reminders[0].minutesBefore, 15)
}

{
    const result = EventMutation.createEvent(rawEvents, calendars,
        Object.assign({}, validDraft, { title: "   " }), "mock-1")

    assert.equal(result.ok, true)
    assert.equal(result.event.title, "Untitled")
    assert.deepEqual(result.event.reminders, [])
}

assert.deepEqual(EventMutation.createEvent(rawEvents, calendars,
    Object.assign({}, validDraft, { calendarId: "readonly" }), "mock-1"), {
    ok: false,
    field: "calendarId",
    message: "Calendar is read-only"
})
assert.equal(EventMutation.createEvent(rawEvents, calendars,
    Object.assign({}, validDraft, { end: validDraft.start }), "mock-1").field,
"end")
assert.equal(EventMutation.createEvent(
    rawEvents, calendars, validDraft, "personal-event").field, "uid")
assert.equal(EventMutation.createEvent(rawEvents, calendars,
    Object.assign({}, validDraft, {
        reminders: [{ minutesBefore: 15 }, { minutesBefore: 15 }]
    }), "mock-duplicate-reminders").field, "reminders")
assert.equal(EventMutation.createEvent(rawEvents, calendars,
    Object.assign({}, validDraft, {
        reminders: [{ minutesBefore: 1.5 }]
    }), "mock-invalid-reminder").field, "reminders")
assert.equal(EventMutation.createEvent(rawEvents, calendars,
    Object.assign({}, validDraft, { reminders: "15" }),
    "mock-invalid-reminders").field, "reminders")

{
    const before = JSON.stringify(rawEvents)
    const result = EventMutation.updateEvent(rawEvents, calendars,
        "personal-event", Object.assign({}, validDraft, { title: "Updated" }))

    assert.equal(result.ok, true)
    assert.equal(result.event.uid, "personal-event")
    assert.equal(result.event.title, "Updated")
    assert.deepEqual(result.event.reminders, [{ minutesBefore: 15 }])
    assert.equal(result.rawEvents[1].title, "Updated")
    assert.equal(JSON.stringify(rawEvents), before)
}

{
    const result = EventMutation.updateEvent(rawEvents, calendars,
        "personal-event", Object.assign({}, validDraft, {
            reminders: [{ minutesBefore: 5 }, { minutesBefore: 60 }]
        }))

    assert.equal(result.ok, true)
    assert.deepEqual(result.event.reminders, [
        { minutesBefore: 5 },
        { minutesBefore: 60 }
    ])
}

assert.equal(EventMutation.updateEvent(
    rawEvents, calendars, "personal-event", null).field, "event")

{
    const events = rawEvents.concat([{
        uid: "imported-reminders",
        calendarId: "personal",
        title: "Imported",
        start: "2026-09-02T12:00:00+02:00",
        end: "2026-09-02T13:00:00+02:00",
        allDay: false,
        reminders: [
            { minutesBefore: 15 },
            { minutesBefore: 15 },
            { minutesBefore: -1 }
        ]
    }])
    const result = EventMutation.updateEvent(events, calendars,
        "imported-reminders", Object.assign({}, validDraft, {
            title: "Updated import"
        }))

    assert.equal(result.ok, true)
    assert.deepEqual(result.event.reminders, [{ minutesBefore: 15 }])
}

assert.equal(EventMutation.updateEvent(
    rawEvents, calendars, "readonly-event", validDraft).ok, false)
assert.equal(EventMutation.updateEvent(
    rawEvents, calendars, "missing", validDraft).field, "uid")

{
    const before = JSON.stringify(rawEvents)
    const result = EventMutation.deleteEvent(
        rawEvents, calendars, "personal-event")

    assert.equal(result.ok, true)
    assert.equal(result.uid, "personal-event")
    assert.deepEqual(result.rawEvents.map(event => event.uid), ["readonly-event"])
    assert.equal(JSON.stringify(rawEvents), before)
}

assert.equal(EventMutation.deleteEvent(
    rawEvents, calendars, "readonly-event").ok, false)
assert.equal(EventMutation.deleteEvent(
    rawEvents, calendars, "missing").field, "uid")

const storedEvent = {
    uid: "personal-stored",
    calendarId: "personal",
    title: "Stored event",
    description: "Notes",
    location: "Home",
    start: "2026-09-03T09:00:00+02:00",
    end: "2026-09-03T10:00:00+02:00",
    allDay: false,
    reminders: [{ minutesBefore: 15 }]
}

assert.deepEqual(EventMutation.parsePersonalStore(
    '{"version":1,"events":[]}', calendars), {
    ok: true,
    rawEvents: []
})

{
    const serialized = EventMutation.serializePersonalStore([storedEvent], calendars)
    assert.equal(serialized.ok, true)
    assert.equal(serialized.text.endsWith("\n"), true)
    assert.deepEqual(EventMutation.parsePersonalStore(
        serialized.text, calendars).rawEvents, [storedEvent])
}

for (const text of [
    "{",
    "[]",
    '{"version":2,"events":[]}',
    '{"version":1,"events":{}}',
    '{"version":1,"events":[],"extra":true}',
    JSON.stringify({ version: 1, events: [
        Object.assign({}, storedEvent, { calendarId: "readonly" })
    ]}),
    JSON.stringify({ version: 1, events: [storedEvent, storedEvent] }),
    JSON.stringify({ version: 1, events: [
        Object.assign({}, storedEvent, { end: storedEvent.start })
    ]}),
    JSON.stringify({ version: 1, events: [
        Object.assign({}, storedEvent, { startMs: 1 })
    ]}),
    JSON.stringify({ version: 1, events: [
        Object.assign({}, storedEvent, {
            reminders: [{ minutesBefore: 15, extra: true }]
        })
    ]})
]) {
    const result = EventMutation.parsePersonalStore(text, calendars)
    assert.equal(result.ok, false)
    assert.equal(result.field, "storage")
}

{
    const result = EventMutation.parsePersonalStore(
        JSON.stringify({ version: 1, events: [storedEvent] }),
        calendars, [storedEvent.uid])
    assert.equal(result.ok, false)
    assert.equal(result.field, "storage")
}


for (const start of ["2026-02-30T09:00:00Z", "September 3, 2026 09:00:00Z",
    "2026-09-03T24:00:00Z", "2026-09-03T09:60:00Z"]) {
    assert.equal(EventMutation.normalizeEvent(Object.assign({}, storedEvent, {
        start, end: "2027-01-01T00:00:00Z"
    }), calendars), null)
}
for (const start of ["2024-02-29T09:00:00.000Z", "2026-09-03T09:00:00+02:00"]) {
    assert.notEqual(EventMutation.normalizeEvent(Object.assign({}, storedEvent, {
        start, end: "2027-01-01T00:00:00Z"
    }), calendars), null)
}
assert.notEqual(EventMutation.normalizeEvent(Object.assign({}, storedEvent, {
    allDay: true, start: "0099-09-02", end: "0099-09-03"
}), calendars), null)

console.log("EventMutation tests passed")
