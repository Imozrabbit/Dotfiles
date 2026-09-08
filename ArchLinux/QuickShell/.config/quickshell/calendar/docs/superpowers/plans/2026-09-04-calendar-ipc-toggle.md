# Calendar IPC Toggle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let Hyprland toggle the persistent calendar window through Quickshell IPC.

**Architecture:** Start `CalendarWindow` hidden and expose one typed `IpcHandler.toggle()` function from `shell.qml`. Toggle only window visibility, requesting activation when showing, so all calendar and editor state remains in memory.

**Tech Stack:** Quickshell 0.3.0, Qt 6 QML, Quickshell.Io `IpcHandler`, `qs ipc`, Hyprland.

## Global Constraints

- Keep calendar Quickshell process running while window is hidden.
- Start window hidden.
- Preserve view, date, zoom, details, editor, and unsaved draft state.
- Expose only IPC target `calendar` function `toggle(): bool`.
- Add no process start fallback, Hyprland API dependency, reset command, polling, timer, or subprocess.
- Do not edit Hyprland configuration; user owns binding and `exec-once` entries.
- Do not commit unless user explicitly requests a commit.

---

### Task 1: Hidden Window And IPC Toggle

**Files:**
- Modify: `ui/CalendarWindow.qml:21`
- Modify: `shell.qml:1-13`
- Modify: `implementation-plan.md`

**Interfaces:**
- Produces: IPC target `calendar` with `toggle(): bool`.
- Consumes: `CalendarWindow.visible` and inherited `requestActivate()`.

- [x] **Step 1: Start the calendar hidden**

Change `ui/CalendarWindow.qml`:

```qml
visible: false
```

- [x] **Step 2: Add IPC handler and window ID**

Change `shell.qml` to:

```qml
import Quickshell
import Quickshell.Io
import "services"
import "ui"

ShellRoot {
    CalendarService {
        id: calendarService
    }

    CalendarWindow {
        id: calendarWindow
        calendarService: calendarService
    }

    IpcHandler {
        target: "calendar"

        function toggle(): bool {
            calendarWindow.visible = !calendarWindow.visible;
            if (calendarWindow.visible)
                calendarWindow.requestActivate();
            return calendarWindow.visible;
        }
    }
}
```

- [x] **Step 3: Record IPC toggle in canonical ledger**

Append `Stage 7: Calendar IPC Toggle` to `implementation-plan.md`, recording
hidden startup, persistent process, preserved state, target/function contract,
startup command, toggle command, static verification, and pending manual
acceptance.

- [x] **Step 4: Run static verification**

Run:

```bash
qmllint -U shell.qml ui/CalendarWindow.qml
TZ=Europe/Paris node tests/test-event-mutation.js
TZ=Europe/Paris node tests/test-calendar-math.js
node tests/test-zoom.js
```

Expected: JavaScript suites print success. `qmllint` exits 0; unresolved
external Quickshell types may produce the repository's known standalone import
warnings, but no syntax or local-property errors.

- [ ] **Step 5: Ask user to perform runtime acceptance**

User starts persistent config once:

```bash
qs -c calendar -d
```

Confirm registration:

```bash
qs -c calendar ipc show
```

Expected target entry:

```text
target calendar
  function toggle(): bool
```

Call twice:

```bash
qs -c calendar ipc call calendar toggle
qs -c calendar ipc call calendar toggle
```

Expected first result `true` and visible focused calendar; second result `false`
and hidden calendar. Reopen after navigating or editing and confirm state remains.

Hyprland entries remain user-owned:

```ini
exec-once = qs -c calendar -d
bind = <user modifiers>, <user key>, exec, qs -c calendar ipc call calendar toggle
```
