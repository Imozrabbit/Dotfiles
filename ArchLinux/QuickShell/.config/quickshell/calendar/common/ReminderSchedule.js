function masterKey(calendarId, uid) {
    return JSON.stringify([calendarId, uid])
}

function snapshots(masters) {
    return new Map(masters.map(event => [masterKey(event.calendarId, event.uid), JSON.stringify(event)]))
}

function build(events, sources, afterMs, untilMs) {
    const rows = []
    for (const event of events) {
        const masterUid = event.masterUid || event.uid
        const source = sources.get(masterKey(event.calendarId, masterUid))
        if (source === undefined || !Number.isSafeInteger(event.startMs))
            continue
        for (const reminder of (event.reminders || [])) {
            const minutes = reminder && reminder.minutesBefore
            const atMs = event.startMs - minutes * 60000
            if (!Number.isSafeInteger(minutes) || minutes < 0 || !Number.isSafeInteger(atMs)
                    || atMs <= afterMs || atMs >= untilMs)
                continue
            const occurrenceId = event.occurrenceId || event.uid
            rows.push({
                key: JSON.stringify([event.calendarId, masterUid, occurrenceId, minutes, atMs]),
                calendarId: event.calendarId, masterUid, occurrenceId, atMs,
                startMs: event.startMs, title: event.title, location: event.location,
                allDay: event.allDay === true, source
            })
        }
    }
    return merge(rows, [])
}

function retain(rows, sources, afterMs) {
    return rows.filter(row => row.atMs > afterMs
        && sources.get(masterKey(row.calendarId, row.masterUid)) === row.source)
}

function merge(left, right) {
    return Array.from(new Map(left.concat(right).map(row => [row.key, row])).values())
        .sort((a, b) => a.atMs - b.atMs || a.key.localeCompare(b.key))
}

function takeDue(rows, clock, nowMs) {
    if (!Number.isSafeInteger(nowMs))
        return []
    const previous = clock.highWaterMs
    const elapsed = nowMs - clock.lastMs
    clock.lastMs = nowMs
    clock.highWaterMs = Math.max(previous, nowMs)
    if (elapsed < 0 || elapsed > 5000)
        return []
    const due = []
    for (const row of rows) {
        if (row.atMs > nowMs)
            break // Rows are sorted; idle ticks do not scan future deadlines.
        if (row.atMs > previous)
            due.push(row)
    }
    return due
}

function escapeMarkup(text) {
    return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}
