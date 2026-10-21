# Level OSD

A lightweight [Quickshell](https://quickshell.org/) on-screen display for speaker
volume, screen brightness and microphone mute status.

## Features

- Speaker volume and mute feedback through PipeWire.
- Backlight brightness indicator.
- Microphone status with distinct icons: **Muted**, **Unmuted**, or **Mic unavailable**.
- Matching pill-style indicators that stack and dismiss independently after one second.
- Event-driven audio updates; no microphone polling or additional daemon.
- No OSD window while idle.

## Requirements

- Quickshell with PipeWire and Wayland support.
- A Wayland compositor supporting layer-shell, such as Hyprland.
- A backlight device for brightness feedback.
- Optional: `inotifywait` from `inotify-tools` for immediate brightness updates.
  A two-second polling fallback remains available.

## Setup

Place this directory at `~/.config/quickshell/level-osd/`, then run:

```sh
quickshell -c level-osd
```

Start it through your compositor's autostart configuration to keep feedback available.
The OSD observes state; existing volume, brightness and mute keybindings remain
responsible for changing it.

### Host-specific settings

Update these values in [`shell.qml`](shell.qml) for your machine:

| Setting | Purpose |
| --- | --- |
| `microphoneName` | Physical PipeWire source controlled by your microphone mute key. |
| `backlightPath` | Backlight device directory under `/sys/class/backlight/`. |
| `hideDelayMs` | Indicator duration; defaults to `1000` ms. |

Speaker feedback follows the default output. Microphone feedback deliberately
tracks the named physical input, not a virtual echo-cancellation default. Keep
`microphoneName` and your mute keybinding's target in sync.

### Microphone keybinding

Normal microphone feedback follows PipeWire mute changes. To also show
**Mic unavailable** when the target is missing or not ready, run this after the
existing mute command, even if that command fails:

```sh
quickshell -c level-osd ipc call levelOsd microphone
```

The included Hyprland integration appends this call to `XF86AudioMicMute`.
Reload Hyprland configuration after changing the binding. The IPC call only
requests feedback; it does not toggle or change audio settings.

Microphone status reports the tracked source's software mute setting, not every
microphone, hardware mute switch or application's chosen input.

## Checks

```sh
node tests/microphone-checks.mjs
qmllint shell.qml OsdItem.qml
```

The automated check requires Node.js and `qml6`. It uses synthetic microphone
state and an isolated offscreen layout test; it does not change microphone settings.
Quickshell type metadata may produce `qmllint` warnings.

For a runtime check, press the mic key twice to verify both states, matching
appearance and dismissal. Also check speaker volume and brightness feedback.
