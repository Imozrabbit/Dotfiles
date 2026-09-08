# Calendar IPC Toggle Design

## Goal

Let a Hyprland keyboard binding show and hide the calendar through Quickshell
IPC while keeping the calendar process alive and preserving UI state.

## Lifecycle

The calendar process starts once at login with:

```bash
qs -c calendar -d
```

`CalendarWindow` starts hidden. Hiding the window does not terminate Quickshell
or reset view, date, zoom, details, editor, or unsaved draft state. Existing
visibility-bound timers stop while hidden.

No start-on-demand or process-kill fallback is added. Hyprland `exec-once` owns
process startup.

## IPC Contract

`shell.qml` registers one `IpcHandler` with target `calendar` and one explicitly
typed function:

```qml
function toggle(): bool
```

The function flips `CalendarWindow.visible`, requests activation when showing,
and returns the resulting visibility. The command used by Hyprland is:

```bash
qs -c calendar ipc call calendar toggle
```

Only `toggle` is exposed. Separate show, hide, reset, or status commands are not
needed for the requested behavior.

## Failure Behavior

If the calendar process is not running, `qs ipc` fails normally and does not
start another process. If the compositor refuses activation, the window still
becomes visible; compositor-specific focus scripting remains outside this
change.

## Verification

Targeted `qmllint` covers `shell.qml` and `CalendarWindow.qml`. Runtime checks
confirm the IPC target appears in `qs -c calendar ipc show`, first call shows
and focuses the window, second call hides it, and state survives a hide/show
cycle.
