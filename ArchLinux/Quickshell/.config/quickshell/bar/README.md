# Quickshell bar

This bottom bar runs as one Quickshell configuration on Hyprland. `shell.qml`
creates shared services once, then places a `BarWindow` on each enabled Wayland
output. Bar windows show the same fixed module order, but visibility can differ
by output. Full-screen menus open on the output that owns their button; service
polling stops when no enabled bar uses that feature.

Left and right sections anchor to their respective screen edges. Media text
centers in up to 70% of the gap between them, capped at 400 px. Long text scrolls
without shrinking its font; media hides only when no useful icon-sized space
remains. On very narrow
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
- **Media:** active MPRIS player, scrolling track text, and playback toggle.
  Animation runs only when text overflows a visible media box.
- **Network:** default-route transfer rates sampled every second and a hover
  tooltip with interface, IPv4 address, gateway, and Wi-Fi signal/frequency.
- **VPN:** router-managed status on exact SSID `HouseOfAnton_5GHz`; away from
  home, shows active VPN and live DNS/NextDNS status. This indicator can be
  hidden without hiding network rates.
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
and all modules enabled except `mouseBattery`. Put machine-specific settings in optional
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
  "edgeSpacing": 14,
  "hoverToggleEnabled": true,
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
    "DP-1": { "mode": "always", "edgeSpacing": 14 },
    "HDMI-A-1": {
      "mode": "hover",
      "edgeSpacing": 4,
      "workspaceDisplay": { "itemSpacing": 8 },
      "hoverToggleEnabled": false,
      "modules": { "media": false, "notifications": false }
    },
    "DP-2": { "mode": "off" }
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
   config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell"
   stage=$(mktemp -d)
   curl -fL https://codeload.github.com/Imozrabbit/Dotfiles/tar.gz/refs/heads/thinkpad \
     -o "$stage/dotfiles.tar.gz" &&
   tar -xzf "$stage/dotfiles.tar.gz" -C "$stage" --strip-components=5 \
     Dotfiles-thinkpad/ArchLinux/Quickshell/.config/quickshell/bar &&
   mkdir -p "$config_dir" &&
   rm -rf "$config_dir/bar" &&
    mv "$stage/bar" "$config_dir/bar" &&
    chmod +x "$config_dir/bar/scripts/wlmouse.py" &&
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
  and `resolvectl` only away from the trusted home SSID.
- Missing sensor/device: CPU temperature needs a `k10temp` or `coretemp`
  hwmon sensor; GPU metrics need `amdgpu`; battery/AC are discovered under
  `/sys/class/power_supply`. Unsupported data stays `N/A`.
- QML import diagnostics: `.qmlls.ini` is local editor tooling and contains
  a host-specific Quickshell VFS path. Adjust that path on another machine.
  To diagnose runtime errors, run `quickshell -c bar` in a graphical terminal.
- Maintainer checks: `node tests/bar-config-checks.mjs`,
  `node tests/mouse-battery-checks.mjs`, `python3 tests/wlmouse-checks.py`,
  `node tests/memory-checks.mjs`, and `node tests/regression-checks.mjs`.
  `CHECK_LIVE_MEMORY=1 node tests/memory-checks.mjs` compares memory figures
  with `free -k`. Use Qt 6 `qmllint` with Quickshell's active VFS import path
  on changed QML files.
