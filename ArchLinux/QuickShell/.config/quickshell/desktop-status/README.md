# Desktop Status

Transparent desktop widgets built with [Quickshell](https://quickshell.org/).
They sit behind application windows and run independently of the bar.

## Features

- **OpenAI/Codex:** remaining weekly and 5-hour quota, with reset countdowns.
- **WLMouse Beast X:** battery percentage and charging status (wired or 1K receiver).
- **DJI Mic Mini:** battery tiers and charging status for each transmitter.

Click a reading to refresh. Batteries refresh every minute; quota every five
minutes and at reset. `+` means charging; `N/A` means no reading is available.
Mic levels run from `FULL` to `L7` (lowest), not exact percentages.

## Requirements

- Linux with a Wayland compositor supporting layer-shell, such as Hyprland.
- Quickshell, Qt 6 Quick and Python 3.
- **BigBlueTermPlus Nerd Font** and **ttyclock** fonts.
- For DJI readings: PyUSB and libusb.
- For quota readings: an existing ChatGPT login through OpenCode.

Quota readings use your existing login without changing credentials. This shows
subscription allowance, not API billing; the unofficial endpoint may change.

## Setup

Place this folder at `~/.config/quickshell/desktop-status`, then run:

```sh
qs -c desktop-status
```

To start with Hyprland, add to your Hyprland config:

```ini
exec-once = qs -c desktop-status -d
```

To stop:

```sh
qs -c desktop-status kill
```

### USB permissions

If battery readings are unavailable, run these from the `desktop-status/` folder:

```sh
sudo install -m 0644 scripts/70-*.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules
```

Reconnect the mouse/receiver afterward. Existing rules installed for the bar also
work; normal readings do not need sudo.

**Disable `mouseBattery` and `djiMicBattery` in the bar if running both configs.**
Do not run competing battery collectors. Stop this config before updating DJI
firmware, using the stop command above rather than force-killing its Python worker.

## Configuration

Edit `Config.qml` to change the monitor, position, size, fonts and colors.
The default monitor is `HDMI-A-1`; change it to your display name.

Set `quotaEnabled`, `mouseBatteryEnabled` or `micBatteryEnabled` to `false` to hide
a module and stop its polling. Changes reload automatically.
