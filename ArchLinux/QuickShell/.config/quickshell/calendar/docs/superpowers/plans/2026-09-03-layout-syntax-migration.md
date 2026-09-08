# Layout Syntax Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace eight remaining QML positioners with Layout equivalents without visual or functional changes.

**Architecture:** Keep component boundaries and absolute visual dimensions intact. Only layout ownership changes: each converted container receives equivalent `Layout.*` constraints for direct children.

**Tech Stack:** Qt 6 QML, QtQuick, QtQuick.Layouts, Quickshell

## Global Constraints

- Modify only calendar project root.
- Preserve exact styling, dimensions, spacing, interaction, and data flow.
- Add no dependencies, runtime processes, polling, persistence, or helper transport.
- Do not commit unless user explicitly requests it.
- Runtime smoke testing remains manual unless user requests assistant execution.

---

### Task 1: Small Content Stacks

**Files:**
- Modify: `ui/CalendarWindow.qml`
- Modify: `ui/EventCard.qml`

- [x] Convert legend `Column`/`Row` to `ColumnLayout`/`RowLayout`; preserve `12px` position, `8px`/`7px` spacing, dot size, and implicit legend sizing.
- [x] Convert EventCard text `Column` to `ColumnLayout`; preserve margins, top-aligned content, text widths, visibility, and wrapping.
- [x] Run `qmllint -U ui/CalendarWindow.qml ui/EventCard.qml`.

### Task 2: Week Layouts

**Files:**
- Modify: `ui/WeekView.qml`

- [x] Import `QtQuick.Layouts` and convert root `Column` to `ColumnLayout`.
- [x] Preserve `3px` spacing, `54px` header, dynamic all-day height, `3px` right inset, and grid use of remaining height.
- [x] Convert centered day-label `Column` to `ColumnLayout`; preserve text centering and zero spacing.
- [x] Run `qmllint -U ui/WeekView.qml`.

### Task 3: Editor Form Layout

**Files:**
- Modify: `ui/EventEditorPanel.qml`

- [x] Convert `formColumn` to `ColumnLayout` while preserving `20px` offsets, width, `9px` spacing, and Flickable content height.
- [x] Translate direct child widths/heights and `FieldLabel` inset to equivalent `Layout.*` constraints.
- [x] Preserve date-time row ratios, input heights, spacer heights, error text, and description height.
- [x] Run `qmllint -U ui/EventEditorPanel.qml ui/InlineWheelField.qml`.

### Task 4: Agenda Layouts And Final Gate

**Files:**
- Modify: `ui/AgendaView.qml`
- Modify: `implementation-plan.md`

- [x] Convert outer agenda `Column` and per-day event `Column` to `ColumnLayout`; preserve offsets, widths, dynamic day heights, `6px` event spacing, and empty-day height.
- [x] Record migration completion in canonical ledger.
- [x] Confirm no declarations match `^\\s*(Row|Column|Grid)\\s*\\{` in `*.qml`.
- [x] Run `qmllint -U ui/CalendarWindow.qml ui/WeekView.qml ui/EventEditorPanel.qml ui/EventCard.qml ui/AgendaView.qml`.
- [x] Run `TZ=Europe/Paris node tests/test-calendar-math.js`, `TZ=Europe/Paris node tests/test-event-mutation.js`, and `node tests/test-zoom.js`.
- [ ] Ask user to manually verify Week, Agenda, editor scrolling, event cards, and legend geometry.
