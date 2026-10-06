# Development and troubleshooting

[Back to README](../README.md)

## Structure

`shell.qml` creates shared services once and composes per-output windows.
`BarWindow.qml` composes bottom-bar UI; `TopMediaWindow.qml` owns the top panel.
`Config.qml` supplies defaults; `core/BarConfig.js` validates overrides.
Services live in `services/`, UI in `widgets/`, and network features in `network/`.
Disabled features do not keep polling when no enabled output needs them.

`proton/Manager.qml` composes `proton/widgets/`; `proton/core/` holds palette/state,
`proton/services/` handles helper lifecycle, and `proton/scripts/` contains
orchestration, release/download, and filesystem logic.

Tests are grouped by feature under `tests/proton/`, `tests/network/`,
`tests/hardware/`, and `tests/quota/`. Bar-config checks stay at the test root.
No build system or repository-wide formatter is configured.

## Checks

Run from `bar/`. These checks use fixtures, not real gaming files or credentials:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests/proton -p 'test_proton_*.py'
PYTHONDONTWRITEBYTECODE=1 python3 tests/quota/openai-usage-checks.py
PYTHONDONTWRITEBYTECODE=1 python3 tests/hardware/wlmouse-checks.py
for test in tests/*.mjs tests/*/*.mjs; do
  PYTHONDONTWRITEBYTECODE=1 node "$test" || exit
done
```

Node checks require Node.js. Offscreen viewport checks require `qml6`; service
lifecycle checks and the demo import test require Quickshell. They do not
launch the actual bar. Run `qmllint` on changed QML with Quickshell's active
VFS import path. `.qmlls.ini` contains a host-specific path; adjust it locally.

Optional live memory comparison:

```sh
CHECK_LIVE_MEMORY=1 node tests/hardware/memory-checks.mjs
```

This compares reported figures with `free -k`.

## Proton demo

```sh
python3 tests/proton/proton-demo.py
```

The script creates private `/tmp/opencode/proton-demo-*` fixtures: dummy
installations, umu TOML, archives, checksums, and release metadata. Run the exact
launch command it prints. The staged demo uses real UI/service/transaction code
with a fixture adapter, without network, package commands, actual `/proc`
inspection, or real gaming paths. The adapter refuses non-fixture config paths.

Launch the printed temporary config, not `tests/proton/proton-demo` directly.
Quickshell requires imports within its config root, so the script copies needed
files. Regenerate after source changes. Escape exits; fixtures remain for inspection.
Do not change real `bar-local.json` for fixture testing.

Try installs/cleanup, GE selection/Sync, and selected-version removal blocking.
Inspect dummy `umu.toml`, preserved `[keep]` values, and unknown folders.
Edit boolean `blocked`, `badChecksum`, or `packageUnavailable` fields in
`scenario.json`, then Refresh to test failures.

## Runtime data

| File | Purpose |
| --- | --- |
| `$XDG_CONFIG_HOME/quickshell/bar-local.json` (default `~/.config/quickshell/bar-local.json`) | Personal configuration; kept outside `bar/`. |
| `~/.local/state/quickshell/weather.json` | Saved weather locations and forecast cache. |
| `~/.cache/quickshell/wifi_status.json` | Last-known Wi-Fi status. |
| `$XDG_DATA_HOME/opencode/opencode.db` (default `~/.local/share/opencode/opencode.db`) | Existing OpenCode credentials; quota collector opens read-only. Legacy `opencode/auth.json` is a fallback. |

Runtime/authentication files are not source configuration. Do not copy or commit
them. The quota collector prefers the active v2 OpenAI credential; ambiguous
accounts fail rather than selecting arbitrarily. An expired selected v2 login
does not fall back to an old JSON login.

## Troubleshooting

- **No bar on a screen:** check its exact name with `hyprctl monitors` and its
  `mode`. `off` leaves Quickshell running without a bottom-bar window.
- **Runtime errors:** run `qs -c bar` in a graphical terminal. Avoid launching a
  duplicate instance; stop only the bar first if needed, never the lockscreen.
- **No network/Wi-Fi:** check module switches, NetworkManager, and default route.
  VPN/DNS details come from `nmcli` and `resolvectl status`.
- **Missing sensors:** CPU temperature needs `k10temp`/`coretemp`; GPU metrics need
  `amdgpu`; batteries/AC are discovered under `/sys/class/power_supply`.
  Unsupported data stays unavailable.
- **Mouse shows `N/A`:** check receiver connection, permissions, and the README's
  udev setup. A sleeping/nonresponding mouse is not necessarily disconnected.
- **Quota shows `N/A`:** renew expired login in OpenCode; check error and last
  update time. The backend endpoint can change. Reset countdowns do not fabricate
  restored quota before a successful reading.
- **Proton blocked:** close gaming processes and read the reported reason.
  Do not bypass safety checks to force a write.
- **Narrow-screen overlap:** module order and bar height are fixed. Hide modules
  or reduce spacing for that monitor instead of expecting automatic rearrangement.

## Behavior notes

- Bottom `always`/pinned bars reserve 35 px; unpinned hover bars reserve none.
  Mode changes reset pin/reveal state. Disabled menus close; active writes finish.
- Top media centers at up to 40% of screen width. Overflow scrolls; no active
  player means no window/reserved space. Bottom toggle IPC never pins top media.
- VPN/DNS follows ordinary-query systemd-resolved routing: `~.` takes priority,
  otherwise default links/global resolvers apply. Domain-specific split DNS is
  excluded. Router DNS requires connected physical-interface gateway evidence;
  categories describe routing, not protection guarantees.
- Workspace focus follows Hyprland globally. Special workspaces use focused,
  occupied, or empty states; closed empty special workspaces are hidden.
- Weather uses Open-Meteo, validated cached forecasts, and atomic state writes.
  Opening the calendar refreshes the active cache only once it is 15 minutes old.
