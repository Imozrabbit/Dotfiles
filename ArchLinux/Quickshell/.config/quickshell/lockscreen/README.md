# Lockscreen

Quickshell session lock using `WlSessionLock`, separate password and fingerprint PAM contexts, per-output wallpaper state, and IPC target `lock`. `shell.qml` composes service; service owns lock/auth/suspend state; view only renders input. Hyprland starts it once; `hypridle` requests lock lifecycle through IPC.

Requires Quickshell with PAM/session-lock support, Hyprland, `hypridle`, `fprintd`, PAM, `jq`, and `JetBrainsMono Nerd Font Mono`.

## File map

- `shell.qml` — `ShellRoot` entrypoint; instantiates `Service`.
- `Service.qml` — session-lock lifecycle, PAM, fingerprint cycles, suspend handling, IPC, stranded-lock recovery.
- `LockView.qml` — lock/preview UI, password input, blurred wallpaper, fingerprint retry.
- `Theme.qml` — fixed colors, font, dimensions, fallback wallpaper.
- `WallpaperState.qml` — watches wallpaper state; resolves output path and image mode.
- `pam/quickshell-lock-password` — password-only `pam_unix.so` stack.
- `pam/quickshell-lock-fingerprint` — fingerprint-only `pam_fprintd.so max-tries=3 timeout=15` stack.

## Security invariants

- Unlock only on explicit `PamResult.Success`; all other PAM results stay locked.
- Password and fingerprint use separate PAM stacks. Do not add `system-auth` or `pam_faillock`.
- Entered and pending passwords clear after submit, failure, unlock, lock reset, or PAM abort.
- Maximum three real fingerprint cycles per lock. Suspend interruptions and PAM/infrastructure errors roll back or retry; they do not consume cycles.
- `WlSessionLock` client death leaves compositor securely locked. Restart lockscreen immediately; do not kill Quickshell while locked unless restart follows immediately.

## Runtime and Hyprland

- Autostart: `qs -n -p ~/.config/quickshell/lockscreen` in `config/autostart.lua`.
- `hypridle.conf`: 300 s runs `loginctl lock-session`; 360 s calls `prepareSuspend`, then DPMS off; 600 s runs `systemctl suspend` only when IPC status has `.secure == true`.
- Sleep hooks: before sleep calls `prepareSuspend`, waits 0.25 s, then locks session; after sleep enables DPMS and calls `resumeAfterSuspend`.
- `lock_cmd` calls IPC `lock`; fallback starts `QUICKSHELL_LOCK_ON_START=1 qs -n -d -p /home/Zrabbit/.config/quickshell/lockscreen`.
- Keep `cursor.no_hardware_cursors = true` in `config/input.lua`; hardware cursors become invisible after resume.

## Wallpaper state

Path: `~/.local/state/quickshell/wallpapers.json`

```json
{"outputs":{"HDMI-A-1":{"wallpaper":"/path/image.png","mode":"fill"}}}
```

Output key is Wayland screen name. Modes: `stretch` → stretch; `fill`/`crop` → aspect crop; `center` → pad; `tile` → tile; missing/other → aspect fit. Missing, invalid, or pathless output uses `Theme.qml` fallback.

## Setup and operation

```sh
root=/home/Zrabbit/.config/quickshell/lockscreen
sudo install -o root -g root -m 0644 "$root/pam/quickshell-lock-password" /etc/pam.d/quickshell-lock-password
sudo install -o root -g root -m 0644 "$root/pam/quickshell-lock-fingerprint" /etc/pam.d/quickshell-lock-fingerprint
qs -n -d -p "$root"                                   # start service
qs -p "$root" ipc call lock preview                    # preview; click to close
qs -p "$root" ipc call lock lock                        # lock
qs -p "$root" ipc call lock status                      # JSON state
qs -p "$root" log -t 200 --no-color                    # service events
```

Re-run both `install` commands after PAM template changes.

## Verification

```sh
/usr/lib/qt6/bin/qmllint -I /usr/lib/qt6/qml /home/Zrabbit/.config/quickshell/lockscreen/{Theme,WallpaperState,LockView,Service,shell}.qml
luac -p /home/Zrabbit/.config/hypr/config/autostart.lua
luac -p /home/Zrabbit/.config/hypr/config/input.lua
hyprctl configerrors
timeout 1s hypridle -v -c /home/Zrabbit/.config/hypr/hypridle.conf
(sleep 5; systemctl suspend) & loginctl lock-session
```

Running `hypridle -c` while normal `hypridle` runs can report duplicate `ScreenSaver` service; this is second-instance behavior, not necessarily parse failure.

## Troubleshooting

| Symptom | Check / recovery |
|---|---|
| `missing-pam` | Install both PAM files root:root `0644`; check `qs -p ~/.config/quickshell/lockscreen ipc call lock status`. |
| Fingerprint unavailable | `journalctl -b -u fprintd.service`; `fprintd-list "$USER"`; confirm fingerprint PAM file exists. |
| Suspend fingerprint race | Use `qs -p ~/.config/quickshell/lockscreen log -t 200 --no-color`; expect `fingerprint-paused`, `fingerprint-resume-requested`, `fingerprint-resumed`. |
| Cursor invisible after resume | Keep Hyprland `no_hardware_cursors = true`; reload Hyprland. |
| Wrong/blank wallpaper | Inspect state JSON/output name/path; fallback is `Theme.qml` `fallbackWallpaper`. |
| Stranded compositor lock | Protocol may remain locked after Quickshell dies. Start `qs -n -d -p /home/Zrabbit/.config/quickshell/lockscreen` immediately; service detects Hyprland `LOCK` blocker and recovers. Do not leave Quickshell stopped while locked. |
