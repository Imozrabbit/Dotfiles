# Layout Syntax Migration Design

## Goal

Replace every remaining `Row` and `Column` positioner with `RowLayout` or
`ColumnLayout` without changing geometry, styling, interaction, or data flow.
No `Grid` positioners remain.

## Scope

Eight positioners across five files:

- `ui/CalendarWindow.qml`: legend column and calendar row
- `ui/WeekView.qml`: root vertical stack and day-label stack
- `ui/EventEditorPanel.qml`: form column
- `ui/EventCard.qml`: card text stack
- `ui/AgendaView.qml`: agenda day stack and event stack

## Approach

Import `QtQuick.Layouts` where missing. Replace positioners one component at a
time. Translate child sizing to `Layout.fillWidth`, `Layout.fillHeight`,
`Layout.preferredWidth`, `Layout.preferredHeight`, margins, and alignment only
where layout ownership requires it. Preserve all existing numeric dimensions,
spacing, anchors, clipping, dynamic heights, and scroll content calculations.

## Verification

Require zero remaining `Row`, `Column`, or `Grid` declarations and clean targeted
`qmllint`. Run all existing Node suites. User manually compares Week, Agenda,
Event cards, editor scrolling, and calendar legend against current behavior.
