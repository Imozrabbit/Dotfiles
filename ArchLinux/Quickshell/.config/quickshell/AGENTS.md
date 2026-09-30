# AGENTS.md

## Scope Boundary

- At the start of each new session, ask which top-level config directory should be the project root.
- After resolving symlinks, limit all reads, searches, edits, commands, and delegated work to the selected project root.
- Ask before accessing any ancestor, sibling config, or other path outside the selected project root.

## Project Structure
Independent runtime Quickshell QML configs; each top-level config has its own shell.qml.

- `alt-tab_view/`: Hyprland expose/window picker with IPC target `expose`; layouts are registered through `layouts/qmldir`.
- `bar/`: per-output bottom bar with IPC target `bar`; `shell.qml` owns one shared service set and screen variants, `BarWindow.qml` composes each output, `Config.qml` and `core/BarConfig.js` resolve defaults and host overrides, `services/` collects/mutates state, `widgets/` presents it, and `network/` owns route/rate, VPN/DNS, and NetworkManager Wi-Fi behavior. `bar/README.md` is the setup and module reference.
- `level-osd/`: transient stacked PipeWire volume and backlight OSD; its window exists only while a changed level is shown.
- `lockscreen/`: `WlSessionLock` service with separate password/fingerprint PAM contexts, per-output wallpaper state, preview mode, suspend recovery, and IPC target `lock`. `README.md` documents setup and security invariants.
- `wallpaper_switcher/`: Hyprland wallpaper GUI split into `core`, `services`, `ui`, `overlays`, and `animations`. Its `qs.*` imports resolve from this config root; preserve that hierarchy.

## Run And Verify

- There is no build system, formatter, code generation, or configured repository-wide lint/typecheck command. `bar/tests/*.mjs` are focused Node checks; `bar/.qmlls.ini` is local editor tooling.
- Run `qmllint` on changed QML before runtime testing. Lockscreen-specific verification and required import path are documented in `lockscreen/README.md`.
- Before the final runtime smoke test, ask whether the user will test manually or wants the assistant to run it; default to the user's manual testing preference.
- If the assistant runs the smoke test, test only the changed config with `quickshell -c /home/Zrabbit/Documents/Dotfiles/ArchLinux/Quickshell/.config/quickshell/<config-dir>`; for example, `quickshell -c /home/Zrabbit/Documents/Dotfiles/ArchLinux/Quickshell/.config/quickshell/bar`.
- There is no repository-wide test command. Run relevant focused checks where present, then exercise the changed config's trigger or data source and inspect Quickshell's runtime output.

## Structure And Modularity

- Organize each config into clear, feature-oriented directories and dedicated files, following its established local structure.
- Give each component or feature one coherent responsibility and a small, explicit interface to its consumers.
- Keep entrypoints focused on composition and wiring; place data collection, state management, process handling, and reusable UI in dedicated files when those concerns are separable.
- Extend configs by adding or composing modules instead of modifying unrelated, already validated features.
- Do not split trivial one-off logic into separate files unless it creates a meaningful, independently testable boundary.

## Extending `bar/`

- Keep `shell.qml` responsible for shared services and one IPC handler; compose per-output UI in `BarWindow.qml`. Create a service once only if an enabled output uses it; do not multiply subprocesses per monitor.
- Add module defaults in `Config.qml`; validate local overrides in `core/BarConfig.js`. Expose the module in the existing fixed layout, wire dependent feature visibility, and update `bar/README.md` with its configuration and optional commands.
- Anchor full-screen menus to the output that opened them. Keep `off` outputs windowless, `always` outputs reserved, and `hover` outputs as 2 px pointer targets; only focused, enabled `hover` outputs respond to toggle IPC.
- Normal workspace slots default to 1–3; additional existing numbered and special workspaces appear automatically. Host-specific minimum count and labels belong in `bar-local.json`, not hard-coded widget arrays.

## Review Scope

- Do not repeat broad audits of unchanged files that the user has explicitly identified as already validated.
- Reinspect validated files when they are modified, rewritten, or restructured; when an upstream API or runtime change may affect them; when observed behavior implicates them; or when security or data-flow analysis requires it.
- Prefer targeted inspection of relevant interfaces and call paths over full-file re-auditing.

## Development Priority

- Prioritize functional correctness. Defer visual polish, consistency passes, and redesign until the user explicitly requests them.
- Placeholder colors, font sizes, spacing, and similar visual values are acceptable during functional development.

## Runtime Assumptions

- `alt-tab_view` and `wallpaper_switcher` require Hyprland. The former uses Wayland screencopy; the latter applies through `swaybg` or `hyprctl hyprpaper reload`.
- `bar` has per-output `off`, `always`, and `hover` modes. Only a focused `hover` output with `hoverToggleEnabled` responds to IPC target `bar`; pinning reserves 35 px and unpinning restores pointer reveal without an exclusive zone.
- `bar` calendar and battery menus are full-screen overlay `PanelWindow`s with exclusive keyboard focus; `Esc` or clicking outside the card closes them.
- `bar` discovers battery and mains supplies. Preserve `sudo -n` charge-threshold writes, readback, and unavailable fallbacks; tooltip/panel use refreshes thresholds on demand.
- `bar/network/vpn/` treats exact SSID `HouseOfAnton_5GHz` as router-managed trusted home and runs no VPN/DNS commands there. Away, it polls active `wireguard`/`vpn` connections with `nmcli` and live resolvers with `resolvectl` every two seconds; expected DNS is NextDNS only when an active VPN and a recognized NextDNS address are both present.
- `bar` weather uses Open-Meteo geocoding and forecast APIs through `XMLHttpRequest`, supports saved user-selected locations, and atomically persists locations plus validated current/six-hour/three-day cache at `~/.local/state/quickshell/weather.json`. Opening the calendar refreshes only when the active cache is at least 15 minutes old.
- `bar/README.md` lists modules, optional commands, and configuration. Missing commands, files, sensors, and malformed output must leave stable unavailable state, not crash or trigger repeated heavy work.
- `level-osd` reads the default PipeWire sink and hard-coded `/sys/class/backlight/amdgpu_bl1`. It uses `inotifywait` plus a two-second polling/restart fallback, hides each changed row after one second, allows volume labels above 100%, and clamps only bar fill.
- `lockscreen` requires `/etc/pam.d/quickshell-lock-password`; fingerprint support additionally uses `/etc/pam.d/quickshell-lock-fingerprint` and `fprintd-list`. It also invokes `hyprctl -j monitors` and `loginctl unlock-session`; `QUICKSHELL_LOCK_ON_START=1` requests startup lock.
- `lockscreen` unlocks only on explicit `PamResult.Success`, clears password state and aborts active PAM contexts on reset/suspend, and starts fingerprint only after session lock is secure. Preview is not a secure session lock. Never stop Quickshell while locked unless immediate restart/recovery follows.
- `lockscreen` waits for valid named Wayland screens and reads per-output wallpaper/mode from `~/.local/state/quickshell/wallpapers.json`; fallback wallpaper is host-specific `/home/Zrabbit/Wallpaper/1920x1080/forest.png`. Its view includes a minute-aligned clock/date, time-based greeting, and authentication prompt.
- `wallpaper_switcher` embeds folders under `/home/Zrabbit/Pictures/Wallpaper`; `Quickshell.statePath("wallpapers.json")` stores selected utility and per-output `{wallpaper, mode}`. `scripts/apply.sh` requires `jq`, `pgrep`, and `pkill`, then runs `swaybg` or `hyprctl hyprpaper reload`.
- Visuals depend on `JetBrainsMono Nerd Font`, `JetBrainsMono Nerd Font Propo`, `JetBrainsMono Nerd Font Mono`, `BigBlueTermPlus Nerd Font Mono`, `Departure Mono`, `Atkinson Hyperlegible Next`, and `Great Vibes`.

## Editing Constraints

- Preserve the touched subsystem's local indentation and naming; styles are not uniform across these configs.
- Keep `shell.qml` entrypoints, `qmldir` registrations, and config-rooted `qs.*` imports intact unless restructuring is the requested change.
- Validate process output before updating UI state. Missing commands, files, devices, network data, or malformed numbers should leave stable fallback values rather than throw.
- These configs and their polling timers run continuously. Avoid tighter polling, extra subprocesses, unbounded sample arrays, or repeated heavy allocations.
- Treat `~/.local/state/quickshell/weather.json` and `wallpapers.json` as runtime data, not source configuration; preserve atomic writes and schema validation.
- Preserve lockscreen security boundaries: separate PAM stacks, explicit-success unlock, password clearing, secure-lock-before-fingerprint ordering, suspend handling, and stranded-lock recovery.
