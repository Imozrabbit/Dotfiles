# AGENTS.md

## Scope Boundary

- At the start of each new session, ask which top-level config directory should be the project root.
- After resolving symlinks, limit all reads, searches, edits, commands, and delegated work to the selected project root.
- Ask before accessing any ancestor, sibling config, or other path outside the selected project root.

## Project Structure
Independent runtime Quickshell QML configs; each top-level config has its own shell.qml.

- `alt-tab_view/`: Hyprland expose/window picker with IPC target `expose`; layouts are registered through `layouts/qmldir`.
- `bar/`: bottom bar; `shell.qml` owns services, `services/` collects/mutates state, and `widgets/` presents it. `network/README.md` documents its larger network/Wi-Fi subsystem.
- `clock/`: desktop clock pinned to one screen.
- `ram-osd/`: RAM bar backed by the `Mem` singleton and `/proc/meminfo`.
- `system-osd/`: host-specific CPU/GPU monitor built around `HWInfoProvider`.
- `volume-osd/`: transient PipeWire OSD whose window exists only while volume changes are shown.
- `wallpaper_switcher/`: Hyprland wallpaper GUI split into `core`, `services`, `ui`, `overlays`, and `animations`. Its `qs.*` imports resolve from this config root; preserve that hierarchy.
- `weather/`: Open-Meteo OSD with the service in `WeatherService.qml`.

## Run And Verify

- There is no build system, formatter, code generation, automated test runner, or configured repository-wide lint/typecheck command; `wallpaper_switcher/.qmlls.ini` is the only tooling file.
- Run available static checks on new or changed files before runtime testing.
- Before the final runtime smoke test, ask whether the user will test manually or wants the assistant to run it; default to the user's manual testing preference.
- If the assistant runs the smoke test, test only the changed config with `quickshell -c /home/Zrabbit/Documents/Dotfiles/ArchLinux/Quickshell/.config/quickshell/<config-dir>`; for example, `quickshell -c /home/Zrabbit/Documents/Dotfiles/ArchLinux/Quickshell/.config/quickshell/clock`.
- There is no single-test command. Exercise the changed config's actual trigger or data source and inspect Quickshell's runtime output.

## Structure And Modularity

- Organize each config into clear, feature-oriented directories and dedicated files, following its established local structure.
- Give each component or feature one coherent responsibility and a small, explicit interface to its consumers.
- Keep entrypoints focused on composition and wiring; place data collection, state management, process handling, and reusable UI in dedicated files when those concerns are separable.
- Extend configs by adding or composing modules instead of modifying unrelated, already validated features.
- Do not split trivial one-off logic into separate files unless it creates a meaningful, independently testable boundary.

## Review Scope

- Do not repeat broad audits of unchanged files that the user has explicitly identified as already validated.
- Reinspect validated files when they are modified, rewritten, or restructured; when an upstream API or runtime change may affect them; when observed behavior implicates them; or when security or data-flow analysis requires it.
- Prefer targeted inspection of relevant interfaces and call paths over full-file re-auditing.

## Development Priority

- Prioritize functional correctness. Defer visual polish, consistency passes, and redesign until the user explicitly requests them.
- Placeholder colors, font sizes, spacing, and similar visual values are acceptable during functional development.

## Runtime Assumptions

- `clock`, `ram-osd`, `system-osd`, and `weather` currently target `HDMI-A-1`; do not assume monitor names are portable.
- `alt-tab_view` and `wallpaper_switcher` require Hyprland. The former uses Wayland screencopy; the latter invokes `swaybg` or `hyprctl hyprpaper`.
- `bar` battery paths are host-specific (`BAT0`, `AC`); threshold writes use `sudo -n`, and profiles use `powerprofilesctl`. Start/end controls allow `45–95%`/`50–100%` with end greater than start.
- `bar` MPRIS selects Playing before Paused, hides Stopped, toggles playback on click, and caps text at 280 px.
- `bar/network/` polls kernel counters; VPN state polls NetworkManager and maps active VPN to Proton DNS, inactive to NextDNS.
- `volume-osd` reads the default PipeWire sink and intentionally supports displayed volume above 100% while clamping only the bar fill.
- `system-osd` polls once per second, runs `sudo -n turbostat`, and reads hard-coded AMD GPU and hwmon paths under `/sys`. Card and hwmon indexes are host-specific, and turbostat requires non-interactive sudo permission.
- `weather` runs `curl` against Open-Meteo every 15 minutes and embeds Strasbourg coordinates.
- `wallpaper_switcher` embeds wallpaper folders under `/home/Zrabbit/Pictures/Wallpaper`; selection state is runtime data stored through `Quickshell.statePath("wallpapers.json")`.
- Visuals depend on the `BigBlueTermPlus Nerd Font`, `JetBrainsMono Nerd Font`, `ttyclock`, `Atkinson Hyperlegible Next`, and `DSEG7 Modern` font families.

## Editing Constraints

- Preserve the touched subsystem's local indentation and naming; styles are not uniform across these configs.
- Keep `shell.qml` entrypoints, `qmldir` registrations, and config-rooted `qs.*` imports intact unless restructuring is the requested change.
- Validate process output before updating UI state. Missing commands, files, devices, network data, or malformed numbers should leave stable fallback values rather than throw.
- These configs and their polling timers run continuously. Avoid tighter polling, extra subprocesses, unbounded sample arrays, or repeated heavy allocations.
