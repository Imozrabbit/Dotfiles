# Quickshell Bar

A configurable bottom bar for **Hyprland**, built with [Quickshell](https://quickshell.org/).
Use it on multiple monitors, keep it visible or reveal it on hover, and choose
which features appear on each screen. Music appears in a separate top panel
or centered in the bottom bar.

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
(or `$XDG_CONFIG_HOME/quickshell/bar/`), excluding `tests/` but keeping
documentation. Then run:

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
  --exclude='*/bar/tests' \
  Dotfiles-thinkpad/ArchLinux/Quickshell/.config/quickshell/bar &&
mkdir -p "$config_dir" &&
rm -rf "$config_dir/bar" &&
mv "$stage/bar" "$config_dir/bar" &&
rm -rf "$stage" &&
qs -c bar -d
```

Your sibling `bar-local.json` and saved weather/Wi-Fi data stay untouched.
Tests remain in the GitHub repository but are excluded from this installation;
documentation is included.

</details>

### Optional tools

Install tools for features you use; missing tools leave those controls unavailable.

| Feature | Tools |
| --- | --- |
| Network / Wi-Fi / VPN / DNS | `ip`, `iw`, NetworkManager (`nmcli`), `resolvectl`; optional school VPN detection uses `systemctl` |
| Updates | `checkupdates` from `pacman-contrib` |
| Bluetooth | `bluetoothctl`; optional `ghostty` + `bluetui` for advanced controls |
| Brightness | `brightnessctl` |
| Input method | `fcitx5-remote` |
| Notifications | SwayNC (`swaync-client`) |
| Battery profiles | `powerprofilesctl` |
| AMD GPU name | `lspci` |
| Advanced Wi-Fi editor | `nm-connection-editor` |
| Default shortcuts | `nwg-look`, `qt6ct`, separate `wallpaper_switcher` config |
| Mouse battery / quota display | Python 3 |
| Proton Manager | Python 3.11+; optional `pacman` and `checkupdates` for package status |

## Configuration

Create `~/.config/quickshell/bar-local.json` beside the `bar/` folder,
not inside it. If you use `XDG_CONFIG_HOME`, use `$XDG_CONFIG_HOME/quickshell/bar-local.json`.

**Only include settings you want to change.** Missing settings use defaults.
Saving valid JSON applies changes immediately, without restarting. Invalid
fields are ignored; broken JSON keeps the last working configuration.
Save `{}` to reset to defaults.

### Full example

Most values below match defaults; workspace labels and monitor entries are
examples. Find monitor names with `hyprctl monitors`. Change host-specific
Proton paths before enabling Proton Manager.

<details>
<summary>Complete bar-local.json example (all supported options)</summary>

```json
{
  "mode": "always",
  "topMediaMode": "hover",
  "mediaPosition": "top",
  "edgeSpacing": 14,
  "hoverToggleEnabled": true,
  "dns": {
    "providers": [
      {
        "id": "quad9",
        "label": "Quad9",
        "ipv4": ["9.9.9.9", "149.112.112.112"],
        "ipv6": ["2620:fe::fe", "2620:fe::9"]
      }
    ],
    "preferredProvider": "quad9"
  },
  "vpn": {
    "routerManagedSsids": [],
    "schoolService": "",
    "schoolInterface": "ppp0",
    "schoolName": "School VPN"
  },
  "mouseBattery": { "name": "WLMouse Beast X" },
  "openAiUsage": { "display": "weekly" },
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
    "DP-1": {
      "mode": "always",
      "topMediaMode": "hover",
      "mediaPosition": "bottom",
      "openAiUsage": { "display": "both" }
    },
    "HDMI-A-1": {
      "mode": "hover",
      "topMediaMode": "always",
      "mediaPosition": "top",
      "edgeSpacing": 4,
      "hoverToggleEnabled": false,
      "openAiUsage": { "display": "fiveHour" },
      "workspaceDisplay": { "itemSpacing": 8 },
      "modules": { "notifications": false }
    },
    "DP-2": { "mode": "off", "topMediaMode": "off" }
  }
}
```

</details>

### Display and layout

| Option | What it does |
| --- | --- |
| `mode` | Bottom bar: `always` stays visible and reserves 35 px; `hover` reveals from a 2 px bottom edge; `off` removes it. Default: `always`. |
| `mediaPosition` | Music placement: `top` (default) uses a separate panel; `bottom` centers music between bottom-bar sections, capped at 70% of that gap. Bottom music follows bar hover/pinning and `mode`; `topMediaMode` is ignored there. |
| `topMediaMode` | Top music panel: `hover`, `always`, or `off`. Default: `hover`. Appears only when a player is available, even if paused. Independent of bottom bar mode; applies only with `mediaPosition: "top"`. |
| `edgeSpacing` | Left/right margins in pixels, 0–100. Default: 14. |
| `hoverToggleEnabled` | Allow the toggle command to pin/unpin a hover bar. Default: `true`. Pinned bars reserve 35 px. Does not affect mouse hover or top media. |
| `monitors` | Settings for individual screens. Use exact names from `hyprctl monitors`; omitted values inherit global settings. |
| `workspaceDisplay.minimumCount` | Keep workspace slots 1 through this number visible, even when empty. Range: 0–50; default: 3. Other existing workspaces appear automatically. |
| `workspaceDisplay.itemSpacing` | Gaps between workspace/launcher items in pixels, 0–100. Default: 21. |
| `workspaceDisplay.normalLabels` | Replace numbered workspace labels, e.g. `"1": "Web"`. Default: `{}` (numbers). |
| `workspaceDisplay.specialLabels` | Replace special-workspace names, e.g. `"steam": ""`. Default: `{}` (names). Does not create workspaces. |

Inside a monitor entry, you can override `mode`, `topMediaMode`, `mediaPosition`, `edgeSpacing`,
`hoverToggleEnabled`, `modules`, `workspaceDisplay`, `launchers`,
`mouseBattery`, and `openAiUsage`. **`dns`, `vpn`, and `protonManager` settings are global only.**

Example: DP-1 uses bottom music and both quota periods; HDMI-A-1 uses top music
and 5-hour quota. Other monitors inherit global settings. Modules must be enabled.

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
| `tray` | Inline app icons: left-click activates (or opens menu-only items); right-click opens non-empty menus. No separate drawer. |
| `launcher` | App shortcuts revealed on hover. |
| `updates` | Available Arch update count; manual refresh. |
| `protonManager` | GE-Proton/CachyOS installs, confirmed cleanup, and umu selection. [Setup and safety](docs/proton-manager.md). |
| `media` | MPRIS music in the selected top/bottom position, with scrolling track text and playback toggle. |
| `network` | Download/upload speeds and connection details. |
| `vpn` | Local VPN/router VPN indicator and DNS category. Requires `network`. |
| `wifiMenu` | Wi-Fi connections, saved networks, credentials, and per-profile Default/Quad9 DNS selection. Requires `network`; DNS selection also requires Python 3. |
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

Tray menus hold hover bars open without pinning/reserving space; hiding the
tray closes its menu. Empty tray/Proton sections have no leading separator.

### Shortcuts and optional settings

| Option | What it does |
| --- | --- |
| `launchers` | Ordered app-shortcut list. Omit to keep defaults; `[]` removes all shortcuts. |
| `launchers[].icon` | Required icon or text shown for a shortcut. |
| `launchers[].tooltip` | Optional hover text. Use `\n` for a new line. |
| `launchers[].leftCommand` / `rightCommand` | Program plus arguments for each click, e.g. `["qt6ct"]`. Omitted or `[]` does nothing. No shell expansion. |
| `mouseBattery.name` | Name displayed in the mouse tooltip. Default: `WLMouse Beast X`; does not change device detection. |
| `openAiUsage.display` | Quota remaining on the chip: `weekly` (default), `fiveHour`, or `both`. Both shows weekly first, then 5-hour, separated by a dot. Calendar/timer icons identify each period. |
| `dns.providers` | DNS choices in addition to built-in Default. Defaults to Quad9 only. Entries have a unique `id`, `label`, and `ipv4`/`ipv6` address lists. Invalid entries are hidden with a configuration warning. `[]` leaves only Default. |
| `dns.preferredProvider` | Suggested choice for new non-home networks; default `quad9`. Unknown IDs fall back to the first valid provider or Default. Does not rewrite existing profiles. |
| `vpn.routerManagedSsids` | Exact Wi-Fi names where your router is configured for VPN. Default: `[]`. A matching name is **not proof** the router VPN is working. Local VPN takes priority, but tooltip retains router context. |
| `vpn.schoolService` | OpenFortiVPN system service to observe, e.g. `openfortivpn@Unistra.service`. Default: `""` (disabled; no school queries). Requires a `Type=notify` unit, as shipped by OpenFortiVPN. Never starts/stops the service or reads its credentials. |
| `vpn.schoolInterface` | Dedicated school PPP interface to check alongside service readiness. Default: `ppp0`; set to your actual school interface. Must not refer to an unrelated PPP tunnel. |
| `vpn.schoolName` | School VPN label in tooltip. Default: `School VPN`; use `Unistra` for that service. |
| `protonManager.compatibilityToolsDir` | Host folder containing Proton installations, not an individual version folder. |
| `protonManager.umuConfigPath` | Existing umu TOML config file to update. |
| `protonManager.sandboxCompatibilityToolsDir` | Same Proton folder as seen inside your gaming sandbox. Without a sandbox, use the host folder here too. |

Proton paths must be absolute, contain no `..`, and refer to an existing setup.
The example paths match this author's gaming PC, not necessarily yours.

### Wi-Fi, VPN, and DNS

Expand a connected/saved Wi-Fi card to choose **Default** or a configured DNS
provider. Choices are saved per profile; **Test** checks each provider server
without changing settings. Home Wi-Fi listed in `vpn.routerManagedSsids` is
locked to automatic/router-advertised DNS; saved manual DNS is reset there.
Other custom settings stay untouched until explicitly replaced.

VPN detection and DNS reporting are independent. Router VPN is an assumption
from configured Wi-Fi names; colors are **not security guarantees**. School
VPN plus assumed router VPN produces an amber nesting/overhead warning.

[Network guide: DNS application, prompts, indicators, and school VPN setup](docs/network.md).

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

Add `"openAiUsage": { "display": "weekly" }` to your override; change `display`
to `"fiveHour"` or `"both"` as needed. Chips show **percentage remaining**, not used:
`󰨳 64%`, `󰔛 25%`, or `󰨳 64% · 󰔛 25%`. Tooltip always includes both
periods and reset times. Missing readings show `N/A` for that period.

Tooltip banked resets use five circles: `● ○ ○ ○ ○` means one available;
`● ● ● ● ● +2` means seven. Slots are visual, not a capacity limit. Zero
shows empty circles; unknown data shows `Unavailable` without affecting
quotas. Resets are not redeemed and individual expiration details are not fetched.

The collector reads existing OpenAI OAuth credentials from OpenCode's local
database, with a legacy `auth.json` fallback when no usable v2 credential exists.
It never refreshes or edits credentials and only requests quota data from
`https://chatgpt.com/backend-api/wham/usage`. It does not send inference requests
or include tokens/account IDs/email in output.
**Do not put tokens or passwords in `bar-local.json` or sync authentication files.**
Expired logins must be renewed in OpenCode; failures show `N/A`.
This unofficial backend endpoint may change.

</details>

<details>
<summary>Battery charge limits</summary>

Charge-limit controls require supported sysfs threshold files and narrowly
scoped permission for the existing `sudo -n` writes. Do not grant unrestricted
sudo access to enable them. Ordinary battery display needs no sudo setup.

</details>

## More information

- [Wi-Fi, DNS choices, and VPN indicators](docs/network.md)
- [Proton Manager: setup, usage, and safety](docs/proton-manager.md)
- [Development, testing, and troubleshooting](docs/development.md)
