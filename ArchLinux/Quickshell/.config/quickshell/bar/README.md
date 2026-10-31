# Quickshell Bar

A configurable multi-monitor bar for **Hyprland**, built with
[Quickshell](https://quickshell.org/): workspaces, tray, media, network, system
stats, device controls, calendar, and weather. Optional modules add Proton
Manager, peripheral batteries, and ChatGPT/Codex quota.

## Install and run

Requires **Hyprland**, **Quickshell** (tested with 0.3.1), Qt 6 Quick Controls,
Qt 6 Quick Layouts, and `Qt5Compat.GraphicalEffects`. Install **JetBrainsMono
Nerd Font Propo** and **Atkinson Hyperlegible Next** for icons and text.
Audio controls need PipeWire and a session manager.

Develop and test on the main machine; other machines use client copies.
Copy published `bar/` to `~/.config/quickshell/bar/` (or
`$XDG_CONFIG_HOME/quickshell/bar/`), including `docs/`. When copying the main
checkout instead, omit Git-ignored files and `.gitignore`. Then run:

```sh
qs -c bar -d
```

Use `qs -c bar` without `-d` to see errors in your terminal. To start on login,
add `exec-once = qs -c bar -d` to your Hyprland configuration.

<details>
<summary>Download or update directly from GitHub</summary>

Requires `curl` and GNU `tar`. **Client update replaces the entire installed
`bar/`, including local edits. Do not run it over the main development checkout.**
Keep personal settings in sibling `bar-local.json`.
Stop only the bar with `qs -c bar kill` before updating; skip this if it is not running.
Do not stop other Quickshell configurations, especially a running lockscreen.

```sh
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell"
stage=$(mktemp -d)
curl -fL https://codeload.github.com/Imozrabbit/Dotfiles/tar.gz/refs/heads/thinkpad \
  -o "$stage/dotfiles.tar.gz" &&
tar -xzf "$stage/dotfiles.tar.gz" -C "$stage" --strip-components=5 \
  --exclude='*/bar/tests' --exclude='*/__pycache__' \
  --exclude='*/bar/.qmlls.ini' --exclude='*/bar/.gitignore' \
  --exclude='*.py[cod]' --exclude='*.qmlc' --exclude='*.jsc' \
  Dotfiles-thinkpad/ArchLinux/Quickshell/.config/quickshell/bar &&
mkdir -p "$config_dir" &&
rm -rf "$config_dir/bar" &&
mv "$stage/bar" "$config_dir/bar" &&
rm -rf "$stage" &&
qs -c bar -d
```

Host settings and saved weather/Wi-Fi data stay untouched. Documentation is
included; tests, editor files and generated artifacts are Git-ignored and not
published. Archive exclusions also cover older published revisions.

</details>

### Optional tools

Install tools for features you use; missing tools leave those controls unavailable.

| Feature | Tools |
| --- | --- |
| Network / Wi-Fi / VPN / DNS | `ip`, `iw`, NetworkManager (`nmcli`), `resolvectl`; strict DNS-over-TLS also requires NetworkManager's `systemd-resolved` DNS backend and `busctl`; optional school VPN detection uses `systemctl` |
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
  "backgrounds": {
    "workspaces": "#99000000",
    "media": "#E6252525",
    "network": "#20302F",
    "cpu": "#292432",
    "gpu": "#242D2C",
    "memory": "#222A34",
    "controls": "#252733",
    "openAiUsage": "#30291F",
    "timeDate": "#211E1C",
    "calendar": "#E61F1F1F",
    "wifi": "#991F1F1F",
    "bluetooth": "#E61F1F1F",
    "battery": "#E61F1F1F",
    "protonManager": "#E61C1C22",
    "tooltips": "#CC1F1F1F"
  },
  "dns": {
    "providers": [
      {
        "id": "quad9",
        "label": "Quad9",
        "tls": false,
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
    "djiMicBattery": false,
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
      "backgrounds": { "calendar": "#CC1F1F1F", "tooltips": "#991F1F1F" },
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
`mouseBattery`, `openAiUsage`, and `backgrounds`. **`dns`, `vpn`, and `protonManager` path settings are global only.**

Example: DP-1 uses bottom music and both quota periods; HDMI-A-1 uses top music
and 5-hour quota. Other monitors inherit global settings. Modules must be enabled.

To pin/unpin the focused hover bar:

```sh
qs -c bar ipc call bar toggle
```

Optional Hyprland binding: `bind = SUPER, C, exec, qs -c bar ipc call bar toggle`.
The command does nothing on `always`/`off` outputs or when toggling is disabled.

### Background colors

Set global colors in `backgrounds`. Override individual colors under
`monitors.<name>.backgrounds`; omitted monitor keys inherit global colors.
Missing global keys keep the current built-in defaults shown below and in the
full example. An empty monitor object (`"backgrounds": {}`) inherits everything.
Removing an override restores inheritance; saving `{}` resets all settings.

Colors accept `#RRGGBB`, `#AARRGGBB` (**alpha first**, unlike Hyprglass tint
colors), or `transparent`. For example, `#801F1F1F` is about 50% opaque.
Invalid colors and unknown keys are ignored. Changes apply live, including open
panels and tooltips; no restart or Hyprglass dependency is required.

| Background key | Surface | Default |
| --- | --- | --- |
| `workspaces` | Shared workspace/tray/launcher/update/Proton-icon box | `#99000000` |
| `media` | Music box, in either top or bottom position | `#E6252525` |
| `network` | Network/VPN/DNS box | `#20302F` |
| `cpu` | CPU segment | `#292432` |
| `gpu` | GPU segment | `#242D2C` |
| `memory` | Memory segment | `#222A34` |
| `controls` | Shared volume/Bluetooth/input-method/brightness box **and volume/brightness popups** | `#252733` |
| `openAiUsage` | ChatGPT/Codex quota box | `#30291F` |
| `timeDate` | Shared battery/mouse/microphone/clock/notification box | `#211E1C` |
| `calendar` | Calendar/weather panel | `#E61F1F1F` |
| `wifi` | Wi-Fi panel | `#991F1F1F` |
| `bluetooth` | Bluetooth panel | `#E61F1F1F` |
| `battery` | Battery panel | `#E61F1F1F` |
| `protonManager` | Proton Manager panel (not its path settings) | `#E61C1C22` |
| `tooltips` | All bar tooltips, including network and launcher tooltips | `#CC1F1F1F` |

Each bar and its tooltips use that output's colors. Shared Wi-Fi and Proton
panels follow the output that opened them: open from DP-1 to use DP-1 overrides,
or from another output to use its overrides/global defaults. Services stay shared.
Panel backgrounds are independent; changing calendar does not recolor battery
or Bluetooth. Shared bar boxes stay shared. Text, borders, and other palette
colors are unchanged; this is not a full-theme editor.

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
| `wifiMenu` | Wi-Fi connections, saved networks, credentials, and per-profile DNS provider selection, including strict DNS-over-TLS. Requires `network`; DNS selection also requires Python 3. |
| `cpu` | CPU usage and sensor details. |
| `gpu` | AMD GPU usage/details; Intel/NVIDIA metrics are not supported. |
| `memory` | Memory usage and details. |
| `volume` | PipeWire volume and mute. |
| `bluetooth` | Adapter and device connect/disconnect controls. |
| `inputMethod` | Fcitx input-method status and cycling. |
| `brightness` | Display brightness and available keyboard backlight. |
| `battery` | Charge, health, power profiles, and supported charge limits. |
| `mouseBattery` | Supported WLMouse battery level; independent of laptop battery. |
| `djiMicBattery` | DJI Mic Mini transmitter battery icons and charging status, beside mouse in the same box. Disabled by default; requires Python 3, PyUSB, libusb, and USB access rule below. |
| `openAiUsage` | ChatGPT/Codex subscription quota, reset times, and click-to-refresh. |
| `clock` | Time and date. |
| `calendar` | Monthly calendar popup. |
| `weather` | Open-Meteo location search and forecasts. Requires `calendar`. |
| `notifications` | SwayNC notification/DND status and panel launcher. |

Hiding a parent also hides dependent modules. Missing devices/tools show
unavailable data rather than breaking the bar. Module order is fixed.

Tray menus hold hover bars open without pinning/reserving space; hiding the
tray closes its menu. Empty tray/Proton sections have no leading separator.
Tray/Proton icons use compact 8 px gaps; section dividers have 13 px gaps on each
side. Workspace/launcher icons retain `workspaceDisplay.itemSpacing`.

### Shortcuts and optional settings

#### Tooltip layers and Hyprglass

Bottom and top media windows use **`quickshell-bottom-bar`** and
**`quickshell-top-media`**, respectively. Target these names instead of the
generic `quickshell` namespace in compositor layer rules.

All bar tooltips use the layer-shell namespace **`quickshell-bar-tooltip`**,
including network, system statistics, batteries, launchers, Proton Manager,
quota, Bluetooth, and media. Tooltips stay on their source output, above the
bottom bar or below top media, without taking focus or reserving screen space.
Volume, brightness, and tray menus remain popups, not tooltip layers.

For Hyprglass versions with the Lua API, add this to your Hyprland configuration
after loading the plugin:

```lua
if hl.plugin.hyprglass then
    local hg = hl.plugin.hyprglass
    hg.config({ layers = { enabled = true } })
    hg.layer("quickshell-bar-tooltip", { preset = "subtle" })
end
```

Open a tooltip and use `hyprctl layers` to verify the namespace. Hyprglass is
optional; its layer support must match your Hyprland version. Adjust tooltip
color/alpha with `backgrounds.tooltips`; the default remains unchanged.

#### Optional settings

| Option | What it does |
| --- | --- |
| `launchers` | Ordered app-shortcut list. Omit to keep defaults; `[]` removes all shortcuts. |
| `launchers[].icon` | Required icon or text shown for a shortcut. |
| `launchers[].tooltip` | Optional hover text. Use `\n` for a new line. |
| `launchers[].leftCommand` / `rightCommand` | Program plus arguments for each click, e.g. `["qt6ct"]`. Omitted or `[]` does nothing. No shell expansion. |
| `mouseBattery.name` | Name displayed in the mouse tooltip. Default: `WLMouse Beast X`; does not change device detection. |
| `openAiUsage.display` | Quota remaining on the chip: `weekly` (default), `fiveHour`, or `both`. Both shows weekly first, then 5-hour, separated by a dot. Calendar/timer icons identify each period. |
| `dns.providers` | DNS choices in addition to built-in Default. Defaults to Quad9 only. Entries have a unique `id`, `label`, and `ipv4`/`ipv6` address lists. Optional `tls: true` requires `IP#TLS-hostname` entries and enables strict DoT without plaintext fallback. Invalid entries are hidden with a configuration warning. `[]` leaves only Default. |
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

Expand a connected/saved Wi-Fi card to choose **Auto** (network-advertised DNS) or a configured DNS
provider. Selection stays pending until **Confirm** saves it per profile.
**Test** checks the pending provider's servers without saving; **Cancel** restores
the saved choice. Home Wi-Fi listed in `vpn.routerManagedSsids` is
locked to automatic/router-advertised DNS; saved manual DNS is reset there.
Other custom settings stay untouched until explicitly replaced.

VPN detection and DNS reporting are independent. Router VPN is an assumption
from configured Wi-Fi names; colors are **not security guarantees**. School
VPN plus assumed router VPN produces an amber nesting/overhead warning.

[Network guide: DNS application, prompts, indicators, and school VPN setup](docs/network.md).

For profile-aware NextDNS, use the [strict DoT provider example](docs/network.md#nextdns-over-tls).
NextDNS profile IDs stay in host-local configuration, not source defaults.

### Optional module setup

Device permissions and account setup are covered in the [setup guide](docs/setup.md):

- [WLMouse battery](docs/setup.md#wlmouse-battery)
- [DJI Mic Mini battery](docs/setup.md#dji-mic-mini)
- [ChatGPT/Codex quota](docs/setup.md#quota)
- [Battery charge limits](docs/setup.md#battery-charge-limits)

The DJI Mic Mini USB access rule referenced above is bundled in
`scripts/70-dji-mic-mini.rules`:

```udev
SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="2ca3", ATTR{idProduct}=="4011", TAG+="uaccess"
```

## More information

- [Optional setup and troubleshooting](docs/setup.md)
- [Wi-Fi, DNS choices, and VPN indicators](docs/network.md)
- [Proton Manager: setup, usage, and safety](docs/proton-manager.md)

Development tests and instructions stay in Git-ignored `tests/` on the main
machine. Fresh Git clones and client copies do not include them.
