# Personal Calendar Persistence Design

## Goal

Persist Personal calendar events across Quickshell sessions in
`~/.local/share/calendar/personal.json`. Keep imported calendars separate and
read-only. Preserve the existing `CalendarService` interface used by the UI.

## Scope

This change persists create, edit, delete, and reminder metadata for Personal
events. It removes current Personal mock fixtures instead of migrating them.
University mock fixtures remain until imported calendar JSON replaces them.

This change does not add file watching, live external edits, backup recovery,
ICS parsing or writing, pimsync integration, recurrence, notification
scheduling, or a native helper. The calendar is the sole writer of
`personal.json`.

## Storage Contract

The file uses a versioned calendar-level document:

```json
{
  "version": 1,
  "events": []
}
```

Each event stores only canonical source fields:

```json
{
  "uid": "stable-opaque-id",
  "calendarId": "personal",
  "title": "Project review",
  "description": "",
  "location": "",
  "start": "2026-09-03T08:30:00Z",
  "end": "2026-09-03T09:30:00Z",
  "allDay": false,
  "reminders": [
    { "minutesBefore": 15 }
  ]
}
```

Derived fields such as `startMs`, `endMs`, `readOnly`, and `color` are not
stored. Root and reminder objects reject unknown fields so later writes cannot
silently discard data. Every event must use calendar ID `personal`, pass
existing event normalization, and have a unique non-empty UID that does not
collide with a read-only source UID. Generated UIDs remain unchanged for the
event's lifetime so a future ICS exporter can use them as ICS UIDs.

## File Ownership

A dedicated `PersonalCalendarStore` owns file loading, validation, and writing.
It uses Quickshell.Io `FileView` with atomic and blocking writes. Blocking is
acceptable because the file is small and preserves the service's existing
synchronous mutation result contract.

`CalendarService` owns event behavior. It combines read-only source fixtures
with events published by `PersonalCalendarStore`, then normalizes the combined
list through the existing `EventMutation` boundary. Views continue calling only
`CalendarService.createEvent`, `updateEvent`, and `deleteEvent`.

## Startup Behavior

On startup, the store loads `personal.json` once.

- If the file is valid, its Personal events become available.
- If the file does not exist, the store atomically writes an empty version-1
  document and becomes writable.
- If the directory is unavailable or the empty-file write fails, the store
  remains unavailable and reports the error.
- If JSON syntax, root schema, version, duplicate UIDs, or any event is invalid,
  the store leaves the file untouched, publishes no Personal events, logs the
  error, and disables Personal mutations for that session.

No external-change watcher is installed. Manual file edits take effect after a
Quickshell restart.

## Mutation Flow

For create, edit, or delete:

1. `CalendarService` rejects the request unless the store is ready.
2. Existing `EventMutation` logic validates the request and computes a candidate
   Personal event array without modifying current state.
3. The store serializes `{ "version": 1, "events": candidate }` and performs an
   atomic blocking write.
4. On success, the store publishes the candidate array and the service returns
   its current success result.
5. On failure, memory and disk remain unchanged and the service returns a
   storage error for the editor or details panel to display.

Immediate write-after-change means a successful UI operation is already durable
when its panel closes.

## Future ICS Export

A later exporter may read `personal.json` and write one `<UID>.ics` file per
event into a pimsync-managed vdir. Stable UIDs make this mapping deterministic.
Bidirectional synchronization is not part of this design; remote ICS changes
would require a later reconciliation design because `personal.json` remains the
authoritative writable source.

## Verification

Pure JavaScript checks cover store schema parsing, empty documents, malformed
JSON, unsupported versions, non-Personal events, invalid events, duplicate UIDs,
and deterministic serialization input. Existing mutation, calendar math, and
zoom checks remain green. Targeted `qmllint` covers the store and service.

Manual runtime verification covers first-run file creation, create/edit/delete
persistence across Quickshell restarts, reminder persistence, write-failure
state preservation, malformed-file protection, and unchanged read-only source
behavior.
