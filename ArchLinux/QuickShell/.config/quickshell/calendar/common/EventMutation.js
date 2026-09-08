function failure(field, message) {
    return { ok: false, field, message }
}

function localDateMs(value) {
    if (typeof value !== "string")
        return NaN
    const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value)
    if (!match)
        return NaN

    const date = new Date(0)
    date.setFullYear(Number(match[1]), Number(match[2]) - 1, Number(match[3]))
    date.setHours(0, 0, 0, 0)
    if (date.getFullYear() !== Number(match[1])
            || date.getMonth() !== Number(match[2]) - 1
            || date.getDate() !== Number(match[3]))
        return NaN
    return date.getTime()
}

function timestampMs(value) {
    if (typeof value !== "string")
        return NaN
    const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,3})?(?:Z|[+-](\d{2}):(\d{2}))$/.exec(value)
    if (!match || Number(match[4]) > 23 || Number(match[5]) > 59
            || Number(match[6]) > 59 || Number(match[7] || 0) > 23
            || Number(match[8] || 0) > 59)
        return NaN
    const date = new Date(0)
    date.setUTCFullYear(Number(match[1]), Number(match[2]) - 1, Number(match[3]))
    if (date.getUTCFullYear() !== Number(match[1])
            || date.getUTCMonth() !== Number(match[2]) - 1
            || date.getUTCDate() !== Number(match[3]))
        return NaN
    return Date.parse(value)
}

function eventTimes(source) {
    if (source.allDay === true) {
        return {
            startMs: localDateMs(source.start),
            endMs: localDateMs(source.end)
        }
    }

    return {
        startMs: timestampMs(source.start),
        endMs: timestampMs(source.end)
    }
}

function canonicalReminders(value) {
    if (!Array.isArray(value))
        return []

    const seen = new Set()
    const reminders = []
    for (const reminder of value) {
        const minutes = reminder && reminder.minutesBefore
        if (!Number.isSafeInteger(minutes) || minutes < 0 || seen.has(minutes))
            continue
        seen.add(minutes)
        reminders.push({ minutesBefore: minutes })
    }
    return reminders
}

function validateReminders(value) {
    if (value === undefined)
        return { ok: true, reminders: [] }
    if (!Array.isArray(value))
        return failure("reminders", "Reminders must be a list")

    const reminders = canonicalReminders(value)
    if (reminders.length !== value.length)
        return failure("reminders", "Use unique nonnegative whole-minute reminders")
    return { ok: true, reminders }
}

function normalizeEvent(source, calendars) {
    if (!source || typeof source !== "object" || !Array.isArray(calendars))
        return null

    const calendar = calendars.find(item => item.id === source.calendarId)
    if (!calendar || typeof source.uid !== "string" || source.uid.length === 0)
        return null

    const times = eventTimes(source)
    if (!Number.isFinite(times.startMs) || !Number.isFinite(times.endMs)
            || times.endMs <= times.startMs)
        return null

    const title = typeof source.title === "string" ? source.title.trim() : ""
    return Object.assign({}, source, {
        title: title.length > 0 ? title : "Untitled",
        description: typeof source.description === "string" ? source.description : "",
        location: typeof source.location === "string" ? source.location : "",
        allDay: source.allDay === true,
        readOnly: calendar.writable !== true || source.readOnly === true,
        color: typeof source.color === "string"
                && /^#[0-9a-f]{6}(?:[0-9a-f]{2})?$/i.test(source.color)
            ? source.color : calendar.color,
        reminders: canonicalReminders(source.reminders),
        startMs: times.startMs,
        endMs: times.endMs
    })
}

function validateEvent(eventData, calendars, uid) {
    if (!eventData || typeof eventData !== "object")
        return failure("event", "Event data is required")
    if (typeof uid !== "string" || uid.length === 0)
        return failure("uid", "Event identifier is required")
    if (!Array.isArray(calendars))
        return failure("calendarId", "Choose a writable calendar")

    const calendar = calendars.find(item => item.id === eventData.calendarId)
    if (!calendar)
        return failure("calendarId", "Choose a writable calendar")
    if (calendar.writable !== true)
        return failure("calendarId", "Calendar is read-only")

    const reminderResult = validateReminders(eventData.reminders)
    if (!reminderResult.ok)
        return reminderResult

    const candidate = Object.assign({}, eventData, {
        uid,
        reminders: reminderResult.reminders
    })
    const normalized = normalizeEvent(candidate, calendars)
    if (normalized)
        return { ok: true, event: normalized }

    const times = eventTimes(candidate)
    if (!Number.isFinite(times.startMs))
        return failure("start", "Enter a valid start")
    return failure("end", "End must be later than start")
}

function canonicalRaw(event, source, preserved) {
    const raw = {
        uid: event.uid,
        calendarId: event.calendarId,
        title: event.title,
        description: event.description,
        location: event.location,
        start: source.start,
        end: source.end,
        allDay: event.allDay,
        reminders: canonicalReminders(event.reminders)
    }
    if (preserved && Object.prototype.hasOwnProperty.call(preserved, "readOnly"))
        raw.readOnly = preserved.readOnly
    if (preserved && Object.prototype.hasOwnProperty.call(preserved, "color"))
        raw.color = preserved.color
    return raw
}

function storageFailure(message) {
    return failure("storage", message)
}

function canonicalPersonalEvents(value, calendars, reservedUids) {
    if (!Array.isArray(value))
        return storageFailure("Personal calendar events must be a list")

    const required = [
        "uid", "calendarId", "title", "description", "location",
        "start", "end", "allDay", "reminders"
    ]
    const allowed = new Set(required)
    const seen = new Set()
    const reserved = new Set(Array.isArray(reservedUids) ? reservedUids : [])
    const rawEvents = []

    for (const source of value) {
        if (!source || typeof source !== "object" || Array.isArray(source))
            return storageFailure("Personal calendar contains an invalid event")
        if (Object.keys(source).some(key => !allowed.has(key))
                || required.some(key => !Object.prototype.hasOwnProperty.call(source, key)))
            return storageFailure("Personal calendar event schema is invalid")
        if (source.calendarId !== "personal")
            return storageFailure("Personal calendar contains a non-Personal event")
        if (typeof source.uid !== "string" || source.uid.length === 0
                || seen.has(source.uid) || reserved.has(source.uid))
            return storageFailure("Personal calendar event UIDs must be unique")
        if (typeof source.title !== "string"
                || typeof source.description !== "string"
                || typeof source.location !== "string"
                || typeof source.start !== "string"
                || typeof source.end !== "string"
                || typeof source.allDay !== "boolean")
            return storageFailure("Personal calendar event fields are invalid")
        if (!Array.isArray(source.reminders)
                || source.reminders.some(reminder => !reminder
                    || typeof reminder !== "object" || Array.isArray(reminder)
                    || Object.keys(reminder).length !== 1
                    || !Object.prototype.hasOwnProperty.call(reminder, "minutesBefore")))
            return storageFailure("Personal calendar reminder schema is invalid")

        const validation = validateEvent(source, calendars, source.uid)
        if (!validation.ok)
            return storageFailure("Invalid Personal event " + source.uid
                + ": " + validation.message)

        seen.add(source.uid)
        rawEvents.push(canonicalRaw(validation.event, source, null))
    }

    return { ok: true, rawEvents }
}

function parsePersonalStore(text, calendars, reservedUids) {
    if (typeof text !== "string")
        return storageFailure("Personal calendar JSON is invalid")

    let document
    try {
        document = JSON.parse(text)
    } catch (error) {
        return storageFailure("Personal calendar JSON is malformed")
    }

    if (!document || typeof document !== "object" || Array.isArray(document)
            || Object.keys(document).length !== 2
            || !Object.prototype.hasOwnProperty.call(document, "version")
            || !Object.prototype.hasOwnProperty.call(document, "events")
            || document.version !== 1 || !Array.isArray(document.events))
        return storageFailure("Personal calendar schema is unsupported")

    return canonicalPersonalEvents(document.events, calendars, reservedUids)
}

function serializePersonalStore(rawEvents, calendars, reservedUids) {
    const result = canonicalPersonalEvents(rawEvents, calendars, reservedUids)
    if (!result.ok)
        return result
    return {
        ok: true,
        rawEvents: result.rawEvents,
        text: JSON.stringify({ version: 1, events: result.rawEvents }, null, 2) + "\n"
    }
}

function targetEvent(rawEvents, calendars, uid) {
    if (!Array.isArray(rawEvents) || typeof uid !== "string" || uid.length === 0)
        return failure("uid", "Event not found")
    const index = rawEvents.findIndex(event => event.uid === uid)
    if (index < 0)
        return failure("uid", "Event not found")
    const event = normalizeEvent(rawEvents[index], calendars)
    if (!event)
        return failure("uid", "Event not found")
    if (event.readOnly)
        return failure("event", "Event is read-only")
    return { ok: true, index, event, raw: rawEvents[index] }
}

function createEvent(rawEvents, calendars, eventData, uid) {
    if (!Array.isArray(rawEvents))
        return failure("event", "Event data is required")
    if (rawEvents.some(event => event.uid === uid))
        return failure("uid", "Event identifier already exists")

    const validation = validateEvent(eventData, calendars, uid)
    if (!validation.ok)
        return validation
    const raw = canonicalRaw(validation.event, eventData, null)
    return {
        ok: true,
        event: normalizeEvent(raw, calendars),
        rawEvents: rawEvents.concat([raw])
    }
}

function updateEvent(rawEvents, calendars, uid, eventData) {
    const target = targetEvent(rawEvents, calendars, uid)
    if (!target.ok)
        return target
    if (!eventData || typeof eventData !== "object")
        return failure("event", "Event data is required")

    const candidate = Object.assign({}, target.raw, eventData, {
        uid,
        reminders: Object.prototype.hasOwnProperty.call(eventData, "reminders")
            ? eventData.reminders : target.event.reminders,
        readOnly: target.raw.readOnly,
        color: target.raw.color
    })
    const validation = validateEvent(candidate, calendars, uid)
    if (!validation.ok)
        return validation
    const raw = canonicalRaw(validation.event, candidate, target.raw)
    const result = rawEvents.slice()
    result[target.index] = raw
    return { ok: true, event: normalizeEvent(raw, calendars), rawEvents: result }
}

function deleteEvent(rawEvents, calendars, uid) {
    const target = targetEvent(rawEvents, calendars, uid)
    if (!target.ok)
        return target
    return {
        ok: true,
        uid,
        rawEvents: rawEvents.filter((event, index) => index !== target.index)
    }
}

if (typeof module !== "undefined") {
    module.exports = {
        createEvent,
        deleteEvent,
        normalizeEvent,
        parsePersonalStore,
        serializePersonalStore,
        updateEvent
    }
}
