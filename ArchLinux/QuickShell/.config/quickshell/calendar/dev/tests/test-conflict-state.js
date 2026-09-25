const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

const service = fs.readFileSync(path.join(__dirname, "../../services/CalendarConflictService.qml"), "utf8")
const start = service.indexOf("    function loadState(text)")
const end = service.indexOf("    function choose(side)", start)
const root = { conflicts: [], errorMessage: "", stateValid: false }
const context = { root }
vm.runInNewContext(service.slice(start, end), context)

context.loadState(JSON.stringify({ version: 1, conflicts: [] }))
assert.equal(root.conflicts.length, 0)
assert.equal(root.errorMessage, "")
assert.equal(root.stateValid, true)

const conflict = {
    uid: "event-1",
    local: { title: "Local" },
    remote: { title: "Remote" },
    localIcs: "BEGIN:VCALENDAR",
    remoteIcs: "BEGIN:VCALENDAR",
    choice: ""
}
context.loadState(JSON.stringify({ version: 1, conflicts: [conflict] }))
assert.equal(root.conflicts[0].uid, "event-1")
assert.equal(root.errorMessage, "")
assert.equal(root.stateValid, true)

for (const invalid of [
    { version: 2, conflicts: [] },
    { version: 1, conflicts: [Object.assign({}, conflict, { remoteIcs: null })] },
    { version: 1, conflicts: [Object.assign({}, conflict, { choice: "both" })] },
    { version: 1, conflicts: [null] }
]) {
    context.loadState(JSON.stringify(invalid))
    assert.equal(root.conflicts[0].uid, "event-1")
    assert.equal(root.errorMessage, "Could not read calendar conflict state")
    assert.equal(root.stateValid, false)
}

const calendarService = fs.readFileSync(path.join(__dirname, "../../services/CalendarService.qml"), "utf8")
const mutationStart = calendarService.indexOf("    function syncedMutation(")
const mutationEnd = calendarService.indexOf("    function createEvent(", mutationStart)
const mutationContext = { root: { conflictService: { stateValid: false } }, syncProcess: { running: false } }
vm.runInNewContext(calendarService.slice(mutationStart, mutationEnd), mutationContext)
const blocked = mutationContext.syncedMutation("create", "", { calendarId: "personal" })
assert.equal(blocked.ok, false)
assert.equal(blocked.field, "storage")

const panel = fs.readFileSync(path.join(__dirname, "../../ui/ConflictResolutionPanel.qml"), "utf8")
const handlerStart = panel.indexOf("        function onConflictsChanged()")
const handlerEnd = panel.indexOf("        function onErrorMessageChanged()", handlerStart)
assert.ok(handlerStart >= 0 && handlerEnd > handlerStart)
const panelRoot = {
    conflict: { uid: "next", localIcs: "local", remoteIcs: "remote" },
    selectedUid: "previous",
    selectedLocalIcs: "local",
    selectedRemoteIcs: "remote",
    selectedSide: "local",
    confirmPending: true,
    conflictService: { hasConflict: true },
    closeRequested() { throw new Error("Next conflict must remain open") }
}
const panelContext = { root: panelRoot }
vm.runInNewContext(panel.slice(handlerStart, handlerEnd), panelContext)
panelContext.onConflictsChanged()
assert.equal(panelRoot.selectedUid, "next")
assert.equal(panelRoot.selectedSide, "")
assert.equal(panelRoot.confirmPending, false)
panelRoot.selectedSide = "remote"
panelRoot.confirmPending = true
panelContext.onConflictsChanged()
assert.equal(panelRoot.selectedSide, "remote")
assert.equal(panelRoot.confirmPending, true)
panelRoot.conflict = { uid: "next", localIcs: "local", remoteIcs: "remote-updated" }
panelContext.onConflictsChanged()
assert.equal(panelRoot.selectedSide, "")
assert.equal(panelRoot.confirmPending, false)

const confirmStart = panel.indexOf("    function confirmChoice(")
const confirmEnd = panel.indexOf("    function cancelChoice(", confirmStart)
let chooseCalls = 0
const invalidRoot = {
    selectedSide: "local", confirmPending: false,
    conflictService: { busy: false, stateValid: false, choose() { chooseCalls++ } }
}
const invalidContext = { root: invalidRoot }
vm.runInNewContext(panel.slice(confirmStart, confirmEnd), invalidContext)
invalidContext.confirmChoice()
assert.equal(invalidRoot.confirmPending, false)
assert.equal(chooseCalls, 0)

console.log("Conflict state tests passed")
