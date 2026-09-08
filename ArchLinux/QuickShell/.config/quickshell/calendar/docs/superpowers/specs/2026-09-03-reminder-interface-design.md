# Reminder Interface Design

## Goal

Add editable event reminders while keeping reminder scheduling outside QML.
CalendarService remains sole frontend data boundary; future native helper owns
notification timing and delivery.

## Data Contract

Event reminders remain an array:

```js
[
    { minutesBefore: 15 }
]
```

`minutesBefore` must be a nonnegative safe integer. Duplicate offsets are
invalid. Mutation validation rejects malformed reminder arrays with field
`reminders` and leaves service state unchanged. Missing reminders normalize to
an empty array. Imported source events keep valid unique entries and discard
malformed or duplicate optional reminder entries without rejecting otherwise
valid events.

Create persists supplied reminders. Update replaces reminders when the caller
supplies them and preserves existing reminders when the property is omitted.
Arrays and entries are copied at service boundaries so callers cannot mutate
service state by reference.

## Editor UI

EventEditorPanel owns draft reminder state. Create starts empty; edit loads a
copy of event reminders. Saving includes the draft array in existing
create/update requests.

Add a REMINDERS section to the existing scrollable form. Current reminders are
shown as readable labels with a remove control. An add control offers these
presets:

- At start time: 0 minutes
- 5 minutes before
- 10 minutes before
- 15 minutes before
- 30 minutes before
- 1 hour before: 60 minutes
- 1 day before: 1440 minutes
- Custom

Custom input accepts nonnegative whole minutes. Adding an invalid or duplicate
offset preserves draft state and shows one inline reminder error. Removing an
entry updates only draft state. Editor Cancel leaves service state unchanged.

Reminder display uses the existing Details labels and fallback behavior. No
changes are required in Week, Month, Agenda, or EventCard.

## Ownership Boundary

QML may display and edit reminder metadata only. CalendarService validates and
publishes reminder metadata with events. Views never call a helper or launch a
notification command. Future native helper transport remains unspecified and
must sit behind CalendarService when implemented separately.

This stage adds no scheduler, Timer, polling loop, daemon, subprocess,
`notify-send`, ICS write, pimsync integration, or helper transport. Notification
execution requires separate explicit approval and acceptance plan.

## Verification

EventMutation tests cover source normalization, create persistence, update
replacement, omitted-update preservation, duplicate rejection, malformed entry
rejection, and defensive copying. Existing CalendarMath and Zoom suites remain
green. Targeted QML lint covers EventEditorPanel and CalendarService.

Manual checks cover preset add, custom add, duplicate/invalid errors, remove,
cancel, create, edit, Details display, read-only behavior, and session-only reset.
