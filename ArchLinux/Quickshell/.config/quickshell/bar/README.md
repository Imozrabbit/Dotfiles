# Quickshell bar

This bottom bar runs as one Quickshell configuration on Hyprland. `shell.qml`
creates shared services once, then places a `BarWindow` on each enabled Wayland
output. Bar windows show the same fixed module order, but visibility can differ
by output. Full-screen menus open on the output that owns their button; service
polling stops when no enabled bar uses that feature.

Left and right sections anchor to their respective screen edges. Media appears
in a separate full-width transparent top panel, centered at its natural width
up to 40% of the monitor width. Long text scrolls without shrinking its font.
On very narrow
screens the sections may overlap, with right-side controls above the left.
Module sizes and the single-row bar height do not change.

## Modules

- **Workspaces:** Hyprland workspace and special-workspace state and switching.
  Slots 1–3 stay visible by default; other workspaces appear when created.
  `workspaceDisplay` sets a larger minimum and optional labels/icons.
- **Tray:** app icons, primary activation, and a themed app-provided menu.
- **Launcher:** configurable app shortcuts that expand rightward from the
  update/launcher icon on hover. Defaults: wallpaper switcher, GTK Look, Qt6ct.
- **Updates:** `checkupdates` count and manual refresh; runs hourly.
- **Proton Manager:** optional `󰹂` button after Tray, left of Updates. On-demand
  GE-Proton/CachyOS checks, verified installation and confirmed cleanup/removal,
  installed GE selection for umu, and official Arch umu-launcher status.
- **Media:** active MPRIS player, scrolling track text, and playback toggle.
  Animation runs only when text overflows a visible media box.
- **OpenAI usage:** optional amber chip between controls and time/date showing
  five-hour Codex subscription percentage remaining. Bundled OpenAI logo and
  tooltip show five-hour/weekly allowances, reset countdowns, plan, and status.
- **Network:** default-route transfer rates sampled every second and a hover
  tooltip with interface, IPv4 address, gateway, and Wi-Fi signal/frequency.
- **VPN/DNS:** independent local VPN and resolver status, refreshed every two
  seconds by one shared service. Active NetworkManager VPN/WireGuard profiles
  take precedence over an optional configured router VPN fallback. This
  indicator can be hidden without hiding network rates.
- **Wi-Fi menu:** NetworkManager radio, active connection, saved profiles,
  available-network scans, credentials, and advanced editor. It is optional
  even when the network widget remains visible.
- **CPU, GPU, memory:** usage indicators and hover details. AMD GPU metrics
  use discovered sysfs paths; Intel/NVIDIA metrics are not implemented.
- **Volume:** PipeWire default-sink volume and mute.
- **Bluetooth:** adapter state, paired-device details on demand, and device
  connect/disconnect controls.
- **Input method:** Fcitx state and cycling.
- **Brightness:** display slider and keyboard-backlight cycling when available.
- **Battery:** charge, health, power profile, and supported charge thresholds.
- **Mouse battery:** optional WLMouse percentage between battery and clock in
  the same box. Tooltip shows configured mouse name, wired/wireless transport,
  and charging status. It remains usable with laptop battery display disabled.
  Failed readings show `N/A` with a reason rather than stale percentages.
- **Clock and calendar:** live time, monthly calendar, and weather panel.
- **Weather:** Open-Meteo location search and forecast; saved locations and a
  validated cache survive restarts.
- **Notifications:** SwayNC notification/DND indicator and panel launcher.

## Configuration

`Config.qml` contains synced defaults: mode `always`, `hoverToggleEnabled: true`,
and all modules enabled except `mouseBattery`, `openAiUsage`, and `protonManager`. Put machine-specific settings in optional
`~/.config/quickshell/bar-local.json`, or
`$XDG_CONFIG_HOME/quickshell/bar-local.json` if that variable is set. Global
values override defaults; exact output names in `monitors` override global
values. Omitted settings keep their defaults. Invalid fields are ignored.
**Valid saves apply live**, including spacing, modules, and monitor modes;
no restart is required. Malformed or unreadable saves keep the last valid
configuration (shipped defaults at startup). File creation and atomic editor
saves are watched without polling. To return to defaults while running, save
`{}`. The local file lives outside this repository.

Complete example (replace output names with those from `hyprctl monitors`):

```json
{
  "mode": "always",
  "topMediaMode": "hover",
  "edgeSpacing": 14,
  "hoverToggleEnabled": true,
  "vpn": { "routerManagedSsids": [] },
  "mouseBattery": { "name": "WLMouse Beast X" },
  "launchers": [
    {
      "icon": "󰸉",
      "tooltip": "Wallpaper Switcher",
      "leftCommand": ["quickshell", "-c", "wallpaper_switcher"],
      "rightCommand": []
    },
    {
      "icon": "󰔎",
      "tooltip": "Left click: GTK Look\nRight click: Qt6ct",
      "leftCommand": ["nwg-look"],
      "rightCommand": ["qt6ct"]
    }
  ],
  "modules": {
    "workspaces": true,
    "tray": true,
    "launcher": true,
    "updates": true,
    "protonManager": false,
    "media": true,
    "network": true,
    "vpn": true,
    "wifiMenu": false,
    "cpu": true,
    "gpu": false,
    "memory": true,
    "volume": true,
    "bluetooth": false,
    "inputMethod": false,
    "brightness": false,
    "battery": false,
    "mouseBattery": false,
    "openAiUsage": false,
    "clock": true,
    "calendar": true,
    "weather": true,
    "notifications": true
  },
  "workspaceDisplay": {
    "minimumCount": 7,
    "itemSpacing": 21,
    "normalLabels": { "4": "󰝆", "5": "󰐫", "6": "", "7": "" },
    "specialLabels": { "rmpc": "", "steam": "" }
  },
  "monitors": {
    "DP-1": { "mode": "always", "topMediaMode": "hover", "edgeSpacing": 14 },
    "HDMI-A-1": {
      "mode": "hover",
      "topMediaMode": "always",
      "edgeSpacing": 4,
      "workspaceDisplay": { "itemSpacing": 8 },
      "hoverToggleEnabled": false,
      "modules": { "notifications": false }
    },
    "DP-2": { "mode": "off", "topMediaMode": "off" }
  }
}
```

- `always`: bar stays visible and reserves 35 px; toggle IPC is ignored.
- `hover`: 2 px bottom-edge pointer target with no reserved zone. Hover reveals
  the bar temporarily. Toggle IPC pins/unpins the **focused** output; pinned
  bars reserve 35 px. Set `hoverToggleEnabled: false` to ignore that request,
  not to remove its Hyprland binding.
  For Hyprland Lua, bind toggle with
  `hl.bind(mainMod .. "+ C", hl.dsp.exec_cmd("qs -c bar ipc call bar toggle"))`.
- `off`: no bar window, pointer target, or reserved zone. Unknown outputs use
  the configured global mode, which defaults to `always`.

`wifiMenu` and `vpn` require `network`; `weather` requires `calendar`.
Disabling a parent also disables its dependent feature. Layout order does not
change when a module is hidden. Status services are shared among outputs and
unused services do not poll.

`topMediaMode` controls the independent top MPRIS panel, globally or per monitor
under `monitors`: `hover` (default), `always`, or `off`. `modules.media: false`
also disables it. Bottom `mode: "off"` does not disable top media. `hover` uses
a full-width 2 px top-edge reveal target and expands to 35 px without reserving
space; `always` reserves 35 px. No active player means no top window or reserved
space in either mode. Paused players remain available. The existing `bar toggle`
IPC/shortcut only controls the bottom bar; top media cannot be pinned by it.
Set global `topMediaMode` for all outputs, then override individual monitor
names as above. Omitted monitor values inherit the global setting. Both modes
apply live when the override file is saved. In the example, DP-1 reveals top
media on hover, HDMI-A-1 keeps it visible while a player exists, and DP-2 has
neither bar. Set `modules.media: false` per monitor to disable media there
regardless of `topMediaMode`. The centered 40% width limit is fixed, not a
configuration field; `hoverToggleEnabled` affects only the bottom bar.

`vpn.routerManagedSsids` is a global list of exact Wi-Fi SSIDs, empty by default.
On a machine using a router VPN, set it to, for example,
`["HouseOfAnton_5GHz"]`. With no active local VPN, a matching connected SSID
shows **Router VPN**. This is configuration, not a router health
check. Local VPN detection continues on that network. Ethernet-only machines
normally leave the list empty. A failed VPN query shows **Unavailable**, not
the router fallback.

The VPN glyph shows local VPN (``), configured router VPN (`󰣫`), no local VPN
(`󱙲`), or unavailable (``). The adjacent DNS dot identifies resolver category:
NextDNS mint, router blue, VPN/other neutral, mixed purple, unavailable muted red.
These colors describe category, not a protection guarantee. Classification
follows systemd-resolved routing for ordinary Internet queries: a `~.` DNS
route takes precedence; otherwise default DNS links and global resolvers apply.
Domain-specific split DNS, such as Tailscale machine-name resolution, does not
make the main indicator Mixed. Tailscale is not classified as a local Internet
VPN. Wrapped resolver lists are supported. NextDNS addresses
take precedence; router DNS requires a resolver matching a connected physical
interface's gateway; VPN DNS requires an active VPN interface. Other addresses
remain Other DNS. Different categories serving ordinary queries show Mixed.
The tooltip shows the DNS category without individual resolver addresses;
use `resolvectl status` for endpoint details. DNS status remains visible even
when the VPN query fails; missing gateway evidence never implies router DNS.

`workspaceDisplay.minimumCount` keeps slots 1 through that number visible
even when empty (default: 3). Existing higher-numbered workspaces appear
automatically, without adding empty intermediate slots. `normalLabels` maps
workspace IDs to glyphs/text. Special workspaces appear when Hyprland creates
them; `specialLabels` maps their names to glyphs/text. Unmapped entries use
their number or name. Labels do not make absent workspaces visible.

Normal workspace highlighting follows global Hyprland focus on every bar.
Special workspaces open on the focused monitor use the same active highlight,
even when empty. Unfocused occupied special workspaces are purple whether
open or closed; open empty unfocused ones are gray. Closed empty special
workspaces are hidden. Pointer hover keeps its usual hover color.

`workspaceDisplay.itemSpacing` sets gaps between items in the workspace box,
including separators and expanded launcher icons. Default: 21 px; accepted
range: 0–100 px. `edgeSpacing` sets horizontal screen-edge margins for the
left/right sections (default: 14 px; range: 0–100 px). Both settings can be
overridden per monitor as shown above. Monitor workspace settings inherit
global minimum count and labels unless explicitly overridden.

Mode changes clear pin/reveal state. Menus close when their feature is disabled.
In-progress charge-limit or Wi-Fi actions finish before their shared service is
unloaded; live reconfiguration does not terminate those writes halfway through.

`launchers` is an ordered replacement list: omit it to use shipped defaults,
provide an array to replace them, or use `[]` to clear entries. It can also be
overridden per monitor. Each entry needs a nonempty `icon`; `tooltip` is optional
and supports JSON `\n` line breaks. `leftCommand` and `rightCommand` are optional
argument lists; omitted or empty lists perform no action. Invalid entries are
skipped. Commands run directly, without implicit shell expansion. Saves apply
live; per-monitor `itemSpacing` controls gaps between revealed icons and trigger.

Enable `modules.mouseBattery` on the PC that uses the mouse and set
`mouseBattery.name` to the name you want in its tooltip. Both can be overridden
per monitor. The bundled `scripts/wlmouse.py` supports WLMouse Beast X wired
and 1K receiver devices (VID `36a7`, PIDs `a884`/`a882`). One shared asynchronous
process refreshes at startup and every 60 seconds. Hover requests a refresh
with a global 10-second cooldown; concurrent queries are skipped. A five-second
watchdog marks stalled queries unavailable and requests termination.

Python 3 and read/write access to the matching `/dev/hidraw*` devices are
required. The optional udev setup below grants device-scoped access for the
active desktop user; the collector does not use sudo. Missing devices, sleeping/disconnected
mice, permissions failures, and malformed output produce `N/A`; no response
does not by itself prove that a mouse is disconnected. Mouse name is user
configuration, not a name discovered by the collector.

Enable `modules.openAiUsage` globally or per monitor to read existing OpenCode
ChatGPT OAuth credentials from `$XDG_DATA_HOME/opencode/opencode.db` (default:
`~/.local/share/opencode/opencode.db`), opened read-only through Python's built-in
SQLite support. The active v2 OpenAI credential takes precedence; a sole
credential with a null active flag is also supported. Multiple equally preferred
credentials report an error rather than choose an account arbitrarily. If no
usable v2 credential is available, the collector falls back to `opencode/auth.json`
in the same data directory for v1. An expired selected v2 credential does not
fall back to an old JSON login. Python 3 and Qt SVG support are required;
OpenCode need not be running. The collector reads only the OpenAI login, never
refreshes or modifies credentials, and sends only quota GET requests to
`https://chatgpt.com/backend-api/wham/usage`. It does not perform inference or
use billed API keys. Tokens, account IDs, and email are not included in output.
Do not put passwords/tokens in the override or sync the authentication file.

One service refreshes every five minutes, on hover if the last attempt is at
least five minutes old, and when a known reset becomes due.
Left-click the quota chip to refresh immediately, bypassing the five-minute
cooldown. Clicks while a request is running do not start another request.
Reset countdowns use the shared local clock; elapsed time does not fabricate a restored quota.
A failed request shows `N/A`, reason, and last update time. Refresh an expired
login in OpenCode. This is a ChatGPT backend endpoint, not a stable public
billing API: unexpected schema changes degrade to unavailable state. The SVG
logo is bundled from Simple Icons v13.21.0 (CC0; OpenAI retains its trademark).

## Proton Manager

Enable `modules.protonManager` globally or per output. One service and popup are
shared. Opening always inspects local installations/config; automatic release and
package checks run at most once every 24 hours per Quickshell session. **Refresh**
bypasses that cooldown. Restarting Quickshell triggers a new initial check. No
background polling. `qs -c bar ipc call bar protonManager` opens on the focused
enabled output; `bar previewProton` remains a compatibility alias.

Add this top-level `protonManager` object to `~/.config/quickshell/bar-local.json`
(or `$XDG_CONFIG_HOME/quickshell/bar-local.json`). Merge it into existing JSON;
do not place it inside `modules` or `monitors`. Paths override the shipped defaults
and are global, not per-monitor:

```json
{
  "protonManager": {
    "compatibilityToolsDir": "/home/Steam/.local/share/Steam/compatibilitytools.d",
    "umuConfigPath": "/home/Steam/.config/umu-launcher/config.toml",
    "sandboxCompatibilityToolsDir": "/home/Zrabbit/.local/share/Steam/compatibilitytools.d"
  }
}
```

These shipped paths match the gaming PC's host/sandbox mapping. Override them
for another layout; without a sandbox, use the same compatibility-tools path
for host and sandbox. Paths must be absolute and cannot contain `..` or NUL.
Existing installation/configuration directories are required; the manager does
not invent missing umu configuration or follow installation-directory symlinks.

Python **3.11+** and standard library provide all management logic. `pacman` and
`checkupdates` (pacman-contrib) are optional for official Arch `umu-launcher`
status; missing/failed commands show unavailable. No package installation,
host package database synchronization, sudo, or AUR management is performed.

Updates targets official GE-Proton **x86_64** and CachyOS Proton **SLR
x86_64_v3**, requiring the matching published SHA-512 checksum. GE folders named
`GE-Proton<major>-<minor>[-<patch>]` and the same name with `-x86_64` suffix are
recognized; the canonical compatibility metadata name may omit that suffix.
Confirm the
release and exact older same-family versions before **Update & clean**.
Downloads stage on the installation filesystem; archives/links and installation
metadata are validated before no-replace atomic activation. GE updates umu
before cleanup. Unknown folders, newer versions, and the selected umu version
are protected. Steam/umu/Proton/Wine command lines across users and readable
executable evidence block mutation. Uninspectable executable state for the
desktop user or installation/config owner also blocks mutation; checks repeat before
activation/config writes and every removal.

Launcher selection and **Sync latest GE** only write the existing umu config.
Sync rescans and chooses the newest valid **installed** GE; it does not download
upstream GE. Wheel navigation alone does not write: click an entry or press
Enter to commit. The selector and Installed umu marker update after successful
write. TOML comments/unrelated values and file permissions are preserved; unsafe,
ambiguous, or unsupported TOML spellings fail without rewriting the file.

Closing the popup or disabling the module does not terminate active work.
Installation followed by config/cleanup failure reports partial success and
retains working files; failed umu updates retain all older GE. Interrupted
staging is hidden from installed inventory and is not automatically deleted.
Operations and results appear in their corresponding tabs; progress is shared.

Code lives under `proton/`: `Manager.qml` composes tabs, `Palette.qml` names
module colors, `Service.qml` validates helper events, and `backend.py`,
`releases.py`, `storage.py` isolate orchestration/network/filesystem concerns.

### Dummy testing without Steam

From `bar/`, run:

```sh
python3 tests/proton-demo.py
```

It creates a private `/tmp/opencode/proton-demo-*` directory with dummy
installations, umu TOML, small archives, checksums, release metadata, and prints
the **exact demo launch command**. Run that command manually. This separate
popup uses the real UI/service/transaction code with a fixture adapter: no
network, package commands, actual `/proc` inspection, or real gaming paths.
The script copies required QML/Python modules into the fixture's `demo/` config
root because Quickshell rejects imports outside its selected config. Launch the
printed temporary path, not `bar/tests/proton-demo` directly. Regenerate fixtures
after source changes to refresh these copies.
Escape exits the demo; fixtures remain for inspection. Run the script again
for a fresh directory. Do not change the real bar-local.json to test fixtures.

Try GE install/cleanup, CachyOS update, GE selection/Sync, and selected-version
removal blocking. Inspect the printed directory's `umu.toml`, installation
folders, preserved unknown folder, and `[keep]` table. Edit its `scenario.json`
and press Refresh to test `blocked`, `badChecksum`, and `packageUnavailable`
(boolean fields). The adapter refuses non-fixture configuration paths.

Automated checks (all mutations use private temporary fixtures):

```sh
python3 -m unittest discover -s tests -p 'test_proton_*.py'
for test in tests/proton-*-checks.mjs; do node "$test" || exit; done
```

Offscreen viewport checks require `qml6`; isolated service lifecycle checks
require Quickshell. Neither launches your actual bar.

## Install

1. Install Quickshell (tested with 0.3.1), Hyprland, Qt 6 Quick Controls and
   Layouts, and `Qt5Compat.GraphicalEffects`. For audio, run PipeWire and its
   session manager. Install **JetBrainsMono Nerd Font Propo** and **Atkinson
   Hyperlegible Next** for intended icons and text.
2. Install commands for features you use: `ip`, `iw`, `nmcli`/NetworkManager,
   and `resolvectl` for network/VPN/Wi-Fi; `checkupdates` for updates;
   `bluetoothctl` for Bluetooth; `brightnessctl` for brightness;
   `fcitx5-remote` for input method; `swaync-client`/SwayNC for notifications;
   `powerprofilesctl` for battery profiles; `lspci` for AMD GPU names. The
   optional advanced actions launch `nm-connection-editor`, `ghostty` with
   `bluetui`, `nwg-look`, `qt6ct`, or the separate `wallpaper_switcher` config.
   Missing optional tools leave associated controls without live data or actions.
3. Download the `thinkpad` branch tarball, extract only `bar/`, and replace
   the installed folder. No Git checkout or symlink is needed. Requires
   `curl` and GNU `tar`:

   ```sh
   qs -c bar kill
   config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell"
   stage=$(mktemp -d)
   curl -fL https://codeload.github.com/Imozrabbit/Dotfiles/tar.gz/refs/heads/thinkpad \
     -o "$stage/dotfiles.tar.gz" &&
   tar -xzf "$stage/dotfiles.tar.gz" -C "$stage" --strip-components=5 \
     Dotfiles-thinkpad/ArchLinux/Quickshell/.config/quickshell/bar &&
   mkdir -p "$config_dir" &&
   rm -rf "$config_dir/bar" &&
    mv "$stage/bar" "$config_dir/bar" &&
    chmod +x "$config_dir/bar/scripts/"*.py &&
   rm -rf "$stage" &&
   # To run the bar
   qs -c bar -d
   ```

   These commands replace the whole installed `bar` folder, including any
   edits inside it. Keep host settings in the sibling `bar-local.json`.
   Use `qs -c bar` without `-d` to run in the foreground and see runtime errors.

4. Create `bar-local.json` outside the repository if this host needs module,
   workspace, or monitor overrides. A missing file uses defaults. Battery charge limits
   additionally require supported sysfs threshold files and narrowly scoped
    permission for existing `sudo -n` writes; ordinary battery display does not.

5. On the PC using WLMouse, install Python 3 and the bundled udev rule once:

   ```sh
   config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell"
   sudo install -m 0644 "$config_dir/bar/scripts/70-wlmouse.rules" /etc/udev/rules.d/70-wlmouse.rules
   sudo udevadm control --reload-rules
   sudo udevadm trigger --action=add --subsystem-match=hidraw
   sudo udevadm settle
   python3 "$config_dir/bar/scripts/wlmouse.py"
   ```

   In order to take effect immediately, unplug then plug the doggle.
   The final command should print JSON without sudo. Reconnect mouse/receiver
   if access has not updated, then retry from your graphical session. The rule
   explicitly matches receiver PID `a882` and wired PID `a884` under vendor
   `36a7`. Attribute selectors use `==`, not assignment `=`. Enable
   `modules.mouseBattery` after access works. Hover refresh has a 10-second
   cooldown. Executable permission is for direct script execution; the bar
   invokes it through Python and does not require `chmod +x` to collect data.

## Update

Stop only the running bar:

```sh
qs -c bar kill
```

Then rerun the download/extraction commands in installation step 3. They remove
the old folder and launch the new version. `bar-local.json` and weather/Wi-Fi
runtime data remain untouched. Skip the kill command if the bar is not running.

Other Quickshell configurations, especially a running lockscreen, must stay
running. The `bar` IPC target provides `toggle`; it acts only on a focused
`hover` output whose `hoverToggleEnabled` setting is true.

## State, checks, and troubleshooting

- Host overrides: `$XDG_CONFIG_HOME/quickshell/bar-local.json` or
  `~/.config/quickshell/bar-local.json`.
- Weather locations/forecast: `~/.local/state/quickshell/weather.json`;
  Wi-Fi last-known status: `~/.cache/quickshell/wifi_status.json`. These are
  runtime data, not files to copy into the repository.
- No bar on a display: check its exact output name with `hyprctl monitors`,
  then inspect that output's `mode`. `off` intentionally leaves Quickshell
  running without a bar window.
- No rates or Wi-Fi control: inspect the `network` and `wifiMenu` switches,
  NetworkManager, and the active default route. VPN/DNS details use `nmcli`
  and `resolvectl status` on every network, including configured router VPN SSIDs.
- Missing sensor/device: CPU temperature needs a `k10temp` or `coretemp`
  hwmon sensor; GPU metrics need `amdgpu`; battery/AC are discovered under
  `/sys/class/power_supply`. Unsupported data stays `N/A`.
- QML import diagnostics: `.qmlls.ini` is local editor tooling and contains
  a host-specific Quickshell VFS path. Adjust that path on another machine.
  To diagnose runtime errors, run `quickshell -c bar` in a graphical terminal.
- Maintainer checks: `node tests/bar-config-checks.mjs`,
  `node tests/vpn-dns-checks.mjs`,
  `node tests/vpn-process-checks.mjs`,
  `python3 tests/openai-usage-checks.py`, `node tests/openai-usage-checks.mjs`,
  `node tests/mouse-battery-checks.mjs`, `python3 tests/wlmouse-checks.py`,
  `node tests/memory-checks.mjs`, and `node tests/regression-checks.mjs`.
  `CHECK_LIVE_MEMORY=1 node tests/memory-checks.mjs` compares memory figures
  with `free -k`. Use Qt 6 `qmllint` with Quickshell's active VFS import path
  on changed QML files.
