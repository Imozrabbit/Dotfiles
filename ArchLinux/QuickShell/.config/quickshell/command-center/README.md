# Quickshell Command Center

A configurable control panel for **Hyprland**, built with
[Quickshell](https://quickshell.org/): notifications, media, volume, microphone,
display brightness, power buttons, and optional quick-action tiles.

It includes its own notification service. **SwayNC is not required.**

## Install, update and run

Requires **Hyprland**, a recent **Quickshell** build with notification, Bluetooth,
PipeWire, and MPRIS support, and Qt 6 Quick Controls and Quick Layouts.
Install **JetBrainsMono Nerd Font** for icons and **Atkinson Hyperlegible Next**
for text. Notification storage uses standard GNU `coreutils` and `findutils`.

Copy the complete `command-center/` folder to
`~/.config/quickshell/command-center/` (or
`$XDG_CONFIG_HOME/quickshell/command-center/`), preserving executable permissions.
When copying the development checkout, omit Git-ignored files and `.gitignore`.

**Before starting, stop any other notification service**, such as SwayNC, Dunst,
or Mako, and remove its automatic startup entry if you are replacing it.
Only one notification service can run in your session. You do not need to
uninstall the old service.

Run these commands in a terminal inside your Hyprland session:

```sh
qs -c command-center -d
qs -c command-center ipc call command-center toggle
```

The first command starts the service in the background. The panel starts hidden;
the second command opens it. Use `qs -c command-center` without `-d` to see
errors in your terminal.

To start on login, add this line to your Hyprland configuration:

```ini
exec-once = qs -c command-center -d
```

<details>
<summary>Install or update directly from GitHub</summary>

Requires `curl` and GNU `tar`. This downloads the repository's **default branch**,
which must already contain `command-center/`. For another published branch,
replace `/HEAD` at the end of the download URL with `/refs/heads/YOUR_BRANCH`.

Use the same block for first installation and updates. It downloads and checks
the new copy before stopping command-center, replacing its folder, and restarting
it. A failed download or extraction leaves the old installation running.

**This replaces the entire installed `command-center/` folder, including local
edits. Use it only for client copies, never your development checkout.** The
block refuses symlinks and copies containing development files. It does not
install dependencies, add startup entries, or change sibling settings or saved
notification data. Other Quickshell configurations are not stopped.

```sh
(
    set -eu
    config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell"
    install_dir="$config_dir/command-center"
    if [ -L "$install_dir" ] || [ -e "$install_dir/.git" ] \
        || [ -e "$install_dir/.gitignore" ] || [ -d "$install_dir/tests" ]; then
        printf '%s\n' "Refusing to replace a symlink or development copy: $install_dir" >&2
        exit 1
    fi
    stage=$(mktemp -d)
    trap 'rm -rf -- "$stage"' EXIT
    curl -fL https://codeload.github.com/Imozrabbit/Dotfiles/tar.gz/HEAD \
        -o "$stage/dotfiles.tar.gz"
    tar -xzf "$stage/dotfiles.tar.gz" -C "$stage" --strip-components=5 \
        --wildcards \
        --exclude='*/command-center/tests' \
        --exclude='*/command-center/dev' \
        --exclude='*/command-center/tmp' \
        --exclude='*/command-center/AGENTS.md' \
        --exclude='*/command-center/.gitignore' \
        '*/ArchLinux/Quick[Ss]hell/.config/quickshell/command-center'
    test -f "$stage/command-center/shell.qml"
    mkdir -p "$config_dir"
    if [ -d "$install_dir" ]; then
        instances=$(qs -p "$install_dir" list)
        case "$instances" in
            "No running instances for "*) ;;
            *) qs -p "$install_dir" kill ;;
        esac
    fi
    rm -rf -- "$install_dir"
    mv -T -- "$stage/command-center" "$install_dir"
    qs -c command-center -d
)
```

The service starts with the panel hidden; use the toggle command above to open
it. The archive pattern accepts both `QuickShell` and `Quickshell` directory names.

</details>

Keep sibling `command-center-local.json` and saved notification data in place.
When moving to another computer, copy only the module and settings you want to
reuse, not notification history or thumbnails.

### Optional tools

Install or configure only what you need. Missing tools or devices leave the
corresponding controls unavailable.

| Feature | Requirements |
| --- | --- |
| Volume and microphone | PipeWire and a session manager, such as WirePlumber. |
| Media controls | A player that exposes MPRIS desktop media controls. |
| Audio visualizer | `cava` built with the PipeWire input backend. |
| Built-in display brightness | `brightnessctl` and permission to change the backlight. |
| External display brightness | `ddcutil`, access to the monitor's I²C device, and DDC/CI enabled in the monitor's own menu. |
| Network and VPN tiles | NetworkManager (`nmcli`); the network toggle also needs the Rofi confirmation setup below. |
| Bluetooth tile | BlueZ, a Bluetooth adapter, and `busctl` from systemd. |
| Power confirmations | `rofi`, XWayland for the bundled `-x11` prompts, and a readable `~/.config/rofi/themes/confirmation-box.rasi`. With `XDG_CONFIG_HOME`, the theme goes under that directory instead. |
| Shutdown and reboot | `hyprshutdown` and a Hyprland version supporting the Lua dispatcher used by the bundled commands. See Power buttons below. |
| Lock, suspend, hibernate | systemd; locking needs an existing screen-locker integration, and hibernation needs a working system hibernation setup. |
| Stay-awake tile | An existing `idle-inhibit.service` user unit. See Optional setup below. |
| LocalSend tile | A separately configured firewall helper and narrowly scoped non-interactive `sudo` permission. Installing LocalSend alone is not enough. |
| Night-light tile | `hyprsunset` already running, with working `hyprctl hyprsunset` commands. See [Hyprsunset setup](#hyprsunset-screen-warmth). |

The Rofi theme, idle-inhibit unit, and LocalSend helper are **not bundled**.
Your separate `Confirm_rofi` launcher scripts are not required by command-center;
keep them if your application launcher still uses them.

## Configuration

Create `~/.config/quickshell/command-center-local.json` beside the
`command-center/` folder, not inside it. With `XDG_CONFIG_HOME`, use
`$XDG_CONFIG_HOME/quickshell/command-center-local.json`.

**Only include settings you want to change.** Missing settings use defaults.
Saving valid JSON applies changes immediately, without restarting. Invalid fields
fall back to defaults or are ignored; broken JSON keeps the last working
configuration. Save `{}` to restore defaults.

JSON needs double quotes, no comments, and no trailing commas. Lists replace the
whole corresponding default list: keep every entry you still want, in the order
you want it. An empty list (`[]`) hides that list's contents.

**Quick actions are empty by default.** Add tiles using the example below.

### Full example

These are the built-in defaults, including every configurable palette color.
You do not need to copy the whole example.

<details>
<summary>Complete command-center-local.json example</summary>

```json
{
  "panel": { "width": 300, "height": 900 },
  "toast": { "width": 350, "height": 0 },
  "background": { "color": "#0f1416", "opacity": 0.4 },
  "padding": { "left": 16, "right": 16 },
  "colors": {
    "panelBorder": "#00000000",
    "section": "#40171c1f",
    "sectionAlt": "#40171c1f",
    "mediaSurface": "#661b2023",
    "mediaSpectrum": "#88d0ec",
    "contextMenuBackground": "#1b2023",
    "notificationSurface": "#661b2023",
    "toastBackground": "#8c161616",
    "toastButtonBackground": "#80343b40",
    "sectionBorder": "#00000000",
    "text": "#dee3e6",
    "muted": "#bfc8cc",
    "tile": "#661b2023",
    "tileHover": "#992f3437",
    "gridTile": "#661b2023",
    "gridTileHover": "#992f3437",
    "sliderTrack": "#661b2023",
    "tileActive": "#88d0ec",
    "onActive": "#003544",
    "tileBorder": "#00000000",
    "activeBorder": "#00000000",
    "hoverBorder": "#00000000",
    "bevel": "#00000000",
    "danger": "#ffb4ab",
    "warning": "#c3c3eb",
    "powerLock": "#88d0ec",
    "powerLogout": "#ffb786",
    "powerSuspend": "#f2d58a",
    "powerHibernate": "#a8c7fa"
  },
  "media": { "cavaEnabled": true, "sourceNames": {} },
  "quickActions": [],
  "powerActions": [
    { "id": "hibernate", "enabled": true, "tooltip": "Hibernate", "command": "./power/actions/confirm.sh hibernate" },
    { "id": "suspend", "enabled": true, "tooltip": "Suspend", "command": "./power/actions/confirm.sh suspend" },
    { "id": "logout", "enabled": true, "tooltip": "Log out", "command": "./power/actions/confirm.sh logout" },
    { "id": "lock", "enabled": true, "tooltip": "Lock session", "command": "/usr/bin/loginctl lock-session" },
    { "id": "reboot", "enabled": true, "tooltip": "Reboot", "command": "./power/actions/confirm.sh reboot" },
    { "id": "poweroff", "enabled": true, "tooltip": "Power off", "command": "./power/actions/confirm.sh poweroff" }
  ],
  "sliders": [
    { "type": "volume", "length": 2, "enabled": true },
    { "type": "microphone", "length": 1, "enabled": true },
    { "type": "brightness", "length": 2, "enabled": true }
  ],
  "sections": [
    { "id": "quickActions", "enabled": true, "spacingBefore": 12 },
    { "id": "media", "enabled": true, "spacingBefore": 6 },
    { "id": "sliders", "enabled": true, "spacingBefore": 12 },
    { "id": "notifications", "enabled": true, "spacingBefore": 8 }
  ]
}
```

</details>

### Display and layout

| Option | What it does |
| --- | --- |
| `panel.width` / `panel.height` | Panel size in pixels. Positive whole numbers; defaults: 300 × 900. The panel fits within the screen. |
| `toast.width` | Notification popup width in pixels. Positive whole number; default: 350. Limited to the available screen width. |
| `toast.height` | Height of each popup. Default `0` fits its content; a positive whole number requests a fixed height, limited to the screen. |
| `background.color` | Panel background in `#RRGGBB` format. Default: `#0f1416`. |
| `background.opacity` | Background opacity from 0 (transparent) to 1 (solid). Default: 0.4. |
| `padding.left` / `padding.right` | Horizontal content padding in pixels. Non-negative numbers; their sum must not exceed 64. Default: 16 each. |
| `sections` | Ordered list of `quickActions`, `media`, `sliders`, and `notifications`. Each entry has `id`, `enabled` (default `true`), and non-negative whole-number `spacingBefore` in pixels. |
| `sliders` | Ordered list of `volume`, `microphone`, and `brightness`. Each entry has `type`, `enabled` (default `true`), and `length`: 1 for half-width or 2 for full-width. |

Power buttons stay above the ordered sections. Setting `enabled` to `false`
hides a control; it does not turn off its device or service. Hiding the
notifications section does not stop notification popups.

### Colors

Override individual colors under `colors`; omitted entries keep the defaults
shown in the full example. Use `#RRGGBB` or `#AARRGGBB`, with **alpha first**.
For example, `#801F1F1F` is about 50% opaque. Use `#00000000` for transparent.
This differs from `background.color`, which uses separate `background.opacity`.

| Color keys | Surface or role |
| --- | --- |
| `panelBorder`, `sectionBorder` | Panel and section borders. |
| `section`, `sectionAlt` | Section backgrounds. |
| `mediaSurface`, `mediaSpectrum` | Media card and audio visualizer. |
| `contextMenuBackground` | Context menus, including monitor selection. |
| `notificationSurface` | Notification history cards. |
| `toastBackground`, `toastButtonBackground` | Notification popups and their buttons. |
| `text`, `muted` | Main and secondary text. |
| `tile`, `tileHover` | General buttons and their hover color. |
| `gridTile`, `gridTileHover` | Quick-action tiles and their hover color. |
| `sliderTrack` | Unfilled slider track. |
| `tileActive`, `onActive` | Active accent and text/icons on that accent. |
| `tileBorder`, `activeBorder`, `hoverBorder`, `bevel` | Button edges and decorative highlights. |
| `danger`, `warning` | Warning and destructive-action accents. |
| `powerLock`, `powerLogout`, `powerSuspend`, `powerHibernate` | Individual power-button accents. |

### Quick actions

Add a `quickActions` list to your local file. This example shows the available
controls; the four requiring extra host setup start hidden. Change their
`enabled` values only after setting them up.

```json
{
  "quickActions": [
    { "id": "dnd", "icon": "󰂛", "tooltip": "Do not disturb" },
    { "id": "network", "icon": "󰖩", "tooltip": "Networking" },
    { "id": "bluetooth", "icon": "󰂯", "tooltip": "Bluetooth" },
    { "id": "vpn", "icon": "󰖂", "title": "VPN", "display": "details", "defaultProfile": "My VPN", "profileNames": { "My VPN": "Home" }, "enabled": false },
    { "id": "idle-inhibit", "icon": "󰅶", "title": "Stay awake", "enabled": false },
    { "id": "localsend", "icon": "󰒍", "tooltip": "LocalSend LAN access", "scriptPath": "~/.config/nftables/scripts/localsend-mode.py", "enabled": false },
    { "id": "hyprsunset", "icon": "󰖔", "tooltip": "Night light", "temperature": 4500, "enabled": false }
  ]
}
```

Merge this list into an existing file rather than adding a second `quickActions`
key. Remove entries you do not want. Built-in tiles show the actual service
state, not a separately configured on/off value.

| ID | What it controls |
| --- | --- |
| `dnd` | Do Not Disturb for this notification service. |
| `network` | All NetworkManager networking, not just Wi-Fi. Asks for confirmation; turning it off can disconnect SSH and downloads. |
| `bluetooth` | Bluetooth adapter power, not individual pairing or device connections. |
| `vpn` | Saved NetworkManager VPN/WireGuard profiles. Connects `defaultProfile` when none are active; turning it off disconnects **all** active VPN/WireGuard profiles. |
| `idle-inhibit` | Starts/stops the `idle-inhibit.service` user unit. |
| `localsend` | The external helper's LocalSend LAN allowance, not the entire firewall or the LocalSend application. |
| `hyprsunset` | Applies the configured color temperature or restores the identity filter. Does not start or stop Hyprsunset. |

<details>
<summary>Quick-action options</summary>

| Option | What it does |
| --- | --- |
| `id` | One of the built-in IDs above. Other IDs are display-only previews, not custom command launchers. |
| `icon` | Required non-empty icon or short text. |
| `enabled` | Show the tile. Default: `true`. |
| `tooltip` | Hover text; also used as the title when `title` is missing. Default: empty. |
| `tooltipOn` / `tooltipOff` | Optional hover text for the current on/off state. |
| `display` | `icon` or `details`. Detailed tiles occupy two columns and show a title and status. Default: `icon`, except `idle-inhibit`, which defaults to `details`. |
| `title` | Text on a detailed tile. Defaults to `tooltip`. |
| `type` | `normal` (default) or `toggle` for display-only previews. Built-in tiles always follow their service state. |
| `active` / `details` | Initial on/off state and sample status text for previews. Default: `false` / empty. Ignored for built-in tiles. |
| VPN `defaultProfile` | Exact saved NetworkManager profile name. Default: `CH-Zurich`; replace this with your own. The module does not create VPN profiles. |
| VPN `profileNames` | Display-name replacements, for example `{ "My VPN": "Home" }`. Default: `{}`. Does not rename the real profile. |
| LocalSend `scriptPath` | Absolute path or `~/` path to the external helper. Default: `~/.config/nftables/scripts/localsend-mode.py`. |
| Hyprsunset `temperature` | Whole-number color temperature from 1000 to 20000 K. Default: 4500. |

Put VPN, LocalSend, and Hyprsunset options inside their corresponding tile.
If you repeat a built-in ID, its first enabled entry supplies the service options.

</details>

### Power buttons

`powerActions` controls the order and visibility of `hibernate`, `suspend`,
`logout`, `lock`, `reboot`, and `poweroff`. Each entry accepts `id`, `enabled`,
`tooltip`, and `command`. Omit `command` to keep that action's bundled default.

All bundled actions except lock ask for confirmation. Only an exact **Yes**
runs the action. The Rofi theme and anything it imports must exist before those
prompts can work. Shutdown/reboot use Hyprland's Lua dispatcher and
`hyprshutdown`; use your own confirmed commands if your Hyprland version differs.
Logout uses `hyprshutdown` when available, otherwise `hyprctl dispatch exit`.

**Lock requires an existing screen locker that handles `loginctl lock-session`.**
That command does not install or launch a locker by itself. Check your lock setup
before relying on this button.

Custom commands run through `/bin/sh` from the `command-center/` folder. Use
trusted commands and preserve confirmations for destructive actions. You can
point to your existing confirmation scripts; they are not removed or replaced.

### Media and brightness

- Swipe between media sources, or use **Ctrl+Left/Right** while media has focus.
  Playback controls depend on what the player supports.
- **To desktop** creates a live, draggable copy of the current media card on the
  focused screen. Removing the copy leaves the original card in the panel.
- `media.cavaEnabled` enables the audio visualizer (default `true`). Missing
  `cava` does not prevent ordinary media controls from working.
- `media.sourceNames` replaces displayed player names using their desktop-entry
  IDs, for example `{ "mpd-mpris": "MPD" }`. Default: `{}`.
- Right-click the brightness slider to choose a controllable display. Keyboard
  users can use the Menu key or **Shift+F10** on that control. Laptop backlights
  use `brightnessctl`; supported external displays use `ddcutil`.

## Controls and notifications

Open or hide the panel from a shortcut or a bar button:

```sh
qs -c command-center ipc call command-center toggle
```

Optional Hyprland binding:

```ini
bind = SUPER, N, exec, qs -c command-center ipc call command-center toggle
```

To hide it without accidentally reopening it:

```sh
qs -c command-center ipc call command-center close
```

The panel opens on the focused monitor and stays there until closed. It takes
keyboard focus when the pointer enters. Clicking elsewhere or leaving the panel
does not automatically hide it; use the toggle or close command. `close` returns
`false` if already hidden, which is not an error.

Notification popups appear at the top-right of the monitor focused when they
arrive. Hovering or focusing a popup pauses its timeout. The panel groups saved
notifications by application; use its clear buttons to remove one, a group,
or all history. Actions and inline replies depend on support from the sending
application and are only available while the notification is still live.

**Do Not Disturb (DND)** hides ordinary popups while still allowing critical
notifications. Ordinary notifications can still enter history; transient ones
are not saved. Turning DND off does not replay suppressed popups. DND survives a
configuration reload, starts off after a process restart, and is not reset by
hiding its tile.

You can also control DND without adding a tile:

```sh
qs -c command-center ipc call notifications toggleDnd
qs -c command-center ipc call notifications setDnd true
qs -c command-center ipc call notifications setDnd false
```

For integrations, the `notifications` target exposes read-only `dnd` and the
`dndStateChanged(bool)` signal. There is no public notification-count/content
interface or SwayNC-compatible command. A bar using `swaync-client` needs its own
integration updated; installing this module does not change the bar.

### Saved data

Notification data stays on each computer:

- History: `~/.local/state/quickshell/notification-history.json`.
- Thumbnail copies: `~/.local/state/quickshell/notification-thumbnails/`.

These paths use `$HOME/.local/state`, even if `XDG_STATE_HOME` points elsewhere.
History can contain private messages. Do not publish it or copy another
computer's history into this installation. Module updates should leave it alone.

## Optional setup

### Stay awake

The tile needs a systemd user unit named `idle-inhibit.service`. If you already
have one, keep your existing setup. Otherwise, create
`~/.config/systemd/user/idle-inhibit.service` with:

```ini
[Unit]
Description=Manual idle inhibitor

[Service]
Type=simple
ExecStart=/usr/bin/systemd-inhibit --what=idle --who=idle-inhibit --why=manual-idle-inhibition --mode=block /usr/bin/sleep infinity
```

Then run:

```sh
systemctl --user daemon-reload
```

Do not enable it at login unless you want inhibition permanently active. The
tile starts and stops it on demand. Your idle manager must respect systemd idle
inhibitors; this does not prevent manual locking or manual suspend.

### LocalSend

Leave LocalSend's tile disabled unless you already have a suitable firewall
helper. It must accept `status`, `on`, and `off`; successful `status` prints
exactly `on` or `off`. The tile calls it through `sudo -n`, which cannot prompt
for a password. Use a root-controlled helper with narrowly scoped sudo
permission, never unrestricted passwordless sudo. Firewall rules and peer
policies remain your own setup.

### Hyprsunset (screen warmth)

**Installing Hyprsunset does not start it.** The tile controls an already-running
Hyprsunset process; it does not launch one. Run the following commands inside
your active Hyprland graphical session, not an unrelated SSH session.

First, check the exact status command used by the tile. It only reads the state:

```sh
hyprctl hyprsunset identity get
```

Expected output is `true` (warming off) or `false` (warming on). Either means the
service is reachable. An error or any other output leaves the tile unavailable.

If the command cannot connect, check whether Hyprsunset is running:

```sh
pgrep -a -x hyprsunset
```

#### Start now and enable automatic startup with systemd

The Arch Linux package includes a **user service** named `hyprsunset.service`.
If you choose this startup method, do not also run Hyprsunset manually or through
a Hyprland startup entry. Stop any manually started copy before switching.

From a terminal inside Hyprland
`systemctl --user edit hyprsunset.service` in order to set a base line:
```sh
[Service]
ExecStart=
ExecStart=/usr/bin/hyprsunset --temperature 4500 --identity
```

Then:
```sh
systemctl --user enable --now hyprsunset.service
systemctl --user status hyprsunset.service --no-pager
hyprctl hyprsunset identity get
```

The bundled unit requires `graphical-session.target` and a `WAYLAND_DISPLAY`
value in the systemd user manager. Hyprsunset's IPC also uses
`HYPRLAND_INSTANCE_SIGNATURE`. If logs indicate missing session environment,
import only those variables from a terminal inside the active Hyprland session,
then restart the service:

```sh
systemctl --user import-environment WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE
systemctl --user restart hyprsunset.service
hyprctl hyprsunset identity get
```

If your Hyprland session does not manage `graphical-session.target`, use the
Hyprland startup method below instead. If the unit is not found, your installed
package may not provide it.

#### Alternative: start directly from Hyprland

Use this instead of the systemd service. If no Hyprsunset process is running,
start it in a terminal and leave that terminal open:

```sh
hyprsunset --identity
```

This starts without applying a warming filter. In another terminal, retry the
status command. If startup fails, read its terminal error; installing the package
alone does not guarantee a compatible Hyprland/Hyprsunset setup.

For this startup method, add the command to your existing Hyprland startup
configuration to run at login. With a Lua configuration, add it to your
`hyprland.start` handler, for example:

```lua
hl.on("hyprland.start", function()
    hl.exec_cmd("hyprsunset --identity")
end)
```

For an older INI-style configuration, use this instead:

```ini
exec-once = hyprsunset --identity
```

Use only one startup method. If a user service or another startup entry already
runs Hyprsunset, keep that setup rather than starting a second copy. Startup
changes apply at the next Hyprland login; the manual command above handles the
current session.

#### Enable the tile with either startup method

In `command-center-local.json`, set your existing `hyprsunset` quick action's
`enabled` to `true`. Its `temperature` is a whole number from 1000 to 20000 K
(default: 4500). Reopen the panel to refresh its status.

If Hyprsunset is already running but `identity get` still fails or is unsupported,
check its logs and use compatible, up-to-date Hyprland and Hyprsunset versions.
Do not start extra copies to work around an IPC failure. Existing schedules in
`~/.config/hypr/hyprsunset.conf` can change the filter later; the tile does not
replace those profiles or other tools controlling the filter.

[Official Hyprsunset configuration and usage](https://wiki.hypr.land/hypr-ecosystem/user/hyprsunset/).

### Compositor effects

Window names for your own Hyprland layer rules:

- Panel: `quickshell-command-center`.
- Notification popups: `quickshell-command-center-toast`.
- Desktop media copy: `quickshell-command-center-media-copy`.

Blur and Hyprglass are optional compositor effects, not requirements.
Background colors and opacity can be configured without them.

## Troubleshooting

| Problem | What to check |
| --- | --- |
| Nothing appears after starting | The panel starts hidden. Run the toggle command. |
| Startup/import error | Run `qs -c command-center` in a terminal and check the required Quickshell/Qt modules. |
| Notifications appear in another application | Stop the other notification service and its automatic startup, then restart command-center. |
| No quick-action tiles | The default list is empty. Add the tiles you want to `quickActions`. |
| Power/network prompt does not open | Check Rofi, XWayland, the confirmation theme, and any files imported by that theme. |
| A device control is unavailable | Check the corresponding tool, service, device permissions, and setup in Optional tools. |
| Screen warmth is unavailable | Run `hyprctl hyprsunset identity get` inside Hyprland; it must return `true` or `false`. See [Hyprsunset setup](#hyprsunset-screen-warmth). |
| VPN will not connect | Use the exact saved profile name in `defaultProfile`; it must identify one profile unambiguously. |
| Colors or settings do not change | Check that the JSON file is beside the module, not inside it, and contains valid JSON. |
| Notification history reports an error | Check the path and permissions. History must be a regular owner-only file (0600), and its thumbnail directory must be private (0700). Invalid data is preserved rather than silently overwritten. |
| Inline reply fails after an application replaces a notification | Some Quickshell builds have an upstream reply-replacement issue. Affected builds may need an upstream update. |
