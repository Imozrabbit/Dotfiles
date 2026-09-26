#!/bin/sh
set -eu
umask 077

# -----------------------------------------------------------------------------------------
# Stage 3: Refresh imported calendars when pimsync changes their ICS files
# -----------------------------------------------------------------------------------------
data_home=${XDG_DATA_HOME:-$HOME/.local/share}
config_home=${XDG_CONFIG_HOME:-$HOME/.config}
state_home=${XDG_STATE_HOME:-$HOME/.local/state}
state_dir=$state_home/quickshell-calendar/installer
unit_dir=$config_home/systemd/user
service=$unit_dir/quickshell-calendar-import.service
watcher=$unit_dir/quickshell-calendar-import.path
installed=$HOME/.config/quickshell/calendar/parse

for path in "$HOME" "$data_home" "$config_home" "$state_home"; do
    case "$path" in /*) ;; *) printf '%s\n' "Expected absolute path: $path" >&2; exit 1 ;; esac
    if printf '%s' "$path" | LC_ALL=C grep -Eq '[[:cntrl:]"\\%]'; then
        printf '%s\n' 'Calendar paths cannot contain control characters, quotes, backslashes, or systemd specifiers.' >&2
        exit 1
    fi
done
if [ ! -s "$state_dir/sources" ] || [ -L "$state_dir/sources" ]; then
    printf '%s\n' 'Complete pimsync setup before installing calendar import units.' >&2
    exit 1
fi
read -r university holidays personal < "$state_dir/sources"
for flag in "$university" "$holidays" "$personal"; do
    case "$flag" in 0|1) ;; *) printf '%s\n' 'Installer source selection is invalid.' >&2; exit 1 ;; esac
done
if [ "$university$holidays$personal" = 000 ]; then
    printf '%s\n' 'No sync sources are selected.' >&2
    exit 1
fi
if [ -L "$service" ] || [ -L "$watcher" ]; then
    printf '%s\n' 'Inspect existing calendar import unit symlink before continuing.' >&2
    exit 1
fi

mkdir -p -- "$unit_dir"
staging=$(mktemp -d "$unit_dir/.calendar-import.XXXXXXXX")
trap 'rm -rf -- "$staging"' EXIT
service_new=$staging/quickshell-calendar-import.service
watcher_new=$staging/quickshell-calendar-import.path

{
    printf '[Unit]\nDescription=Generate Quickshell calendar JSON files\nAfter=pimsync.service\n\n[Service]\nType=oneshot\nUMask=0077\nExecStartPre=/usr/bin/sleep 1\n'
    if [ "$university" -eq 1 ]; then
        printf 'ExecStart="%s/convert" "%s/calendars/edt_unistra" "%s/calendars/edt_unistra.json" edt_unistra\n' "$installed" "$data_home" "$data_home"
    fi
    if [ "$holidays" -eq 1 ]; then
        printf 'ExecStart="%s/convert" "%s/calendars/holidays_fr" "%s/calendars/holidays_fr.json" holidays_fr\n' "$installed" "$data_home" "$data_home"
    fi
    if [ "$personal" -eq 1 ]; then
        printf 'ExecStart="%s/calendar-sync-helper" rebuild "%s/calendars/personal" "%s/calendars/personal.sync.json" personal\n' "$installed" "$data_home" "$data_home"
    fi
    printf '\n[Install]\nWantedBy=default.target\n'
} > "$service_new"
{
    printf '[Unit]\nDescription=Watch synchronized calendar files\n\n[Path]\n'
    for pair in "edt_unistra:$university" "holidays_fr:$holidays" "personal:$personal"; do
        name=${pair%:*}
        enabled=${pair#*:}
        if [ "$enabled" -eq 1 ]; then
            printf 'PathChanged=%s/calendars/%s\nPathModified=%s/calendars/%s\n' "$data_home" "$name" "$data_home" "$name"
        fi
    done
    printf 'Unit=quickshell-calendar-import.service\n\n[Install]\nWantedBy=default.target\n'
} > "$watcher_new"

# Keep existing units unless user explicitly approves replacing different content.
if { [ -e "$service" ] && ! cmp -s "$service_new" "$service"; } ||
   { [ -e "$watcher" ] && ! cmp -s "$watcher_new" "$watcher"; }; then
    printf '%s ' 'Calendar import units already exist with different settings. Replace them? [y/N]'
    IFS= read -r answer || answer=''
    case "$answer" in y|Y|yes|YES) ;; *) printf '%s\n' 'Existing calendar import units unchanged.' >&2; exit 1 ;; esac
    printf '%s ' 'Keep timestamped backups of existing import units? [y/N]'
    IFS= read -r answer || answer=''
    case "$answer" in
        y|Y|yes|YES)
            suffix=$(date +%Y%m%d-%H%M%S)-$$
            for existing in "$service" "$watcher"; do
                if [ -e "$existing" ]; then
                    printf '%s\n' "Saving $existing before replacement..."
                    cp -p -- "$existing" "$existing.backup-$suffix"
                fi
            done
            ;;
    esac
fi

units_changed=0
if [ ! -e "$service" ] || ! cmp -s "$service_new" "$service"; then
    printf '%s\n' 'Installing calendar import service...'
    mv -- "$service_new" "$service"
    units_changed=1
fi
if [ ! -e "$watcher" ] || ! cmp -s "$watcher_new" "$watcher"; then
    printf '%s\n' 'Installing calendar import path watcher...'
    mv -- "$watcher_new" "$watcher"
    units_changed=1
fi

if [ "$units_changed" -eq 1 ] || [ ! -s "$state_dir/import-done" ] ||
   ! systemctl --user is-enabled --quiet quickshell-calendar-import.path >/dev/null 2>&1 ||
   ! systemctl --user is-active --quiet quickshell-calendar-import.path >/dev/null 2>&1 ||
   ! systemctl --user is-enabled --quiet quickshell-calendar-import.service >/dev/null 2>&1; then
    printf '%s\n' 'Enabling calendar import service and watcher...'
    if ! systemctl --user daemon-reload > "$state_dir/import.log" 2>&1 ||
       ! systemctl --user enable --now quickshell-calendar-import.path >> "$state_dir/import.log" 2>&1 ||
       ! systemctl --user enable --now quickshell-calendar-import.service >> "$state_dir/import.log" 2>&1; then
        printf '%s\n' 'Calendar import units could not start; rerun installer after checking user service output.' >&2
        tail -n 8 "$state_dir/import.log" >&2
        exit 1
    fi
    printf '%s\n' "$service" > "$state_dir/import-done"
else
    printf '%s\n' 'Calendar import watcher already configured.'
fi
