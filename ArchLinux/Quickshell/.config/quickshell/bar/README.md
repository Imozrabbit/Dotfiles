# Quickshell Bar

A configurable bottom bar for **Hyprland**, built with [Quickshell](https://quickshell.org/).
Use it on multiple monitors, keep it visible or reveal it on hover, and choose
which features appear on each screen. Music appears in a separate top panel.

## Features

- Workspaces, system tray, app shortcuts, and update count.
- Network speeds, Wi-Fi controls, and VPN/DNS status.
- CPU, AMD GPU, memory, audio, brightness, Bluetooth, and battery controls.
- Clock, calendar, weather, and notifications.
- Optional Proton Manager, WLMouse battery, and ChatGPT/Codex quota display.

## Install and run

Requires **Hyprland**, **Quickshell** (tested with 0.3.1), Qt 6 Quick Controls,
Qt 6 Quick Layouts, and `Qt5Compat.GraphicalEffects`. Install **JetBrainsMono
Nerd Font Propo** and **Atkinson Hyperlegible Next** for icons and text.
Audio controls need PipeWire and a session manager.

Copy this `bar/` folder to `~/.config/quickshell/bar/`
(or `$XDG_CONFIG_HOME/quickshell/bar/`), then run:

```sh
qs -c bar -d
```

Use `qs -c bar` without `-d` to see errors in your terminal. To start on login,
add `exec-once = qs -c bar -d` to your Hyprland configuration.

<details>
<summary>Download or update directly from GitHub</summary>

Requires `curl` and GNU `tar`. **This replaces the entire installed `bar/`
folder, including edits inside it.** Keep personal settings in `bar-local.json`.
Stop only the bar with `qs -c bar kill` before updating; skip this if it is not running.
Do not stop other Quickshell configurations, especially a running lockscreen.

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
rm -rf "$stage" &&
qs -c bar -d
```

Your sibling `bar-local.json` and saved weather/Wi-Fi data stay untouched.

</details>

### Optional tools

Install tools for features you use; missing tools leave those controls unavailable.

| Feature | Tools |
| --- | --- |
| Network / Wi-Fi / VPN / DNS | `ip`, `iw`, NetworkManager (`nmcli`), `resolvectl` |
| Updates | `checkupdates` from `pacman-contrib` |
| Bluetooth | `bluetoothctl`; optional `ghostty` + `bluetui` for advanced controls |
| Brightness | `brightnessctl` |
| Input method | `fcitx5-remote` |
| Notifications | SwayNC (`swaync-client`) |
| Battery profiles | `powerprofilesctl` |
| AMD GPU name | `lspci` |
| Advanced Wi-Fi editor | `nm-connection-editor` |
| Default shortcuts | `nwg-look`, `qt6ct`, separate `wallpaper_switcher` config |
| Mouse battery / quota display | Python 3; quota also needs Qt SVG support |
| Proton Manager | Python 3.11+; optional `pacman` and `checkupdates` for package status |

## Configuration

Create `~/.config/quickshell/bar-local.json` beside the `bar/` folder,
not inside it. If you use `XDG_CONFIG_HOME`, use `$XDG_CONFIG_HOME/quickshell/bar-local.json`.

**Only include settings you want to change.** Missing settings use defaults.
Saving valid JSON applies changes immediately, without restarting. Invalid
fields are ignored; broken JSON keeps the last working configuration.
Save `{}` to reset to defaults.

### Full example

This includes every supported option. Most values match defaults; workspace
labels and monitor entries are examples. Replace monitor names using
`hyprctl monitors`. Proton paths below are host-specific: change them before
enabling Proton Manager.

```json
{
  "mode": "always",
  "topMediaMode": "hover",
  "edgeSpacing": 14,
  "hoverToggleEnabled": true,
  "vpn": { "routerManagedSsids": [] },
  "mouseBattery": { "name": "WLMouse Beast X" },
  "protonManager": {
    "compatibilityToolsDir": "/home/Steam/.local/share/Steam/compatibilitytools.d",
    "umuConfigPath": "/home/Steam/.config/umu-launcher/config.toml",
    "sandboxCompatibilityToolsDir": "/home/Zrabbit/.local/share/Steam/compatibilitytools.d"
  },
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
    "wifiMenu": true,
    "cpu": true,
    "gpu": true,
    "memory": true,
    "volume": true,
    "bluetooth": true,
    "inputMethod": true,
    "brightness": true,
    "battery": true,
    "mouseBattery": false,
    "openAiUsage": false,
    "clock": true,
    "calendar": true,
    "weather": true,
    "notifications": true
  },
  "workspaceDisplay": {
    "minimumCount": 3,
    "itemSpacing": 21,
    "normalLabels": { "1": "Web", "2": "Code" },
    "specialLabels": { "steam": "" }
  },
  "monitors": {
    "DP-1": { "mode": "always", "topMediaMode": "hover" },
    "HDMI-A-1": {
      "mode": "hover",
      "topMediaMode": "always",
      "edgeSpacing": 4,
      "hoverToggleEnabled": false,
      "workspaceDisplay": { "itemSpacing": 8 },
      "modules": { "notifications": false }
    },
    "DP-2": { "mode": "off", "topMediaMode": "off" }
  }
}
```

### Display and layout

| Option | What it does |
| --- | --- |
| `mode` | Bottom bar: `always` stays visible and reserves 35 px; `hover` reveals from a 2 px bottom edge; `off` removes it. Default: `always`. |
| `topMediaMode` | Music panel: `hover`, `always`, or `off`. Default: `hover`. Appears only when a player is available, even if paused. Independent of bottom bar mode. |
| `edgeSpacing` | Left/right margins in pixels, 0–100. Default: 14. |
| `hoverToggleEnabled` | Allow the toggle command to pin/unpin a hover bar. Default: `true`. Pinned bars reserve 35 px. Does not affect mouse hover or top media. |
| `monitors` | Settings for individual screens. Use exact names from `hyprctl monitors`; omitted values inherit global settings. |
| `workspaceDisplay.minimumCount` | Keep workspace slots 1 through this number visible, even when empty. Range: 0–50; default: 3. Other existing workspaces appear automatically. |
| `workspaceDisplay.itemSpacing` | Gaps between workspace/launcher items in pixels, 0–100. Default: 21. |
| `workspaceDisplay.normalLabels` | Replace numbered workspace labels, e.g. `"1": "Web"`. Default: `{}` (numbers). |
| `workspaceDisplay.specialLabels` | Replace special-workspace names, e.g. `"steam": ""`. Default: `{}` (names). Does not create workspaces. |

Inside a monitor entry, you can override `mode`, `topMediaMode`, `edgeSpacing`,
`hoverToggleEnabled`, `modules`, `workspaceDisplay`, `launchers`, and
`mouseBattery`. **`vpn` and `protonManager` settings are global only.**

To pin/unpin the focused hover bar:

```sh
qs -c bar ipc call bar toggle
```

Optional Hyprland binding: `bind = SUPER, C, exec, qs -c bar ipc call bar toggle`.
The command does nothing on `always`/`off` outputs or when toggling is disabled.

### Modules

Set a module to `true` to show it or `false` to hide it. All default to `true`
except **`protonManager`**, **`mouseBattery`**, and **`openAiUsage`**.

| Module | What you get |
| --- | --- |
| `workspaces` | Workspace buttons and special workspaces. |
| `tray` | Application icons and their menus. |
| `launcher` | App shortcuts revealed on hover. |
| `updates` | Available Arch update count; manual refresh. |
| `protonManager` | GE-Proton/CachyOS installs, confirmed cleanup, and umu selection. [Setup and safety](docs/proton-manager.md). |
| `media` | Top MPRIS music panel with scrolling track text and playback toggle. |
| `network` | Download/upload speeds and connection details. |
| `vpn` | Local VPN/router VPN indicator and DNS category. Requires `network`. |
| `wifiMenu` | Wi-Fi connections, saved networks, and credentials. Requires `network`. |
| `cpu` | CPU usage and sensor details. |
| `gpu` | AMD GPU usage/details; Intel/NVIDIA metrics are not supported. |
| `memory` | Memory usage and details. |
| `volume` | PipeWire volume and mute. |
| `bluetooth` | Adapter and device connect/disconnect controls. |
| `inputMethod` | Fcitx input-method status and cycling. |
| `brightness` | Display brightness and available keyboard backlight. |
| `battery` | Charge, health, power profiles, and supported charge limits. |
| `mouseBattery` | Supported WLMouse battery level; independent of laptop battery. |
| `openAiUsage` | ChatGPT/Codex subscription quota, reset times, and click-to-refresh. |
| `clock` | Time and date. |
| `calendar` | Monthly calendar popup. |
| `weather` | Open-Meteo location search and forecasts. Requires `calendar`. |
| `notifications` | SwayNC notification/DND status and panel launcher. |

Hiding a parent also hides dependent modules. Missing devices/tools show
unavailable data rather than breaking the bar. Module order is fixed.

### Shortcuts and optional settings

| Option | What it does |
| --- | --- |
| `launchers` | Ordered app-shortcut list. Omit to keep defaults; `[]` removes all shortcuts. |
| `launchers[].icon` | Required icon or text shown for a shortcut. |
| `launchers[].tooltip` | Optional hover text. Use `\n` for a new line. |
| `launchers[].leftCommand` / `rightCommand` | Program plus arguments for each click, e.g. `["qt6ct"]`. Omitted or `[]` does nothing. No shell expansion. |
| `mouseBattery.name` | Name displayed in the mouse tooltip. Default: `WLMouse Beast X`; does not change device detection. |
| `vpn.routerManagedSsids` | Exact Wi-Fi names where your router is configured for VPN. Default: `[]`. A matching name is **not proof** the router VPN is working. Local VPN takes priority. |
| `protonManager.compatibilityToolsDir` | Host folder containing Proton installations, not an individual version folder. |
| `protonManager.umuConfigPath` | Existing umu TOML config file to update. |
| `protonManager.sandboxCompatibilityToolsDir` | Same Proton folder as seen inside your gaming sandbox. Without a sandbox, use the host folder here too. |

Proton paths must be absolute, contain no `..`, and refer to an existing setup.
The example paths match this author's gaming PC, not necessarily yours.

<details>
<summary>VPN/DNS indicator</summary>

The VPN icon distinguishes local VPN, configured router VPN, no local VPN,
and unavailable status. The DNS dot shows NextDNS (mint), router (blue),
VPN/other (neutral), mixed (purple), or unavailable (muted red).
Colors identify resolver categories, **not security guarantees**.
Domain-specific split DNS, such as Tailscale name resolution, does not count
as a main Internet VPN/DNS route. Use `resolvectl status` for resolver details.

</details>

<details>
<summary>WLMouse battery setup</summary>

Supports Beast X wired and 1K receiver devices (vendor `36a7`, products
`a884`/`a882`). Install the bundled device-specific permission rule:

```sh
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell"
sudo install -m 0644 "$config_dir/bar/scripts/70-wlmouse.rules" /etc/udev/rules.d/70-wlmouse.rules
sudo udevadm control --reload-rules
sudo udevadm trigger --action=add --subsystem-match=hidraw
sudo udevadm settle
python3 "$config_dir/bar/scripts/wlmouse.py"
```

Reconnect the mouse/receiver if needed. The final command should print JSON
without sudo. Then enable `modules.mouseBattery`. Hover refreshes readings
with a 10-second cooldown; failed readings show `N/A`.

</details>

<details>
<summary>ChatGPT/Codex quota setup</summary>

Sign in to ChatGPT through OpenCode, then enable `modules.openAiUsage`.
This shows subscription allowance, **not billed API-key usage**. OpenCode
does not need to be running. Click the chip to refresh immediately.

The collector reads existing OpenAI OAuth credentials from OpenCode's local
database, with a legacy `auth.json` fallback when no usable v2 credential exists.
It never refreshes or edits credentials and only requests quota data from
`https://chatgpt.com/backend-api/wham/usage`. It does not send inference requests
or include tokens/account IDs/email in output.
**Do not put tokens or passwords in `bar-local.json` or sync authentication files.**
Expired logins must be renewed in OpenCode; failures show `N/A`.
This unofficial backend endpoint may change.

The bundled OpenAI SVG is from Simple Icons v13.21.0 (CC0); OpenAI retains its trademark.

</details>

<details>
<summary>Battery charge limits</summary>

Charge-limit controls require supported sysfs threshold files and narrowly
scoped permission for the existing `sudo -n` writes. Do not grant unrestricted
sudo access to enable them. Ordinary battery display needs no sudo setup.

</details>

## More information

- [Proton Manager: setup, usage, and safety](docs/proton-manager.md)
- [Development, testing, and troubleshooting](docs/development.md)
