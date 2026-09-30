const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")
const EventMutation = require("../../common/EventMutation.js")

const source = fs.readFileSync(path.join(__dirname, "../../services/CalendarService.qml"), "utf8")
const start = source.indexOf("    function finishSyncedMutation(")
const end = source.indexOf("    function syncedMutation(", start)
assert.ok(start >= 0 && end > start)

const calendars = [{ id: "personal", color: "#112233", writable: true, visible: true }]
const oldEvent = {
    uid: "personal:source", sourceUid: "source", revision: "old", calendarId: "personal",
    title: "Before", description: "", location: "", start: "2026-06-14T14:00:00Z",
    end: "2026-06-14T15:00:00Z", allDay: false, reminders: []
}
const newEvent = Object.assign({}, oldEvent, { revision: "new", title: "After" })
const store = { rawEvents: [oldEvent] }
const emitted = []
let stopped = 0
const root = {
    calendars,
    syncReloadAttempts: 0,
    syncReloadTimer: { stop() { stopped++ } },
    eventMutationFinished(result) { emitted.push(result) },
    pendingEventMutation: {
        operation: "update", store, sourceUid: "source", cacheUid: oldEvent.uid,
        result: { ok: true, event: EventMutation.normalizeEvent(
            Object.assign({}, newEvent, { start: "2026-06-14T14:00:00.000Z" }), calendars) }
    }
}
const context = { root, EventMutation }
vm.runInNewContext(source.slice(start, end), context)
context.finishSyncedMutation()
assert.equal(emitted.length, 0, "stale cache must not finish update")
assert.notEqual(root.pendingEventMutation, null)

store.rawEvents = [newEvent]
context.finishSyncedMutation()
assert.equal(emitted.length, 1)
assert.equal(emitted[0].ok, true)
assert.equal(emitted[0].event.title, "After")
assert.equal(emitted[0].event.startMs, Date.parse(newEvent.start))
assert.equal(root.pendingEventMutation, null)
assert.equal(stopped, 1)

root.pendingEventMutation = {
    operation: "update", store, sourceUid: "source", cacheUid: oldEvent.uid,
    result: { ok: true, event: EventMutation.normalizeEvent(oldEvent, calendars) }
}
root.syncReloadAttempts = 50
context.finishSyncedMutation()
assert.equal(emitted[1].ok, true, "committed update must not invite a duplicate retry")
assert.equal(emitted[1].cacheWarning, true)

console.log("Synced reload tests passed")
