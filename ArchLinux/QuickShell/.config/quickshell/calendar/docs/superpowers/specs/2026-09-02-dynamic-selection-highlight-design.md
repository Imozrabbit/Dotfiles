# Dynamic Selection Highlight Design

## Goal

Replace fixed mint event selection with a clear but restrained highlight derived
from each event's own color across Week, Month, and Agenda views.

## Presentation

- Derive selected color with `Qt.lighter(eventColor, 1.18)`.
- Use selected color at `0.28` opacity for card fill.
- Use selected color at `0.72` opacity for border so it remains subdued.
- Use solid selected color for left ribbon where present.
- Keep unselected styling unchanged.
- Remove `Theme.selection` after all consumers are replaced.

## Scope

- Update `ui/EventCard.qml` for Week cards.
- Update direct event delegates in `ui/MonthView.qml` and `ui/AgendaView.qml`.
- Update `common/Theme.js` only to remove unused fixed selection color.
- Preserve card geometry, text, event interaction, UID selection behavior, and
  multi-day segment highlighting.

## Verification

- Run `qmllint -U` on all changed QML files.
- Run CalendarMath, EventMutation, and Zoom Node test suites.
- Manually compare selected blue and purple events in Week, Month, and Agenda.
- Confirm selection is obvious without an overly bright border and unselected
  cards remain unchanged.
