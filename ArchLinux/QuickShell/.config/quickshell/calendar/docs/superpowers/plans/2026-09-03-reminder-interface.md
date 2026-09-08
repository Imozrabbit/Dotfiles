# Reminder Interface Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add validated multi-reminder editing while leaving scheduling and notification execution outside QML.

**Architecture:** `EventMutation.js` canonicalizes imported reminder metadata and strictly validates mutation input. `EventEditorPanel.qml` owns reminder draft state and sends canonical arrays through existing CalendarService create/update methods; no new service, process, transport, timer, or view dependency is introduced.

**Tech Stack:** Qt 6 QML, QtQuick.Controls, QtQuick.Layouts, JavaScript, Node assert tests

## Global Constraints

- Future native helper owns reminder scheduling and notification delivery.
- Add no scheduler, Timer, polling, daemon, subprocess, `notify-send`, helper transport, ICS write, or pimsync integration.
- Preserve read-only rules, editor input on failure, session-only mutations, and existing Details fallback output.
- Use `RowLayout` and `ColumnLayout` for new layout containers.
- Do not commit unless user explicitly requests it.
- User performs runtime smoke test unless assistant execution is requested.

---

### Task 1: Reminder Mutation Contract

**Files:**
- Modify: `tests/test-event-mutation.js`
- Modify: `common/EventMutation.js`

- [x] Add failing assertions for imported filtering, supplied create reminders, replacement update, omitted update preservation, duplicate rejection, malformed rejection, and defensive copies.
- [x] Run `TZ=Europe/Paris node tests/test-event-mutation.js`; verify expected reminder assertions fail.
- [x] Add canonical reminder copying/filtering and strict mutation validation with field `reminders`.
- [x] Run `TZ=Europe/Paris node tests/test-event-mutation.js`; verify pass.

### Task 2: Reminder Labels And Editor Draft

**Files:**
- Modify: `tests/test-calendar-math.js`
- Modify: `common/CalendarMath.js`
- Modify: `ui/EventEditorPanel.qml`

- [x] Add failing direct reminder-label assertions for 0, 1, 15, 60, and 1440 minutes.
- [x] Export one `reminderLabel(minutesBefore)` helper and reuse it in `eventDetails()`.
- [x] Add editor reminder draft state, presets, add/remove/custom validation helpers, edit loading, and save payload.
- [x] Add REMINDERS form section using Layout containers, removable rows, preset ComboBox, custom whole-minute input, Add action, and one inline error.
- [x] Run CalendarMath and EventMutation suites plus `qmllint -U ui/EventEditorPanel.qml services/CalendarService.qml`.

### Task 3: Stage Gate

**Files:**
- Modify: `implementation-plan.md`

- [x] Record Stage 5 ownership, data contract, implementation, prohibited runtime work, and static verification.
- [x] Run all three Node suites and targeted QML lint.
- [x] Review changed code for validation bypasses, mutable aliases, data loss, and accidental scheduling behavior.
- [ ] Ask user to manually verify preset/custom add, duplicate/invalid handling, remove, cancel, create/edit Details output, read-only behavior, and restart reset.
