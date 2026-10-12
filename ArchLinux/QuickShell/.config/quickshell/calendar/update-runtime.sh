#!/bin/sh
# Update-mode runtime coordination. Sourced by install.sh after the staged build.

update_units='pimsync.service.d/calendar-group-recovery.conf quickshell-calendar-import.service quickshell-calendar-import.path'
update_active=''
update_loaded=''
update_pid=''
update_paused=0
update_rollback=''
update_complete=0
update_unit_dir=${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user
update_data_home=${XDG_DATA_HOME:-$HOME/.local/share}
update_state_home=${XDG_STATE_HOME:-$HOME/.local/state}
update_pending=$installer_state/update-previous

update_recovery_check() {
    sh "$target/parse/conflict-broker.sh" check-recovery || return 1
    for directory in "$update_data_home/calendars/"*; do
        if [ -e "$directory/.calendar-series-transaction.json" ] || [ -L "$directory/.calendar-series-transaction.json" ]; then
            printf '%s\n' "Calendar transaction needs recovery: $directory" >&2
            return 1
        fi
    done
}

update_guard_check() {
    # Validate the effective unit with the new helper, against the permanent path.
    busctl --user call org.freedesktop.systemd1 /org/freedesktop/systemd1 org.freedesktop.systemd1.Manager LoadUnit s pimsync.service >/dev/null || return 1
    properties='['
    separator=''
    for property in ExecCondition Environment EnvironmentFiles UnsetEnvironment; do
        value=$(busctl --user --json=short get-property org.freedesktop.systemd1 /org/freedesktop/systemd1/unit/pimsync_2eservice org.freedesktop.systemd1.Service "$property") || return 1
        properties="$properties$separator$value"
        separator=','
    done
    printf '%s]\n' "$properties" | "$update_helper" verify-group-guard "$target/parse/conflict-broker.sh" "$update_state_home"
}

update_instance_json() {
    instance_file=$1
    shift
    NO_COLOR=1 quickshell list --path "$target" --json "$@" > "$instance_file" || return 1
    # Quickshell prints text instead of [] for a selected config with no instances.
    printf 'No running instances for "%s"\nUse --all to list all instances.\n' "$update_shell" > "$staging/empty-instances.txt"
    if cmp -s "$instance_file" "$staging/empty-instances.txt"; then printf '[]\n' > "$instance_file"; fi
}

update_instances() {
    update_shell=$(realpath -e -- "$target/shell.qml") || return 1
    update_instance_json "$staging/instances.json" || return 1
    jq -e --arg path "$update_shell" '
        type == "array" and length <= 1 and all(.[];
            .config_path == $path and (.pid | type == "number" and . > 0 and floor == .))
    ' "$staging/instances.json" >/dev/null || return 1
    update_instance_json "$staging/all-instances.json" --any-display || return 1
    jq -e --slurpfile current "$staging/instances.json" '. == $current[0]' "$staging/all-instances.json" >/dev/null || return 1
}

update_stop_instance() {
    quickshell kill --pid "$1" || return 1
    attempts=0
    while :; do
        update_instances || return 1
        if [ "$(jq 'length' "$staging/instances.json")" -eq 0 ]; then return 0; fi
        attempts=$((attempts + 1))
        if [ "$attempts" -ge 20 ]; then printf '%s\n' 'Calendar did not stop.' >&2; return 1; fi
        sleep 0.1
    done
}

update_prepare() {
    update_helper=$source_dir/parse/calendar-sync-helper
    lock_directory=${XDG_RUNTIME_DIR:-$update_state_home/quickshell-calendar}
    if [ ! -d "$lock_directory" ] || [ -L "$lock_directory/calendar-pimsync.lock" ]; then
        printf '%s\n' 'Calendar runtime lock directory is unavailable or unsafe.' >&2
        return 1
    fi
    exec 9>"$lock_directory/calendar-pimsync.lock"
    flock -n 9 || { printf '%s\n' 'Another calendar sync operation is running.' >&2; return 1; }
    update_recovery_check || return 1
    update_instances || { printf '%s\n' 'Could not identify a single calendar instance safely.' >&2; return 1; }
    update_pid=$(jq -r '.[0].pid // empty' "$staging/instances.json")
    for unit in quickshell-calendar-import.path quickshell-calendar-import.service pimsync.service; do
        load=$(systemctl --user show --property=LoadState --value "$unit") || return 1
        case "$load" in
            not-found) continue ;;
            loaded) ;;
            *) printf '%s\n' "Inspect $unit: load state $load" >&2; return 1 ;;
        esac
        update_loaded="$update_loaded $unit"
        state=$(systemctl --user is-active "$unit" 2>/dev/null) || :
        case "$state" in
            active) update_active="$update_active $unit" ;;
            inactive|failed) ;;
            *) printf '%s\n' "Inspect $unit: activity $state" >&2; return 1 ;;
        esac
    done
    update_sync_load=$(systemctl --user show --property=LoadState --value pimsync.service) || return 1
    for relative in $update_units; do
        file=$update_unit_dir/$relative
        if [ -L "$(dirname "$file")" ] || [ -L "$file" ] || { [ -e "$file" ] && [ ! -f "$file" ]; }; then
            printf '%s\n' "Inspect runtime unit path: $file" >&2
            return 1
        fi
    done
    if [ "$update_sync_load" = loaded ] && [ -f "$update_unit_dir/pimsync.service.d/calendar-group-recovery.conf" ]; then
        update_guard_check || return 1
    fi
}

update_pause() {
    update_rollback=$config_dir/calendar.update-rollback-$(date +%Y%m%d-%H%M%S)-$$
    mkdir -- "$update_rollback"
    printf '%s\n' "$target" > "$update_rollback/target"
    mkdir "$update_rollback/units"
    for relative in $update_units; do
        mkdir -p -- "$update_rollback/units/$(dirname "$relative")"
        if [ -f "$update_unit_dir/$relative" ]; then
            cp -p -- "$update_unit_dir/$relative" "$update_rollback/units/$relative"
        else
            : > "$update_rollback/units/$relative.missing"
        fi
    done
    printf '%s\n' "$update_active" > "$update_rollback/active-units"
    printf '%s\n' "$update_pid" > "$update_rollback/calendar-pid"
    printf '%s\n' "$update_rollback" > "$update_pending"
    previous=$update_rollback/module
    update_paused=1
    # A previously inactive oneshot can be triggered after the snapshot by its watcher.
    for unit in $update_loaded; do systemctl --user stop "$unit" || return 1; done
    if [ -n "$update_pid" ]; then update_stop_instance "$update_pid" || return 1; fi
    update_recovery_check || return 1
}

update_refresh_units() {
    if [ "$update_sync_load" = loaded ]; then
        guard=$update_unit_dir/pimsync.service.d/calendar-group-recovery.conf
        if [ ! -e "$guard" ]; then
            mkdir -p -- "$(dirname "$guard")"
            printf '[Service]\nEnvironment="XDG_STATE_HOME=%s"\nExecCondition=/bin/sh "%s/parse/conflict-broker.sh" check-recovery\n' "$update_state_home" "$target" > "$guard"
            systemctl --user daemon-reload || return 1
        fi
        update_guard_check || return 1
    fi
    # Older manually configured installs may have no installer source receipt.
    if [ -s "$installer_state/sources" ] && [ -s "$installer_state/import-done" ]; then
        sh "$target/setup-import.sh" --update || return 1
    else
        printf '%s\n' 'No complete import setup receipt; existing import definitions preserved.'
    fi
}

update_resume() {
    if [ "$update_sync_load" = loaded ]; then update_guard_check || return 1; fi
    update_recovery_check || return 1
    # Refresh rebuildable caches when their watcher was running; do not enable units.
    case " $update_active " in
        *' quickshell-calendar-import.path '*) systemctl --user start quickshell-calendar-import.service || return 1 ;;
    esac
    for unit in pimsync.service quickshell-calendar-import.service quickshell-calendar-import.path; do
        case " $update_active " in *" $unit "*) systemctl --user start "$unit" || return 1 ;; esac
    done
    if [ -n "$update_pid" ]; then
        quickshell --path "$target" --daemonize --no-duplicate 8<&- 9>&- || return 1
        attempts=0
        while :; do
            if update_instances; then
                pid=$(jq -r '.[0].pid // empty' "$staging/instances.json")
                if [ -n "$pid" ] && quickshell ipc --pid "$pid" show > "$staging/ipc.txt" 2>/dev/null &&
                    grep -Fxq 'target calendar' "$staging/ipc.txt"; then break; fi
            fi
            attempts=$((attempts + 1))
            if [ "$attempts" -ge 20 ]; then printf '%s\n' 'Updated calendar IPC did not become ready.' >&2; return 1; fi
            sleep 0.1
        done
    fi
    update_paused=0
}

update_remove_previous() {
    if [ -L "$update_pending" ] || [ ! -f "$update_pending" ] || [ "$(wc -l < "$update_pending")" -ne 1 ]; then
        printf '%s\n' 'No valid pending update cleanup receipt.' >&2
        return 1
    fi
    IFS= read -r rollback < "$update_pending" || return 1
    case "$rollback" in "$config_dir"/calendar.update-rollback-*) ;; *) return 1 ;; esac
    if [ "$(dirname "$rollback")" != "$config_dir" ] || [ -L "$rollback" ] || [ ! -d "$rollback" ] ||
        [ -L "$rollback/target" ] || [ ! -f "$rollback/target" ] || [ "$(cat "$rollback/target")" != "$target" ]; then
        printf '%s\n' 'Rollback ownership is invalid; nothing removed.' >&2
        return 1
    fi
    if [ -L "$rollback/ready" ] || [ ! -f "$rollback/ready" ] || [ "$(cat "$rollback/ready")" != ready ]; then
        printf '%s\n' 'Update did not finish runtime verification; preserve rollback files for recovery.' >&2
        return 1
    fi
    update_recovery_check || return 1
    rm -rf -- "$rollback" || return 1
    rm -- "$update_pending" || return 1
    printf '%s\n' 'Confirmed update: previous module and rollback files removed.'
}

update_finish() {
    update_helper=$target/parse/calendar-sync-helper
    update_refresh_units || return 1
    update_resume || return 1
    printf '%s\n' "$target" > "$app_receipt"
    printf 'ready\n' > "$update_rollback/ready"
    update_complete=1
    flock -u 9
    exec 9>&-
    printf '%s\n' 'Open calendar and verify it before removing the temporary rollback copy.'
    if confirm 'Calendar works correctly? Permanently remove previous version and rollback files?'; then
        update_remove_previous || return 1
    else
        printf '%s\n' "Rollback retained at $update_rollback. After verification run: sh \"$target/update.sh\" --confirm"
    fi
}

update_cleanup() {
    if [ "$update_complete" -eq 1 ]; then return; fi
    if [ -n "$previous" ] && [ -d "$previous" ]; then
        # Stop replacement processes before restoring code and unit definitions.
        rollback_safe=1
        for unit in $update_loaded; do systemctl --user stop "$unit" || rollback_safe=0; done
        if [ -n "$update_pid" ] && [ -f "$target/shell.qml" ]; then
            if update_instances; then
                pid=$(jq -r '.[0].pid // empty' "$staging/instances.json")
                if [ -n "$pid" ]; then update_stop_instance "$pid" || rollback_safe=0; fi
            else rollback_safe=0; fi
        fi
        if [ "$rollback_safe" -eq 1 ]; then
            if [ -e "$target" ] || [ -L "$target" ]; then mv -- "$target" "$staging/failed-module" || rollback_safe=0; fi
            if [ "$rollback_safe" -eq 1 ] && mv -- "$previous" "$target"; then
                for relative in $update_units; do
                    if [ -f "$update_rollback/units/$relative.missing" ]; then
                        rm -f -- "$update_unit_dir/$relative" || rollback_safe=0
                    else cp -p -- "$update_rollback/units/$relative" "$update_unit_dir/$relative" || rollback_safe=0; fi
                done
                systemctl --user daemon-reload || rollback_safe=0
                update_helper=$target/parse/calendar-sync-helper
                if [ "$rollback_safe" -eq 1 ] && update_resume; then
                    printf '%s\n' 'Update failed; previous module and runtime restored.' >&2
                    rm -f -- "$update_pending"
                    rm -rf -- "$update_rollback"
                    return
                fi
            fi
        fi
        printf '%s\n' "Update recovery needs review. Preserve $update_rollback; do not bypass sync guards." >&2
    elif [ "$update_paused" -eq 1 ]; then
        update_helper=$target/parse/calendar-sync-helper
        if update_resume; then
            rm -f -- "$update_pending"
            if [ -n "$update_rollback" ]; then rm -rf -- "$update_rollback"; fi
        else
            printf '%s\n' "Could not restore prior runtime state; preserve $update_rollback and inspect user services." >&2
        fi
    elif [ -n "$update_rollback" ]; then
        # Snapshot creation failed before runtime/code were changed.
        rm -f -- "$update_pending"
        rm -rf -- "$update_rollback"
    fi
}
