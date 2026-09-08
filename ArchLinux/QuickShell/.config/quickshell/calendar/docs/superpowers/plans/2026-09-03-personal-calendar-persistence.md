# Personal Calendar Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist Personal calendar create, edit, delete, and reminder changes in `~/.local/share/calendar/personal.json` across Quickshell sessions.

**Architecture:** Extend the existing pure event boundary with strict version-1 Personal store parsing and serialization. Add one `FileView`-backed QML store that performs atomic blocking writes, then route existing `CalendarService` mutations through it while keeping read-only source fixtures separate.

**Tech Stack:** Quickshell 0.3.0, Qt 6 QML, Quickshell.Io `FileView`, JavaScript, Node.js `node:assert/strict`, `qmllint`.

## Global Constraints

- Store runtime data only at `~/.local/share/calendar/personal.json`.
- Missing file starts empty; no Personal mock fixture migration.
- Existing malformed or invalid data is never overwritten automatically.
- Calendar is sole writer; load once at startup and add no file watcher.
- Every successful mutation is persisted immediately with an atomic write.
- A failed write leaves published in-memory events unchanged.
- Keep `CalendarService` as the only UI-facing event boundary.
- Add no dependency, subprocess, helper, timer, polling, ICS handling, pimsync integration, recurrence, notification scheduling, or backup system.
- Do not commit unless the user explicitly requests a commit.

---

### Task 1: Versioned Personal Store Codec

**Files:**
- Modify: `common/EventMutation.js`
- Modify: `tests/test-event-mutation.js`

**Interfaces:**
- Consumes: Existing `validateEvent(eventData, calendars, uid)` and `canonicalRaw(event, source, preserved)` internals.
- Produces: `parsePersonalStore(text, calendars, reservedUids) -> { ok, rawEvents } | { ok: false, field: "storage", message }`.
- Produces: `serializePersonalStore(rawEvents, calendars, reservedUids) -> { ok, rawEvents, text } | { ok: false, field: "storage", message }`.

- [x] **Step 1: Add failing store-contract tests**

Append tests before the final success log in `tests/test-event-mutation.js`. Use one canonical event and assert empty parsing, canonical round-trip, malformed JSON rejection, unsupported version rejection, wrong calendar rejection, duplicate UID rejection, invalid event rejection, and derived-field rejection:

```js
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

assert.equal(EventMutation.parsePersonalStore(
    JSON.stringify({ version: 1, events: [storedEvent] }),
    calendars, [storedEvent.uid]).ok, false)
```

- [x] **Step 2: Run tests and verify red state**

Run:

```bash
TZ=Europe/Paris node tests/test-event-mutation.js
```

Expected: failure because `parsePersonalStore` or `serializePersonalStore` is not defined.

- [x] **Step 3: Implement strict canonical validation**

Add these private helpers after `canonicalRaw` in `common/EventMutation.js`:

```js
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
```

- [x] **Step 4: Implement parse and serialize functions**

Add public functions after the helpers:

```js
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
```

Export both functions in the existing `module.exports` object:

```js
parsePersonalStore,
serializePersonalStore,
```

- [x] **Step 5: Run codec and existing JavaScript checks**

Run:

```bash
TZ=Europe/Paris node tests/test-event-mutation.js
TZ=Europe/Paris node tests/test-calendar-math.js
node tests/test-zoom.js
```

Expected: all three success messages and exit status 0.

---

### Task 2: Atomic Personal Calendar File Store

**Files:**
- Create: `services/PersonalCalendarStore.qml`

**Interfaces:**
- Consumes: Required `calendars` array and `EventMutation.parsePersonalStore` / `serializePersonalStore`.
- Produces: `rawEvents: var`, `ready: bool`, `errorMessage: string`.
- Produces: `persist(candidate) -> { ok: true } | { ok: false, field: "storage", message }`.

- [x] **Step 1: Create the QML store with explicit state**

Create `services/PersonalCalendarStore.qml`:

```qml
import QtQuick
import Quickshell
import Quickshell.Io
import "../common/EventMutation.js" as EventMutation

QtObject {
    id: root

    required property var calendars
    required property var reservedUids
    readonly property string filePath: {
        const home = Quickshell.env("HOME");
        return home ? home + "/.local/share/calendar/personal.json" : "";
    }
    property var rawEvents: []
    property bool ready: false
    property string errorMessage: ""
    property bool writeFinished: false
    property string writeError: ""

    function failure(message) {
        return { ok: false, field: "storage", message };
    }

    function protect(message) {
        root.ready = false;
        root.rawEvents = [];
        root.errorMessage = message;
        console.error("Personal calendar: " + message);
    }

    function loadText(text) {
        const result = EventMutation.parsePersonalStore(
            text, root.calendars, root.reservedUids);
        if (!result.ok) {
            root.protect(result.message);
            return;
        }
        root.rawEvents = result.rawEvents;
        root.errorMessage = "";
        root.ready = true;
    }

    function writeCandidate(candidate) {
        const result = EventMutation.serializePersonalStore(
            candidate, root.calendars, root.reservedUids);
        if (!result.ok)
            return result;

        root.writeFinished = false;
        root.writeError = "";
        personalFile.setText(result.text);
        if (!root.writeFinished)
            return root.failure("Personal calendar write did not complete");
        if (root.writeError.length > 0)
            return root.failure(root.writeError);

        root.rawEvents = result.rawEvents;
        root.errorMessage = "";
        return { ok: true };
    }

    function initializeEmpty() {
        const result = root.writeCandidate([]);
        if (result.ok)
            root.ready = true;
        else
            root.protect(result.message);
    }

    function persist(candidate) {
        if (!root.ready)
            return root.failure(root.errorMessage.length > 0
                ? root.errorMessage : "Personal calendar is not ready");
        return root.writeCandidate(candidate);
    }

    Component.onCompleted: {
        if (root.filePath.length === 0)
            root.protect("HOME is not available");
    }

    property FileView personalFile: FileView {
        path: root.filePath
        preload: true
        atomicWrites: true
        blockWrites: true
        watchChanges: false

        onLoaded: root.loadText(text())
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound)
                root.initializeEmpty();
            else
                root.protect("Could not load personal.json: "
                    + FileViewError.toString(error));
        }
        onSaved: {
            root.writeFinished = true;
            root.writeError = "";
        }
        onSaveFailed: error => {
            root.writeFinished = true;
            root.writeError = "Could not save personal.json: "
                + FileViewError.toString(error);
        }
    }
}
```

- [x] **Step 2: Run targeted QML lint**

Run:

```bash
qmllint -U services/PersonalCalendarStore.qml
```

Expected: exit status 0 with no diagnostics. If installed Quickshell signal names or enum syntax differ, adjust only to Quickshell 0.3.0 documented API, then rerun.

---

### Task 3: Route Calendar Mutations Through Storage

**Files:**
- Modify: `services/CalendarService.qml`
- Modify: `implementation-plan.md`

**Interfaces:**
- Consumes: `PersonalCalendarStore.rawEvents`, `.ready`, and `.persist(candidate)`.
- Preserves: Existing `CalendarService` methods and result objects consumed by `CalendarWindow`, `EventEditorPanel`, and `EventDetailsPanel`.

- [x] **Step 1: Add store and split source events from Personal events**

In `CalendarService.qml`, instantiate the store after `sourceCalendars`:

```qml
property PersonalCalendarStore personalStore: PersonalCalendarStore {
    calendars: root.sourceCalendars
    reservedUids: root.sourceEvents.map(event => event.uid)
}
```

Rename the current mutable `rawEvents` fixture property to
`readonly property var sourceEvents`. Remove every fixture whose
`calendarId` is `personal`, including malformed and month/crowding fixtures.
Then add the merged binding:

```qml
readonly property var rawEvents: root.sourceEvents.concat(personalStore.rawEvents)
```

Keep the current `events` normalization binding unchanged so it consumes the
merged `rawEvents` list.

- [x] **Step 2: Replace session counters with stable opaque UIDs**

Delete `nextMockUid`. Replace `availableUid()` with:

```qml
function availableUid() {
    let uid;
    do {
        uid = Date.now().toString(36) + "-"
            + Math.random().toString(36).slice(2)
            + "@quickshell-calendar";
    } while (root.rawEvents.some(event => event.uid === uid));
    return uid;
}
```

Do not increment any counter after creation. The generated UID is stored once
and preserved by existing updates.

- [x] **Step 3: Persist candidates before publishing success**

In each mutation, keep `EventMutation` as validator, filter its candidate down
to Personal events, and persist before returning success.

Create:

```qml
function createEvent(eventData) {
    const result = EventMutation.createEvent(
        root.rawEvents, root.sourceCalendars, eventData, root.availableUid());
    if (!result.ok)
        return result;
    const saved = personalStore.persist(result.rawEvents.filter(
        event => event.calendarId === "personal"));
    if (!saved.ok)
        return saved;
    return { ok: true, event: result.event };
}
```

Update:

```qml
function updateEvent(uid, eventData) {
    const result = EventMutation.updateEvent(
        root.rawEvents, root.sourceCalendars, uid, eventData);
    if (!result.ok)
        return result;
    const saved = personalStore.persist(result.rawEvents.filter(
        event => event.calendarId === "personal"));
    if (!saved.ok)
        return saved;
    return { ok: true, event: result.event };
}
```

Delete:

```qml
function deleteEvent(uid) {
    const result = EventMutation.deleteEvent(
        root.rawEvents, root.sourceCalendars, uid);
    if (!result.ok)
        return result;
    const saved = personalStore.persist(result.rawEvents.filter(
        event => event.calendarId === "personal"));
    if (!saved.ok)
        return saved;
    return { ok: true, uid: result.uid };
}
```

- [x] **Step 4: Add persistence stage to canonical ledger**

Append a `Stage 6: Personal Calendar Persistence` section to
`implementation-plan.md`. Record approved storage path, version-1 schema,
strict protected-file behavior, immediate atomic writes, sole-writer rule,
future ICS-export boundary, automated checks, and pending manual acceptance.

- [x] **Step 5: Run complete static gate**

Run:

```bash
TZ=Europe/Paris node tests/test-event-mutation.js
TZ=Europe/Paris node tests/test-calendar-math.js
node tests/test-zoom.js
qmllint -U services/PersonalCalendarStore.qml services/CalendarService.qml ui/EventEditorPanel.qml ui/EventDetailsPanel.qml ui/CalendarWindow.qml
```

Expected: three JavaScript success messages, no QML diagnostics, exit status 0.

---

### Task 4: Runtime Persistence Acceptance

**Files:**
- Modify after acceptance: `implementation-plan.md`
- Runtime data created by Quickshell: `~/.local/share/calendar/personal.json`

**Interfaces:**
- Verifies: Startup initialization, durable mutations, malformed-file protection, and read-only behavior.

- [ ] **Step 1: Ask who performs runtime test**

Per project policy, ask whether the user will test manually or wants the
assistant to run only this config with:

```bash
quickshell -c /home/Zrabbit/Documents/Dotfiles/ArchLinux/QuickShell/.config/quickshell/calendar
```

- [ ] **Step 2: Verify first-run initialization**

With no existing `personal.json`, launch calendar and confirm file content is:

```json
{
  "version": 1,
  "events": []
}
```

Confirm Personal mock events are absent and University source fixtures remain.

- [ ] **Step 3: Verify durable create, edit, reminders, and delete**

Create one timed Personal event with a reminder. Close and restart Quickshell;
confirm event and reminder remain. Edit title and time, restart, and confirm new
values remain. Delete event, restart, and confirm it remains deleted.

- [ ] **Step 4: Verify malformed-file protection**

Stop Quickshell, preserve a copy of `personal.json`, replace its content with
`{`, and relaunch. Confirm no Personal events load, mutations return a storage
error, and malformed file remains exactly `{`. Restore valid file afterward.

- [ ] **Step 5: Verify read-only source behavior and logs**

Open University source events from Week, Month, and Agenda. Confirm Details
remains read-only and no mutation path appears. Inspect Quickshell output for
new warnings or uncaught exceptions.

- [ ] **Step 6: Record acceptance**

After all manual checks pass, mark Stage 6 runtime acceptance complete in
`implementation-plan.md`. Leave previous Stage 5 reminder checkbox unchanged
unless its full manual checklist was also explicitly confirmed.
