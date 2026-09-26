#!/bin/sh
set -eu
umask 077

# -----------------------------------------------------------------------------------------
# Stage 2: Configure pimsync sources, private storage, and user service
# -----------------------------------------------------------------------------------------
config_home=${XDG_CONFIG_HOME:-$HOME/.config}
data_home=${XDG_DATA_HOME:-$HOME/.local/share}
state_home=${XDG_STATE_HOME:-$HOME/.local/state}
state_dir=$state_home/quickshell-calendar/installer
managed=$state_dir/managed-dirs
selection=$state_dir/sources
config=$config_home/pimsync/pimsync.conf
secret_file=$config_home/pimsync/secrets/radicale3-password
unit=$config_home/systemd/user/pimsync.service
registry=$data_home/calendars/profiles.json

for path in "$HOME" "$config_home" "$data_home" "$state_home"; do
    case "$path" in
        /*) ;;
        *) printf '%s\n' "Use an absolute XDG directory: $path" >&2; exit 1 ;;
    esac
    if printf '%s' "$path" | LC_ALL=C grep -Eq '[[:cntrl:]"\\%]'; then
        printf '%s\n' 'HOME and XDG paths cannot contain control characters, quotes, backslashes, or systemd specifiers.' >&2
        exit 1
    fi
done
choose_source() {
    printf '%s [Y/n] ' "$1"
    IFS= read -r answer || { printf '%s\n' 'Source selection needs input.' >&2; exit 1; }
    case "$answer" in
        ''|y|Y|yes|YES) return 0 ;;
        n|N|no|NO) return 1 ;;
        *) printf '%s\n' 'Answer yes or no.' >&2; exit 1 ;;
    esac
}

if [ -s "$selection" ]; then
    read -r university holidays personal < "$selection"
    for flag in "$university" "$holidays" "$personal"; do
        case "$flag" in 0|1) ;; *) printf '%s\n' 'Installer source selection is invalid.' >&2; exit 1 ;; esac
    done
    printf '%s\n' 'Using previously selected sync sources.'
else
    university=0; holidays=0; personal=0
    if choose_source 'Sync university timetable?'; then university=1; fi
    if choose_source 'Sync French holidays?'; then holidays=1; fi
    if choose_source 'Sync personal Radicale calendar?'; then personal=1; fi
fi
if [ "$university$holidays$personal" = 000 ]; then
    printf '%s\n' 'Select at least one sync source.' >&2
    exit 1
fi
if [ -L "$state_dir" ] || [ -L "$managed" ] || [ -L "$config" ] ||
   { [ "$personal" -eq 1 ] && [ -L "$secret_file" ]; }; then
    printf '%s\n' 'Installer state or pimsync configuration uses a symlink; inspect it before continuing.' >&2
    exit 1
fi

# Check every directory before creating any; do not adopt unknown calendar data.
required_dirs="$state_home/pimsync/status
$data_home/calendars"
if [ "$university" -eq 1 ]; then required_dirs="$required_dirs
$data_home/calendars/edt_unistra"; fi
if [ "$holidays" -eq 1 ]; then required_dirs="$required_dirs
$data_home/calendars/holidays_fr"; fi
if [ "$personal" -eq 1 ]; then required_dirs="$required_dirs
$data_home/calendars/personal
$config_home/pimsync/secrets"; fi
printf '%s\n' 'Checking pimsync directories for existing data...'
old_ifs=$IFS
IFS='
'
for directory in $required_dirs; do
    if [ -L "$directory" ] || { [ -e "$directory" ] && [ ! -d "$directory" ]; }; then
        printf '%s\n' "Inspect $directory: expected a real directory." >&2
        exit 1
    fi
    if [ -d "$directory" ] && [ -n "$(ls -A -- "$directory")" ] &&
       { [ ! -f "$managed" ] || ! grep -Fxq -- "$directory" "$managed"; }; then
        printf '%s\n' "Inspect $directory: contains data not recorded by this installer. Installation stopped." >&2
        exit 1
    fi
done
mkdir -p -- "$state_dir"
printf '%s\n' 'Preparing private pimsync directories...'
for directory in $required_dirs; do
    if [ ! -d "$directory" ]; then
        if ! install -d -m 700 -- "$directory"; then
            printf '%s\n' "Could not create $directory." >&2
            exit 1
        fi
    fi
    if [ ! -f "$managed" ] || ! grep -Fxq -- "$directory" "$managed"; then
        printf '%s\n' "$directory" >> "$managed"
    fi
done
IFS=$old_ifs
if [ ! -s "$selection" ]; then printf '%s %s %s\n' "$university" "$holidays" "$personal" > "$selection"; fi

if ! pimsync_binary=$(command -v pimsync); then
    printf '%s ' 'pimsync is missing. Install it with sudo pacman -S pimsync? [y/N]'
    IFS= read -r answer || answer=''
    case "$answer" in
        y|Y|yes|YES)
            printf '%s\n' 'Installing pimsync...'
            sudo pacman -S pimsync
            pimsync_binary=$(command -v pimsync) || {
                printf '%s\n' 'pimsync is still unavailable after installation.' >&2
                exit 1
            }
            ;;
        *)
            printf '%s\n' 'Install pimsync manually with: sudo pacman -S pimsync' >&2
            exit 1
            ;;
    esac
fi

if [ -s "$state_dir/config-done" ] && [ -s "$config" ] &&
   { [ "$personal" -eq 0 ] || [ -s "$secret_file" ]; }; then
    printf '%s\n' 'pimsync configuration already present; keeping it.'
else
    if [ -e "$config" ] || [ -L "$config" ]; then
        printf '%s\n' "Inspect existing $config before continuing; installer will not replace it." >&2
        exit 1
    fi
    if [ "$university" -eq 1 ]; then
        printf '%s ' 'University ICS URL:'
        IFS= read -r university_url || exit 1
    fi
    if [ "$personal" -eq 1 ]; then
        printf '%s ' 'Radicale HTTPS URL:'
        IFS= read -r radicale_url || exit 1
        printf '%s ' 'Radicale username:'
        IFS= read -r radicale_user || exit 1
    fi
    for value in ${university_url:+"$university_url"} ${radicale_url:+"$radicale_url"} ${radicale_user:+"$radicale_user"}; do
        if printf '%s' "$value" | LC_ALL=C grep -Eq '[[:space:]{}"\\]'; then
            printf '%s\n' 'URLs and usernames must not contain whitespace or configuration syntax.' >&2
            exit 1
        fi
    done
    if [ "$university" -eq 1 ]; then
        case "$university_url" in https://?*) ;; *) printf '%s\n' 'University ICS URL must use HTTPS.' >&2; exit 1 ;; esac
    fi
    if [ "$personal" -eq 1 ]; then
        case "$radicale_url" in https://?*) ;; *) printf '%s\n' 'Radicale URL must use HTTPS.' >&2; exit 1 ;; esac
        if [ -z "$radicale_user" ]; then printf '%s\n' 'Radicale username is required.' >&2; exit 1; fi
        if [ ! -s "$secret_file" ]; then
            printf '%s ' 'Radicale password (not displayed):'
            tty_mode=''
            if [ -t 0 ]; then
                tty_mode=$(stty -g)
                trap 'stty "$tty_mode"; exit 130' INT TERM HUP
                stty -echo
            fi
            if ! IFS= read -r password; then
                if [ -n "$tty_mode" ]; then stty "$tty_mode"; fi
                printf '%s\n' 'Radicale password is required.' >&2
                exit 1
            fi
            if [ -n "$tty_mode" ]; then stty "$tty_mode"; printf '\n'; trap - INT TERM HUP; fi
            if [ -z "$password" ]; then printf '%s\n' 'Radicale password is required.' >&2; exit 1; fi
            printf '%s\n' "$password" > "$secret_file"
            unset password
        fi
    fi
    mkdir -p -- "$(dirname "$config")"
    printf '%s\n' "Writing $config..."
    config_tmp=$(mktemp "$(dirname "$config")/.pimsync.conf.pending.XXXXXXXX")
    {
        printf 'status_path "%s/pimsync/status/"\n\n' "$state_home"
        if [ "$university" -eq 1 ]; then
            printf 'storage unistra {\n    type webcal\n    url %s\n    collection_id edt_unistra\n    interval 900\n}\n\n' "$university_url"
        fi
        if [ "$holidays" -eq 1 ]; then
            printf 'storage holidays_fr {\n    type webcal\n    url https://etalab.github.io/jours-feries-france-data/ics/jours_feries_alsace-moselle.ics\n    collection_id holidays_fr\n    interval 86400\n}\n\n'
        fi
        if [ "$personal" -eq 1 ]; then
            printf 'storage radicale {\n    type caldav\n    url %s\n    discovery principal\n    username %s\n    password {\n        shell cat "${XDG_CONFIG_HOME:-$HOME/.config}/pimsync/secrets/radicale3-password"\n    }\n    auth_method basic\n    interval 900\n}\n\n' "$radicale_url" "$radicale_user"
        fi
        printf 'storage local {\n    type vdir/icalendar\n    path "%s/calendars"\n}\n\n' "$data_home"
        if [ "$university" -eq 1 ]; then
            printf 'pair unistra {\n    storage_a unistra\n    storage_b local\n    collection edt_unistra\n    one_way\n}\n\n'
        fi
        if [ "$holidays" -eq 1 ]; then
            printf 'pair holidays_fr {\n    storage_a holidays_fr\n    storage_b local\n    collection holidays_fr\n    one_way\n}\n\n'
        fi
        if [ "$personal" -eq 1 ]; then
            printf 'pair personal {\n    storage_a local\n    storage_b radicale\n    collection personal\n    on_empty skip\n    on_delete skip\n    conflict_resolution cmd sh -c '\''exec "$HOME/.config/quickshell/calendar/parse/conflict-broker.sh" "$1" "$2"'\'' conflict-broker\n}\n'
        fi
    } > "$config_tmp"
    mv -- "$config_tmp" "$config"
    printf '%s\n' "$config" > "$state_dir/config-done"
fi

# Check generated configuration without contacting remote calendars.
if ! "$pimsync_binary" -c "$config" list pairs > "$state_dir/config-check.log" 2>&1; then
    printf '%s\n' "pimsync rejected $config; inspect its configuration before continuing." >&2
    tail -n 8 "$state_dir/config-check.log" >&2
    exit 1
fi

# Create a registry only on fresh storage; keep existing event and profile data.
if [ -L "$registry" ]; then
    printf '%s\n' "Inspect symlink $registry before continuing." >&2
    exit 1
fi
if [ ! -e "$registry" ]; then
    printf '%s\n' 'Creating initial calendar profiles...'
    registry_tmp=$(mktemp "$data_home/calendars/.profiles.json.pending.XXXXXXXX")
    {
        printf '{"version":1,"profiles":['
        if [ "$university" -eq 1 ]; then
            printf '{"id":"edt_unistra","name":"University","color":"#7b9acc","type":"imported","visible":true},'
        fi
        if [ "$personal" -eq 1 ]; then profile_type=synced; else profile_type=local; fi
        printf '{"id":"personal","name":"Personal","color":"#b58bc8","type":"%s","visible":true}]}\n' "$profile_type"
    } > "$registry_tmp"
    mv -- "$registry_tmp" "$registry"
fi

if [ -L "$unit" ]; then
    printf '%s\n' "Inspect symlink $unit before continuing." >&2
    exit 1
fi
if [ -e "$unit" ]; then
    if ! grep -Fxq -- "ExecStart=$pimsync_binary daemon" "$unit"; then
        printf '%s\n' "Inspect existing $unit; installer will not replace it." >&2
        exit 1
    fi
    if [ "$config_home" != "$HOME/.config" ] &&
       ! grep -Fxq -- "Environment=\"XDG_CONFIG_HOME=$config_home\"" "$unit"; then
        printf '%s\n' "Existing $unit does not set XDG_CONFIG_HOME; inspect it before continuing." >&2
        exit 1
    fi
else
    mkdir -p -- "$(dirname "$unit")"
    printf '%s\n' "Creating $unit..."
    unit_tmp=$(mktemp "$(dirname "$unit")/.pimsync.service.pending.XXXXXXXX")
    {
        printf '[Unit]\nDescription=Synchronise calendars\n\n[Service]\nEnvironment="XDG_CONFIG_HOME=%s"\nExecStart=%s daemon\nRestart=on-failure\nRestartSec=30s\n\n[Install]\nWantedBy=default.target\n' "$config_home" "$pimsync_binary"
    } > "$unit_tmp"
    mv -- "$unit_tmp" "$unit"
fi
if [ ! -s "$state_dir/service-done" ] ||
   ! systemctl --user is-enabled --quiet pimsync.service >/dev/null 2>&1 ||
   ! systemctl --user is-active --quiet pimsync.service >/dev/null 2>&1; then
    printf '%s\n' 'Enabling pimsync user service...'
    if ! systemctl --user daemon-reload > "$state_dir/service.log" 2>&1; then
        printf '%s\n' 'Could not reload user services; rerun after fixing systemd.' >&2
        tail -n 8 "$state_dir/service.log" >&2
        exit 1
    fi
    if ! systemctl --user enable --now pimsync.service > "$state_dir/service.log" 2>&1; then
        printf '%s\n' 'Could not enable or start pimsync; rerun after fixing the service.' >&2
        tail -n 8 "$state_dir/service.log" >&2
        exit 1
    fi
    printf '%s\n' "$unit" > "$state_dir/service-done"
else
    printf '%s\n' 'pimsync user service already configured.'
fi
