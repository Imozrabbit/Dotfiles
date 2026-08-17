# SwayNC Configuration

## Scope

- Applies only to this directory.
- `config.json` defines SwayNC behavior and widgets; `style.css` is GTK CSS; `restart.sh` restarts live daemon.

## Constraints

- Check installed schema at `/etc/xdg/swaync/configSchema.json` before adding config keys.
- Treat `style.css` as GTK CSS, not browser CSS; preserve `-gtk-*` properties.
- Preserve Nerd Font glyphs and intentional label spacing.
- Button actions depend on Hyprland, `nmcli`, `idle-inhibit.service`, and absolute `/home/Zrabbit/.config/shell/script/Confirm_rofi/` paths.
- Toggle commands receive `SWAYNC_TOGGLE_STATE`; each `update-command` must output exactly `true` or `false`.

## Verification

- JSON: `jq empty config.json`
- Shell syntax: `bash -n restart.sh`
- Config reload: `swaync-client -R`
- CSS reload: `swaync-client -rs`
- Full restart: `./restart.sh`; this kills and relaunches live SwayNC session.
- No local automated test, lint, or build suite exists.
