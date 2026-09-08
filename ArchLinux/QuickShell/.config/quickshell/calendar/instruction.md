# Calendar Quickshell Execution Specification

## Purpose

Build `calendar` as a standalone Quickshell configuration with its own
`shell.qml`. It must be directly runnable with:

```sh
quickshell -c /home/Zrabbit/Documents/Dotfiles/ArchLinux/QuickShell/.config/quickshell/calendar
```

The primary use case is a university timetable. Week View has highest priority.

This directory currently contains no calendar implementation or existing UI
component library. Do not describe it as an existing calendar frontend and do
not depend on sibling Quickshell configurations unless the user explicitly
expands project scope.

## Source Of Truth And Stage Discipline

This file is the implementation contract. Work only on the currently approved
stage. Do not begin a later stage, perform broad rewrites, or modify unrelated
Quickshell configurations.

At the end of every stage:

1. Report exact DankCalendar files used as references.
2. Report exact local files added, changed, or removed.
3. Explain substantial adaptations and extracted algorithms.
4. List Dank-specific dependencies removed or avoided.
5. List mocked behavior and known limitations.
6. Report static and runtime verification performed, including failures.
7. Stop and obtain approval before starting the next stage.

## Donor Project

Use DankCalendar as the primary donor/reference implementation:

<https://github.com/AvengeMedia/dankcalendar>

Inspect its Quickshell frontend in detail, including:

- `quickshell/Modules/`
- `quickshell/Modals/`
- `quickshell/Services/`
- `quickshell/Widgets/`
- `quickshell/Common/`
- `quickshell/tests/`
- `quickshell/shell.qml`

Before copying or adapting code, record the full upstream commit SHA and use
commit-pinned source links in stage reports. Do not treat mutable `master` as a
stable reference.

Reuse proven calendar behavior and layout logic where useful, especially:

- week/day event positioning
- overlap grouping and column layout
- month event layout
- all-day and multi-day event handling
- date navigation
- current-time positioning
- event details and editor interaction patterns
- calendar selection and visibility behavior

Do not blindly copy DankCalendar's `quickshell/` directory or application
architecture. Transplant the minimum code that survives removal of Dank-only
services and components.

### License Requirements

DankCalendar is MIT licensed:

```text
Copyright (c) 2025-2026 Avenge Media LLC
```

When substantial upstream code is copied or adapted:

1. Add the complete DankCalendar MIT license text under a local third-party
   license file.
2. Record the upstream repository, commit SHA, and original file path.
3. Preserve existing copyright or license headers.
4. Distinguish copied/adapted code from independently implemented code in the
   stage report.

Small behavioral ideas or independently reimplemented algorithms still require
source attribution in the stage report, but not misleading copied-code claims.

## Required Architecture

Data flow:

```text
remote calendars
      |
   pimsync
      |
local vdir calendars
      |
    *.ics
      |
native calendar helper (implemented separately)
      |
CalendarService.qml
      |
Quickshell views
```

Quickshell owns presentation and user interaction only. All views consume data
through `CalendarService.qml` or a service-owned model. Views must not:

- parse or write ICS
- scan calendar directories
- access or invoke pimsync
- implement synchronization
- know about CalDAV, WebCal, OAuth, or remote providers
- call the future helper directly
- launch backend or notification processes

The future helper transport is deliberately unspecified. Keep it behind
`CalendarService`; do not design a speculative transport in frontend code.

## Prohibited DankCalendar Dependencies

Do not copy, invoke, or depend on DankCalendar's:

- Go `dcal` daemon or CLI
- database or Ent ORM
- HTTP API or IPC contract
- account management
- CalDAV, Google, Microsoft, or iCloud synchronization
- OAuth code or credentials
- backend synchronization engine
- backend notification daemon
- tray-daemon architecture
- `DankCommon` or `dank-qml-common` as wholesale dependencies
- DankMaterialShell runtime services or theme objects

Do not add a dependency merely because DankCalendar uses it. Any new runtime
dependency requires explicit user approval.

## Visual Direction

Create an original, dark-mode-friendly visual system informed by DankCalendar's
information hierarchy, not a DankMaterialShell clone.

Use local QML primitives and minimal local components. Prefer:

- near-black or dark neutral backgrounds with subtle surface separation
- restrained borders and shadows
- low-saturation chrome with calendar colors reserved for event identity
- clear typography and readable contrast
- visible keyboard focus and selected states
- compact spacing suitable for a dense university timetable
- minimal animation that does not obscure state changes

Avoid importing Dank-specific buttons, cards, typography, colors, dialogs,
icons, animations, or theme infrastructure. Avoid decorative gradients,
excessive elevation, and visual effects that add idle cost.

## CalendarService Contract

During mocked stages, `CalendarService.qml` is the sole owner of calendar data,
visibility state, validation, range filtering, and mutation rules. Views must
not duplicate these responsibilities.

### Calendar Shape

```js
{
    id: "edt_unistra",
    name: "University",
    color: "#6f8fbf",
    writable: false,
    visible: true
}
```

Initially provide at least:

- `edt_unistra`: read-only, conceptually synchronized by pimsync from university
  WebCal
- `personal`: writable, for locally created events

### Event Shape

```js
{
    uid: "abc123",
    calendarId: "edt_unistra",
    title: "Linguistique",
    description: "",
    location: "Salle 301",
    start: "2026-09-02T09:00:00+02:00",
    end: "2026-09-02T11:00:00+02:00",
    allDay: false,
    readOnly: true,
    color: null,
    reminders: [
        { minutesBefore: 15 }
    ]
}
```

Contract rules:

- `uid` and `calendarId` are required stable strings.
- Timed `start` and `end` are ISO 8601 values with explicit offsets.
- All-day `start` and `end` are local `YYYY-MM-DD` dates; `end` is exclusive.
- Every interval is half-open: `[start, end)`.
- `end` must be later than `start`.
- `title` may fall back to `Untitled`; missing description and location become
  empty strings.
- Null event color falls back to its calendar color.
- A read-only calendar makes all its events read-only. Event `readOnly` may
  further restrict an event in a writable calendar.
- Read-only events never expose edit or delete actions.
- Read-only calendars never appear as create or move destinations.
- Calendar visibility filtering belongs to the service.
- Range inclusion uses overlap semantics: event start is before range end and
  event end is after range start.
- Parse and derive date values once when data enters the service. Views consume
  service-derived values instead of repeatedly parsing unchanged timestamps.
- Invalid records are rejected or normalized before model publication. They
  must not crash a view or produce `NaN` geometry.

Expose, at minimum, service-owned calendar and event data plus operations
equivalent to:

```qml
CalendarService.calendars
CalendarService.events
CalendarService.eventsInRange(start, end)
CalendarService.setCalendarVisible(calendarId, visible)
CalendarService.createEvent(eventData)
CalendarService.updateEvent(uid, eventData)
CalendarService.deleteEvent(uid)
```

Exact QML model types may follow the smallest reliable local design. Keep the
consumer-facing behavior above stable. Mutations may remain unavailable until
Stage 4, but their eventual boundary must remain in the service.

Recurrence expansion, ICS recurrence semantics, and timezone reconciliation
belong to the future native helper. Do not implement them in QML. Mock data may
contain already-expanded occurrences when needed to exercise layouts.

## Performance Requirements

Priorities, in order:

1. Minimum idle CPU.
2. Minimum memory overhead.
3. No unnecessary daemon or subprocess.
4. Keep presentation in one calendar Quickshell process; add no companion
   daemon.
5. Event-driven updates instead of polling where possible.
6. No timer per event.
7. No repeated parsing or transformation of unchanged data.
8. No unnecessary full-model or full-view rebuilds.
9. Lazy creation of unselected heavy views when it provides measurable value.

Use at most one shared minute-level ticker for clock/current-time UI, active
only when needed. Do not introduce premature caches, workers, loaders, or
abstractions without demonstrated need.

## Error Handling

- Missing helper or future transport failure must leave stable empty or last
  valid service state.
- Malformed records must not reach geometry calculations.
- Failed mutations must preserve previous valid state and expose one clear
  failure result to the initiating UI.
- Missing optional text, color, reminder, icon, or font data must have a local
  fallback.
- Avoid repeated log spam from polling or persistent invalid data.

## Stages

### Stage 1: Donor Audit And Adaptation Plan

Do not create or modify calendar QML in this stage.

1. Inspect this project root and record its initial state.
2. Inspect the current DankCalendar Quickshell frontend at a pinned commit.
3. Trace candidate views through their services, widgets, common components,
   tests, and backend assumptions.
4. Produce a table for each useful donor file: reuse directly, adapt, extract
   algorithm only, or reject.
5. Identify every Dank-specific import, singleton, service, process, asset, and
   backend API used by selected candidates.
6. Propose the minimum local file set for Stage 2.
7. Describe which layout tests or mock cases can be retained or adapted.
8. Stop for approval.

Stage 1 succeeds only when the plan names exact upstream files and dependencies;
generic references to directories or screenshots are insufficient.

### Stage 2: Standalone Week View With Mock Service

Implement only the minimum standalone shell, local visual primitives,
`CalendarService`, Week View, and components required by Week View.

Required behavior:

- Monday-to-Sunday, 24-hour Week View
- previous week, next week, and jump-to-today navigation
- timed event cards positioned by day and time
- deterministic overlap grouping and column layout
- all-day lane
- multiple calendar colors with event override/fallback rules
- current-time indicator shown only in the current week/day
- mock university and personal calendars
- mock normal, overlapping, all-day, read-only, writable, and malformed events
- stable empty/error fallbacks

Do not implement Month View, Agenda/Day View, details, editing, persistence,
notifications, helper transport, or ICS handling in Stage 2.

Stage 2 acceptance checks:

- Config starts using the documented `quickshell -c` command.
- No unresolved QML imports, binding loops, uncaught runtime errors, or `NaN`
  geometry appear.
- Overlapping mock events remain legible and do not occupy the same column.
- Adjacent half-open events do not count as overlaps.
- All-day events do not enter timed-event geometry.
- Navigation preserves a valid selected week; Today returns to current week.
- Current-time UI uses one shared timer, not event timers.
- Invalid mock data is excluded or normalized without destabilizing valid data.
- Any action affordance introduced respects read-only rules.
- Idle operation launches no backend subprocess and performs no polling beyond
  the shared clock ticker.

### Stage 3: Additional Read-Only Views

Add, in this order unless donor analysis justifies another order:

1. Month View
2. Agenda/Day View
3. Event details
4. Calendar visibility toggles

All views must reuse `CalendarService`, navigation state where practical, and
the local visual primitives created for Week View. Do not fork event filtering
or date parsing into individual views.

Stage 3 acceptance checks:

- Month View places boundary, multi-day, and all-day mock events on correct
  dates without duplicating occurrences.
- Agenda/Day View orders events consistently and represents empty days.
- Event details show normalized title, time, calendar, location, description,
  and reminders with safe fallbacks.
- Visibility changes apply consistently to every implemented view.
- Switching views preserves a valid selected date and does not create duplicate
  timers or service models.

### Stage 4: Mocked Mutations

Add event creation, editing, and deletion against mocked `CalendarService`
operations.

Required rules:

- Only writable calendars are valid destinations.
- Read-only events expose no edit/delete action.
- Service methods revalidate permissions regardless of UI state.
- Validation failure preserves user input and identifies the invalid field.
- Delete requires explicit confirmation.
- No ICS write or helper transport is implemented yet.

Stage 4 acceptance checks:

- Create, update, and delete modify mock service state and every active view
  consistently.
- Attempts to mutate read-only events or target read-only calendars fail in the
  service even when called directly.
- Cancelling an editor or delete confirmation leaves service state unchanged.
- Invalid date ranges and missing required identifiers cannot enter the model.

### Stage 5: Reminder Interface

Define the reminder-facing service/UI boundary only after explicit approval.
The future native helper should own reminder scheduling. If temporary frontend
notification integration is approved, isolate it from views and use the
standard freedesktop notification ecosystem through `notify-send`; do not add
another notification daemon and do not create one timer per event.

Stage 5 succeeds when the boundary and ownership are explicit and verified
without adding a QML reminder scheduler. Actual notification execution requires
separate approval and a dedicated acceptance plan.

## Deferred Work

These items are explicitly outside current frontend stages unless separately
approved:

- real ICS parser or writer
- native helper implementation or transport
- pimsync configuration or invocation
- recurrence expansion
- account/provider management
- synchronization UI or engine
- OAuth or credential storage
- persistent event mutation
- reminder scheduler
- tray daemon

## Verification Procedure

For each implementation stage:

1. Run available static QML checks on changed files without adding tooling
   dependencies solely for this task.
2. Exercise deterministic mock cases for interval boundaries, overlaps,
   all-day separation, invalid records, and permission rules relevant to that
   stage.
3. Before runtime smoke testing, ask whether the user will test manually or
   wants the assistant to run it.
4. If the assistant runs it, test only this config with the documented
   `quickshell -c` command and inspect runtime output while exercising changed
   behavior.
5. Report commands, observed results, skipped checks, and remaining risks.

Do not claim a stage is complete without fresh verification evidence.
