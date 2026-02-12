AGENTS.md

Purpose
- This repository contains Quickshell QML configuration for several OSDs.
- Treat it as runtime QML, not a compiled app.
- Keep implementations minimal, lightweight, and simple; these widgets run continuously and must be extremely light on system resources.

Repository map
- clock/: desktop clock OSD (ShellRoot + PanelWindow)
- ram-osd/: RAM dotted bar (ShellRoot + DottedBar + Mem singleton)
- system-osd/: CPU/GPU monitor (Scope + HWInfoProvider + Gauge/Stat/Sparkline)
- volume-osd/: volume OSD (Scope + Pipewire + LazyLoader)

Build / lint / test
- No build system or test runner is configured in this repo.
- No lint config found; QML tooling is limited to editor tooling.

How to run locally (manual)
- These files are Quickshell configs; load the directory you want.
- Example (manual): `quickshell -c /home/Zrabbit/.config/quickshell/clock`
- Example (manual): `quickshell -c /home/Zrabbit/.config/quickshell/ram-osd`
- Example (manual): `quickshell -c /home/Zrabbit/.config/quickshell/system-osd`
- Example (manual): `quickshell -c /home/Zrabbit/.config/quickshell/volume-osd`

Single test
- No automated tests exist; there is no single-test command.

Cursor / Copilot rules
- No .cursor/rules, .cursorrules, or .github/copilot-instructions.md found.

General QML style
- Keep `pragma` directives at the top of the file.
- Keep imports grouped at the top, one import per line.
- Prefer `pragma ComponentBehavior: Bound` where existing files use it.
- Use 4-space indentation; align braces on the same line as the item.
- Keep blocks short and grouped with section comments when the file is long.
- Prefer explicit `property <type> <name>` with initial values.
- Prefer `required property` for external inputs like `modelData` in `Variants`.

Imports
- Use minimal imports needed for the file.
- Typical ordering (match existing files when editing):
  - QtQuick / QtQuick.Layouts / QtQuick.Shapes
  - Quickshell / Quickshell.Io / Quickshell.Services.Pipewire / Quickshell.Widgets / Quickshell.Wayland
- Avoid wildcard imports or JavaScript `import` statements.

Component and id naming
- QML component type names are PascalCase (e.g., `PanelWindow`, `Gauge`).
- `id` values are lowerCamelCase (e.g., `root`, `clockCol`, `hideTimer`).
- Properties are lowerCamelCase.
- Use descriptive ids for layout containers (`clockCol`, `dateCol`, `boxes`).

Properties and bindings
- Keep derived values as `readonly property` when they should not be set.
- Clamp normalized values with `Math.max(0, Math.min(1, value))`.
- Prefer binding expressions over imperative setters unless stateful.
- Use `implicitWidth/implicitHeight` to wrap content when possible.

Anchors and layouts
- Prefer `anchors {}` and `margins {}` blocks for clarity.
- Use `RowLayout`/`ColumnLayout` where spacing is important.
- Avoid magic numbers when a property can express intent (e.g., `size`, `gap`).

Color and typography
- Colors are expressed as hex strings with alpha when needed.
- Fonts are explicit and non-default; keep font families consistent with nearby usage.
- Use `font.pixelSize` over point size for pixel-precise UI.

JavaScript in QML
- Use `const`/`let` in inline JS blocks for clarity.
- Keep JS helpers near their usage (e.g., `_min`, `_max`).
- Guard against bad input with `isNaN` / `isFinite` and early returns.
- Prefer small, pure functions; avoid global side effects.

Process / IO patterns
- `Process` is used to read from `/proc` and `/sys` or system tools.
- Always validate and sanitize outputs before using them.
- Handle missing data by returning early and keeping prior values.
- Use `Timer` with `repeat: true` to poll, and set `Process.running = true`.
- Keep commands simple; avoid shell where direct reads are possible.

State handling
- For transient UI like OSDs, use `LazyLoader` to avoid persistent windows.
- Use `Connections` for signals and set flags to show/hide.
- Use a `Timer` to auto-hide OSDs after a short interval.

Error handling
- Check numeric parsing with `Number(...)` and `isNaN`.
- Clamp ranges and guard against divide-by-zero.
- Prefer no-op on invalid data instead of throwing.
- Keep user-visible strings stable even when data is missing.

Performance
- Avoid heavy allocations in tight timers; reuse arrays when possible.
- Keep sample arrays bounded with a max length.
- Use simple shapes (`Rectangle`, `Shape`) and `Canvas` for sparklines.

Formatting and layout consistency
- Keep section separators as `// --------------------` when used.
- Keep comment headers aligned and consistent within a file.
- Preserve existing spacing and alignment in the file you touch.

Project-specific conventions observed
- `ShellRoot` is used for standalone screen-specific OSDs.
- `Scope` is used for shared or service-based components.
- `Variants { model: Quickshell.screens }` with `PanelWindow` per screen.
- Screen targeting uses `visible: (modelData.name === targetScreenName)`.
- Use `color: "transparent"` for OSD windows with content-only visuals.
- Make windows non-blocking: `exclusiveZone: 0`, `focusable: false`, `mask: Region {}`.

When adding new files
- Match the folder that matches the feature (clock, ram-osd, system-osd, volume-osd).
- Add a `.qmlls.ini` only if necessary for tooling; keep it simple.
- Use ASCII-only content unless the file already includes Unicode symbols.

When editing existing files
- Preserve existing visual design choices and font selections.
- Keep QML item hierarchy stable unless redesign is intended.
- Avoid reformatting unrelated sections; focus on the change.

If you need to introduce new dependencies
- Prefer existing Quickshell or QtQuick modules already in use.
- Document the reason and update this file if commands change.
