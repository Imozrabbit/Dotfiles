const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

const service = fs.readFileSync(path.join(__dirname, "../../services/CalendarService.qml"), "utf8")
const start = service.indexOf("    function updateEvent(")
const end = service.indexOf("    function deleteEvent(", start)
assert.notEqual(start, -1)
assert.notEqual(end, -1)
const updateSource = service.slice(start, end)

function runMove({ destinationFailure, sourceFailure, rollbackFailure }) {
    const sourceEvent = { uid: "moving", calendarId: "source", title: "Before" }
    const previousDestination = { uid: "existing", calendarId: "destination", title: "Keep" }
    const source = { profile: { id: "source", type: "local" }, ready: true, rawEvents: [sourceEvent] }
    const destination = { profile: { id: "destination", type: "local" }, ready: true, rawEvents: [previousDestination] }
    const writes = []
    const root = {
        rawEvents: [sourceEvent, previousDestination],
        storeForId: id => id === "source" ? source : destination,
        storageUnavailable: () => ({ ok: false, message: "storage unavailable" }),
        persistStore(store, events) {
            const selected = events.filter(event => event.calendarId === store.profile.id)
            writes.push({ id: store.profile.id, uids: selected.map(event => event.uid) })
            const fail = store === destination
                ? (writes.filter(write => write.id === "destination").length === 1
                    ? destinationFailure : rollbackFailure)
                : sourceFailure
            if (fail)
                return { ok: false, message: "write failed" }
            store.rawEvents = selected
            return { ok: true }
        },
        syncedMutation() {
            throw new Error("unexpected synced mutation")
        }
    }
    const context = {
        root,
        EventMutation: {
            updateEvent(events, calendars, uid, data) {
                const moved = Object.assign({}, sourceEvent, { calendarId: "destination", title: data.title })
                return { ok: true, event: moved, rawEvents: [moved, previousDestination] }
            }
        }
    }
    vm.runInNewContext(updateSource, context)
    const result = vm.runInNewContext("updateEvent('moving', { title: 'After' })", context)
    return { result, source, destination, writes }
}

{
    const { result, source, destination, writes } = runMove({ destinationFailure: true })
    assert.equal(result.ok, false)
    assert.deepEqual(writes.map(write => write.id), ["destination"])
    assert.equal(source.rawEvents[0].uid, "moving")
    assert.equal(destination.rawEvents[0].uid, "existing")
}

{
    const { result, source, destination, writes } = runMove({ sourceFailure: true })
    assert.equal(result.ok, false)
    assert.deepEqual(writes.map(write => write.id), ["destination", "source", "destination"])
    assert.equal(source.rawEvents[0].uid, "moving")
    assert.equal(destination.rawEvents[0].uid, "existing")
}

{
    const { result, writes } = runMove({ sourceFailure: true, rollbackFailure: true })
    assert.equal(result.ok, false)
    assert.match(result.message, /destination rollback failed/)
    assert.deepEqual(writes.map(write => write.id), ["destination", "source", "destination"])
}

console.log("Local event move tests passed")
