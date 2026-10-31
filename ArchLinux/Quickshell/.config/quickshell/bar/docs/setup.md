# Optional setup and troubleshooting

[Back to README](../README.md)

## WLMouse battery

Supports Beast X wired and 1K receiver devices (`36a7:a884` / `36a7:a882`).
Install the bundled device-specific permission rule:

```sh
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell"
sudo install -m 0644 "$config_dir/bar/scripts/70-wlmouse.rules" /etc/udev/rules.d/70-wlmouse.rules
sudo udevadm control --reload-rules
sudo udevadm trigger --action=add --subsystem-match=hidraw
sudo udevadm settle
python3 "$config_dir/bar/scripts/wlmouse.py"
```

Reconnect the mouse/receiver if needed. The final command should print JSON
without sudo. Then enable `modules.mouseBattery`. Hover refresh has a ten-second
cooldown; left-click refreshes immediately. Failed readings show `N/A`.

## DJI Mic Mini

On the client with the USB receiver (`2ca3:4011`), install dependencies and the rule:

```sh
sudo pacman -S python-pyusb libusb
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell"
sudo install -m 0644 "$config_dir/bar/scripts/70-dji-mic-mini.rules" /etc/udev/rules.d/70-dji-mic-mini.rules
sudo udevadm control --reload-rules
```

Reconnect the receiver from an active local desktop session, then verify without sudo:

```sh
python3 "$config_dir/bar/scripts/dji-mic-battery.py"
```

Enable `"djiMicBattery": true` inside `modules` in `bar-local.json` on that PC.
Global and per-output switches are supported; defaults and this machine's live
override keep it disabled. Disabled outputs create no collector; all enabled
outputs share one service. Reads run every minute, with hover refresh throttled
to once per ten seconds. Left-click refreshes immediately, bypassing that cooldown.
Queries never overlap, including repeated clicks; the 20-second watchdog sends
SIGTERM and waits for process exit/stream completion, allowing USB cleanup.

Only transmitter batteries are shown. Level **1 is full**; **2–7 indicate
descending charge**. These are charge tiers, not exact percentages. Tooltip shows
raw levels; missing devices, permissions, dependencies or readings show `N/A`.

The collector may temporarily detach the receiver's kernel driver. Do not run
parallel copies or use it during firmware updates. Test on the target client
before relying on it while recording.

## Quota

Sign in to ChatGPT through OpenCode, then enable `modules.openAiUsage`.
This shows subscription allowance, **not billed API-key usage**. OpenCode need
not stay running. Click the chip to refresh.

Add `"openAiUsage": { "display": "weekly" }` to your override; change `display`
to `"fiveHour"` or `"both"` as needed. Chips show **percentage remaining**, not used:
`󰨳 64%`, `󰔛 25%`, or `󰨳 64% · 󰔛 25%`. Tooltip always includes both
periods and reset times. Missing readings show `N/A` for that period.

Five circles summarize banked resets: `● ● ● ● ● +2` means seven. Unknown data
shows `Unavailable`; the bar never redeems resets or fetches individual expirations.

The collector reads existing OpenAI credentials locally, without refreshing or
editing them. It only requests quota data from
`https://chatgpt.com/backend-api/wham/usage`, never inference, and does not print
tokens or account details. Renew expired logins in OpenCode; failures show `N/A`.
This unofficial endpoint may change.
**Do not put tokens or passwords in `bar-local.json` or sync authentication files.**

## Battery charge limits

Charge-limit controls require supported sysfs threshold files and narrowly
scoped permission for the existing `sudo -n` writes. Do not grant unrestricted
sudo access to enable them. Ordinary battery display needs no sudo setup.

## Personal files

These are local data, not files to distribute with `bar/`:

| File | Purpose |
| --- | --- |
| `$XDG_CONFIG_HOME/quickshell/bar-local.json` (default `~/.config/quickshell/bar-local.json`) | Per-machine settings. |
| `~/.local/state/quickshell/weather.json` | Saved weather locations/cache. |
| `~/.cache/quickshell/wifi_status.json` | Wi-Fi status cache. |
| `$XDG_DATA_HOME/opencode/opencode.db` (default `~/.local/share/opencode/opencode.db`) | Existing credentials, opened read-only; legacy `opencode/auth.json` is a fallback. |

Do not copy or commit runtime/authentication data. Ambiguous active credentials
are rejected; an expired selected v2 login does not fall back to an old JSON login.

## Troubleshooting

- **No bar:** check the output name with `hyprctl monitors`, its `mode`, and startup command.
- **Runtime errors:** stop only the existing bar, then run `qs -c bar` in a terminal.
  Do not launch a duplicate or stop a running lockscreen.
- **No network/Wi-Fi:** check module switches, NetworkManager and default route;
  inspect `nmcli` and `resolvectl status`.
- **Missing sensors:** CPU temperature needs `k10temp`/`coretemp`, GPU metrics need
  `amdgpu`, and battery/AC data comes from `/sys/class/power_supply`.
- **Peripheral `N/A`:** check connection, permissions and the setup above. A sleeping
  mouse is not necessarily disconnected.
- **Quota `N/A`:** renew login in OpenCode and check the reported error/last update.
- **Proton blocked:** close gaming processes and read the reason; never bypass safety checks.
- **Narrow-screen overlap:** hide modules or reduce per-output spacing; layout order is fixed.
