function dayStart(date) {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate())
}

function addDays(date, days) {
    const result = new Date(date.getTime())
    result.setDate(result.getDate() + days)
    return result
}

function weekStart(date) {
    const result = dayStart(date)
    result.setDate(result.getDate() - (result.getDay() + 6) % 7)
    return result
}

function weekCount(startDate, endDate) {
    let cursor = dayStart(startDate)
    const end = dayStart(endDate)
    let count = 0
    while (cursor < end) {
        cursor = addDays(cursor, 7)
        ++count
    }
    return count
}

function monthGridStart(date) {
    return weekStart(new Date(date.getFullYear(), date.getMonth(), 1))
}

function monthStartIndex(weekStartDate) {
    for (let index = 0; index < 7; ++index) {
        if (addDays(weekStartDate, index).getDate() === 1)
            return index
    }
    return -1
}

function daysInMonth(year, monthIndex) {
    return new Date(year, monthIndex + 1, 0).getDate()
}

function roundMinuteToStep(minute, step) {
    if (!Number.isFinite(minute) || !Number.isFinite(step) || step <= 0)
        return 0
    return Math.max(0, Math.min(60 - step, Math.round(minute / step) * step))
}

function buildAgendaDays(events, startDate, dayCount) {
    const count = Number.isFinite(Number(dayCount))
        ? Math.max(0, Math.floor(Number(dayCount))) : 0
    const start = dayStart(startDate)
    const days = []
    const dayIndexes = {}
    for (let index = 0; index < count; ++index)
        days.push({ date: addDays(start, index), events: [] })

    for (let index = 0; index < days.length; ++index) {
        const date = days[index].date
        dayIndexes[date.getFullYear() + "-" + date.getMonth() + "-" + date.getDate()] = index
    }

    if (!Array.isArray(events))
        return days

    for (const event of events) {
        if (!event || !Number.isFinite(event.startMs))
            continue
        const eventDate = dayStart(new Date(event.startMs))
        const key = eventDate.getFullYear() + "-" + eventDate.getMonth() + "-" + eventDate.getDate()
        const dayIndex = dayIndexes[key]
        if (dayIndex !== undefined)
            days[dayIndex].events.push(event)
    }
    return days
}

function addMonthsClamped(date, months) {
    const target = new Date(date.getFullYear(), date.getMonth() + months, 1,
        date.getHours(), date.getMinutes(), date.getSeconds(), date.getMilliseconds())
    const lastDay = new Date(target.getFullYear(), target.getMonth() + 1, 0).getDate()
    target.setDate(Math.min(date.getDate(), lastDay))
    return target
}

function rangesOverlap(startA, endA, startB, endB) {
    return startA < endB && endA > startB
}

function clippedInterval(start, end, rangeStart, rangeEnd) {
    if (!rangesOverlap(start, end, rangeStart, rangeEnd))
        return null
    return {
        start: Math.max(start, rangeStart),
        end: Math.min(end, rangeEnd)
    }
}

function reminderLabel(minutes) {
    if (!Number.isSafeInteger(minutes) || minutes < 0)
        return "Reminder"
    if (minutes === 0)
        return "At start time"
    if (minutes === 1)
        return "1 minute before"
    if (minutes === 60)
        return "1 hour before"
    if (minutes === 1440)
        return "1 day before"
    return minutes + " minutes before"
}

function eventDetails(event, calendars) {
    if (!event || typeof event !== "object"
            || !Number.isFinite(event.startMs) || !Number.isFinite(event.endMs)
            || event.endMs <= event.startMs)
        return null

    const calendar = Array.isArray(calendars)
        ? calendars.find(item => item.id === event.calendarId) : null
    const validColor = value => typeof value === "string"
        && /^#[0-9a-f]{6}(?:[0-9a-f]{2})?$/i.test(value)
    const safeText = (value, fallback) => typeof value === "string"
            && value.trim().length > 0
        ? value.trim() : fallback
    const reminderLabels = Array.isArray(event.reminders)
        ? event.reminders.map(reminder => reminderLabel(reminder && reminder.minutesBefore))
        : []
    const allDay = event.allDay === true
    const displayEndMs = allDay
        ? addDays(new Date(event.endMs), -1).getTime() : event.endMs

    return {
        title: safeText(event.title, "Untitled"),
        calendarName: safeText(calendar && calendar.name, "Unknown calendar"),
        color: validColor(event.color) ? event.color
            : calendar && validColor(calendar.color) ? calendar.color : "#8ba7d6",
        location: safeText(event.location, "No location"),
        description: safeText(event.description, "No description"),
        reminders: reminderLabels,
        allDay,
        startMs: event.startMs,
        endMs: event.endMs,
        displayEndMs,
        status: event.readOnly === true ? "Read-only" : "Writable"
    }
}

function wallClockMinutes(timestamp, day) {
    const date = new Date(timestamp)
    const start = dayStart(day)
    const end = dayStart(addDays(day, 1))
    if (!Number.isFinite(date.getTime()))
        return NaN
    if (date <= start)
        return 0
    if (date >= end)
        return 1440
    return date.getHours() * 60 + date.getMinutes() + date.getSeconds() / 60
}

function wallClockRange(startTimestamp, endTimestamp, day) {
    const start = wallClockMinutes(startTimestamp, day)
    let end = wallClockMinutes(endTimestamp, day)
    if (end <= start)
        end = Math.min(1440, start + (endTimestamp - startTimestamp) / 60000)
    return { start, end }
}

function withCalendarVisibility(calendars, calendarId, visible) {
    if (!Array.isArray(calendars) || typeof calendarId !== "string"
            || typeof visible !== "boolean")
        return calendars

    const index = calendars.findIndex(calendar => calendar.id === calendarId)
    if (index < 0 || calendars[index].visible === visible)
        return calendars

    return calendars.map((calendar, calendarIndex) => calendarIndex === index
        ? Object.assign({}, calendar, { visible }) : calendar)
}

function filterEventsInRange(events, calendars, startMs, endMs) {
    if (!Number.isFinite(startMs) || !Number.isFinite(endMs) || endMs <= startMs)
        return []

    const calendarById = {}
    for (const calendar of calendars) {
        if (calendar && typeof calendar.id === "string" && calendarById[calendar.id] === undefined)
            calendarById[calendar.id] = calendar
    }

    return events.filter(event => {
        const calendar = calendarById[event.calendarId]
        return calendar && calendar.visible !== false
            && rangesOverlap(event.startMs, event.endMs, startMs, endMs)
    }).sort((left, right) => Number(right.allDay) - Number(left.allDay)
        || left.startMs - right.startMs
        || String(left.uid).localeCompare(String(right.uid)))
}

function layoutTimedEvents(events) {
    function layoutStart(event) {
        return Number.isFinite(event.layoutStart) ? event.layoutStart : event.startMs
    }

    function layoutEnd(event) {
        return Number.isFinite(event.layoutEnd) ? event.layoutEnd : event.endMs
    }

    const sorted = events.slice().sort((left, right) =>
        layoutStart(left) - layoutStart(right)
        || (layoutEnd(right) - layoutStart(right))
            - (layoutEnd(left) - layoutStart(left))
        || String(left.uid).localeCompare(String(right.uid)))
    const result = []
    let cluster = []
    let columnEnds = []
    let clusterEnd = -Infinity

    function finishCluster() {
        const columns = columnEnds.length
        for (const event of cluster)
            event.columns = columns
    }

    for (const source of sorted) {
        const sourceStart = layoutStart(source)
        const sourceEnd = layoutEnd(source)
        if (sourceStart >= clusterEnd) {
            finishCluster()
            cluster = []
            columnEnds = []
            clusterEnd = -Infinity
        }

        let column = columnEnds.findIndex(end => end <= sourceStart)
        if (column === -1)
            column = columnEnds.length

        columnEnds[column] = sourceEnd
        clusterEnd = Math.max(clusterEnd, sourceEnd)

        const event = Object.assign({}, source, { column, columns: 0 })
        cluster.push(event)
        result.push(event)
    }

    finishCluster()
    return result
}

if (typeof module !== "undefined") {
    module.exports = {
        addDays,
        addMonthsClamped,
        buildAgendaDays,
        clippedInterval,
        dayStart,
        daysInMonth,
        eventDetails,
        filterEventsInRange,
        layoutTimedEvents,
        monthGridStart,
        monthStartIndex,
        rangesOverlap,
        reminderLabel,
        roundMinuteToStep,
        wallClockMinutes,
        wallClockRange,
        withCalendarVisibility,
        weekCount,
        weekStart
    }
}
