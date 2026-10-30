#!/bin/sh
set -u

state_home=${XDG_STATE_HOME:-${HOME}/.local/state}
state_path="$state_home/quickshell-calendar/conflicts.json"
if [ -n "${CALENDAR_ID:-}" ]; then
    case "$CALENDAR_ID" in *[!a-z0-9_-]*|[!a-z0-9]*) printf '%s\n' 'invalid calendar conflict scope' >&2; exit 2 ;; esac
    state_path="$state_home/quickshell-calendar/conflicts-$CALENDAR_ID.json"
fi
helper=${CALENDAR_SYNC_HELPER:-$(dirname "$0")/calendar-sync-helper}

umask 077

# Conversion choices are applied only by the owning final job, never normal UI resolution.
if [ -n "${CALENDAR_CONVERSION_SESSION:-}" ]; then
    test "$#" -eq 2 || exit 2
    exec "$helper" caldav convert-callback "${CALENDAR_ID:-}" "$CALENDAR_CONVERSION_SESSION" "${CALENDAR_CONVERSION_PHASE:-}" "$1" "$2"
fi

verify_group_guard() {
    broker_location=$(realpath -m -s -- "$0") || return 1
    # Load the definition without starting it; fresh units have no D-Bus object yet.
    busctl --user call org.freedesktop.systemd1 /org/freedesktop/systemd1 org.freedesktop.systemd1.Manager LoadUnit s pimsync.service >/dev/null || return 1
    unit_path=/org/freedesktop/systemd1/unit/pimsync_2eservice
    properties='['
    separator=''
    for property in ExecCondition Environment EnvironmentFiles UnsetEnvironment; do
        value=$(busctl --user --json=short get-property org.freedesktop.systemd1 "$unit_path" org.freedesktop.systemd1.Service "$property") || return 1
        properties="$properties$separator$value"
        separator=','
    done
    printf '%s]\n' "$properties" | "$helper" verify-group-guard "$broker_location" "$state_home"
}

if [ "${1:-}" = verify-group-guard ]; then
    test "$#" -eq 1 || exit 2
    verify_group_guard
    exit $?
fi

if [ "${1:-}" = check-recovery ]; then
    test "$#" -eq 1 || exit 2
    pending_guard="$state_home/quickshell-calendar/group-recovery"
    pending_resolution="$state_home/quickshell-calendar/group-resolution.json"
    if [ -e "$pending_guard" ] || [ -L "$pending_guard" ] || [ -e "$pending_resolution" ] || [ -L "$pending_resolution" ]; then
        printf '%s\n' 'group recovery required before starting pimsync' >&2
        exit 4
    fi
    exit 0
fi

# Called only by the locked native sync worker. Callbacks capture, never apply.
if [ "${1:-}" = capture ]; then
    test "$#" -eq 2 || exit 2
    yes y | CALENDAR_CAPTURE_ONLY=1 pimsync resolve-conflicts "$2"
    exit $?
fi

run_serialized() {
    operation=$1
    shift
    case "$operation" in
        resolve) { test "$#" -eq 3 || test "$#" -eq 6; } || return 2 ;;
        mutate) test "$#" -eq 4 || return 2 ;;
        mutate-group) test "$#" -eq 5 || return 2 ;;
        recover-group) { test "$#" -eq 3 || test "$#" -eq 4; } || return 2 ;;
        resolve-group) test "$#" -eq 6 || return 2 ;;
    esac
    lock_directory=${XDG_RUNTIME_DIR:-$state_home/quickshell-calendar}
    mkdir -p "$lock_directory"
    lock=$lock_directory/calendar-pimsync.lock
    if [ -L "$lock" ] || { [ -e "$lock" ] && [ ! -f "$lock" ]; }; then
        printf '%s\n' 'calendar runtime lock is unsafe' >&2
        return 1
    fi
    exec 9>>"$lock"
    if [ -L "$lock" ] || [ ! -f /proc/$$/fd/9 ] || [ ! /proc/$$/fd/9 -ef "$lock" ] ||
       [ "$(stat -Lc '%u:%h' /proc/$$/fd/9)" != "$(id -u):1" ]; then
        printf '%s\n' 'calendar runtime lock must be an owned, unlinked regular file' >&2
        return 1
    fi
    if ! flock -n 9; then
        printf '%s\n' 'another calendar sync operation is running' >&2
        return 1
    fi
    subscription_change="$state_home/quickshell-calendar/subscriptions/change.json"
    if [ -e "$subscription_change" ] || [ -L "$subscription_change" ]; then
        printf '%s\n' 'subscription settings recovery required before changing calendars' >&2
        return 4
    fi
    if [ "$operation" = mutate-group ] || [ "$operation" = resolve-group ]; then
        test -n "$5" || return 2
        verify_group_guard || return 1
        newline='
'
        for argument in "$@"; do
            case "$argument" in *"$newline"*) printf '%s\n' 'group paths must not contain newlines' >&2; return 1 ;; esac
        done
        # Resolve filesystem semantics once, including symlink/.. traversals.
        # Keep final cache component unresolved so native preflight rejects symlinks.
        pending_directory=$(realpath -e -- "$1") || return 1
        pending_cache_parent=$(realpath -e -- "$(dirname -- "$2")") || return 1
        pending_cache="$pending_cache_parent/$(basename -- "$2")"
        if [ "$operation" = resolve-group ]; then
            pending_state=$(realpath -e -- "$4") || return 1
            canonical_state=$(realpath -e -- "$state_path") || return 1
            if [ "$pending_state" != "$canonical_state" ]; then
                printf '%s\n' 'group resolution must use configured conflict-state file' >&2
                return 1
            fi
            state_path=$pending_state
            set -- "$pending_directory" "$pending_cache" "$3" "$pending_state" "$5" "$6"
        else
            set -- "$pending_directory" "$pending_cache" "$3" "$4" "$5"
        fi
        for argument in "$@"; do
            case "$argument" in *"$newline"*) printf '%s\n' 'resolved group paths must not contain newlines' >&2; return 1 ;; esac
        done
        if [ "$operation" = resolve-group ]; then
            "$helper" check-group "$1" "$2" "$3" update < /dev/null || return 1
        else
            "$helper" check-group "$1" "$2" "$3" "$4" < /dev/null || return 1
        fi
    fi
    state=$(systemctl --user is-active pimsync.service 2>/dev/null) || :
    case "$state" in
        active) was_active=1 ;;
        inactive|failed) was_active=0 ;;
        *)
            printf '%s\n' "could not determine pimsync.service state: ${state:-unknown}" >&2
            return 1
            ;;
    esac

    guard_directory="$state_home/quickshell-calendar"
    guard_path="$guard_directory/group-recovery"
    resolution_path="$guard_directory/group-resolution.json"
    resolution_log=""
    sync_paused=0
    cache_recovery_failed=0
    requested_directory=""
    requested_cache=""
    requested_source=""
    requested_uid=""
    if [ "$operation" = recover-group ]; then
        requested_directory=$(realpath -e -- "$1") || return 1
        requested_cache_parent=$(realpath -e -- "$(dirname -- "$2")") || return 1
        requested_cache="$requested_cache_parent/$(basename -- "$2")"
        requested_source=$3
        requested_uid=${4:-}
    fi

    recover_guard() {
        recovery_directory=""
        recovery_cache=""
        recovery_source=""
        recovery_resume=0
        recovery_uid=""
        recovery_state="$state_path"
        has_guard=0
        if [ -e "$guard_path" ] || [ -L "$guard_path" ]; then has_guard=1; fi
        if [ "$has_guard" -eq 0 ] && [ ! -e "$resolution_path" ] && [ ! -L "$resolution_path" ]; then return 0; fi
        if [ "$has_guard" -eq 1 ]; then
        if [ -L "$guard_path" ] || [ ! -f "$guard_path" ] || [ "$(wc -c < "$guard_path")" -gt 16384 ]; then
            printf '%s\n' 'group recovery guard is unsafe' >&2
            return 1
        fi
        if ! {
            IFS= read -r recovery_directory && IFS= read -r recovery_cache &&
            IFS= read -r recovery_source && IFS= read -r recovery_resume &&
            { ! IFS= read -r recovery_uid || { ! IFS= read -r recovery_state_line || { recovery_state=$recovery_state_line; ! IFS= read -r recovery_extra; }; }; }
        } < "$guard_path"; then
            printf '%s\n' 'group recovery guard is malformed' >&2
            return 1
        fi
        case "$recovery_resume" in 0|1) ;; *) return 1 ;; esac
        if [ "$operation" = recover-group ] && {
            [ "$requested_directory" != "$recovery_directory" ] || [ "$requested_cache" != "$recovery_cache" ] ||
            [ "$requested_source" != "$recovery_source" ] ||
            { [ -n "$requested_uid" ] && [ -n "$recovery_uid" ] && [ "$requested_uid" != "$recovery_uid" ]; }
        }; then
            printf '%s\n' 'recovery target does not match pending calendar operation' >&2
            return 1
        fi
        if [ -n "$recovery_uid" ]; then
            "$helper" recover-group "$recovery_directory" "$recovery_cache" "$recovery_source" "$recovery_uid" < /dev/null
        else
            # Existing four-line guards predate entry-scoped recovery.
            "$helper" recover-group "$recovery_directory" "$recovery_cache" "$recovery_source" < /dev/null
        fi
        recovery_status=$?
        case "$recovery_status" in
            0|2)
                if [ "$recovery_resume" -eq 1 ]; then was_active=1; fi
                if [ "$recovery_status" -eq 2 ]; then cache_recovery_failed=1; fi
                ;;
            *) return 1 ;;
        esac
        fi
        if [ -e "$resolution_path" ] || [ -L "$resolution_path" ]; then
            "$helper" group-cancel "$recovery_directory" "$recovery_cache" "$recovery_source" "$recovery_state" < /dev/null
            cancellation_status=$?
            case "$cancellation_status" in
                0) ;;
                2) cache_recovery_failed=1 ;;
                *) return 1 ;;
            esac
            if [ -e "$resolution_path" ] || [ -L "$resolution_path" ]; then return 1; fi
        fi
        if [ "$has_guard" -eq 1 ]; then rm -- "$guard_path" || return 1; fi
    }

    restore_service() {
        original_status=$?
        trap - EXIT HUP INT TERM
        final_status=$original_status
        if [ -n "$resolution_log" ]; then rm -- "$resolution_log" || :; fi
        if [ -e "$guard_path" ] || [ -L "$guard_path" ] || [ -e "$resolution_path" ] || [ -L "$resolution_path" ]; then
            if [ "$sync_paused" -ne 1 ] || ! recover_guard; then
                printf '%s\n' 'group recovery required; pimsync will not be restarted' >&2
                exit 4
            fi
        fi
        if [ "$final_status" -eq 0 ] && [ "$cache_recovery_failed" -eq 1 ]; then final_status=2; fi
        if [ "$was_active" -eq 1 ] && ! systemctl --user start pimsync.service; then
            printf '%s\n' 'could not restore pimsync.service' >&2
            if { { [ "$operation" = mutate ] || [ "$operation" = mutate-group ] || [ "$operation" = recover-group ] || [ "$operation" = resolve-group ]; } && { [ "$original_status" -eq 0 ] || [ "$original_status" -eq 2 ]; } \
                    || [ "$operation" = resolve ] && [ "$original_status" -eq 0 ]; }; then
                final_status=3
            elif [ "$final_status" -eq 0 ]; then
                final_status=1
            fi
        fi
        exit "$final_status"
    }
    trap restore_service EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM

    if [ "$was_active" -eq 1 ] && ! systemctl --user stop pimsync.service; then
        printf '%s\n' 'could not stop pimsync.service' >&2
        exit 1
    fi
    sync_paused=1
    if ! recover_guard; then exit 4; fi
    if [ "$cache_recovery_failed" -eq 1 ]; then exit 1; fi

    case "$operation" in
        resolve)
            if [ "$#" -ne 3 ] && [ "$#" -ne 6 ]; then
                printf '%s\n' 'Usage: conflict-broker.sh resolve calendar-id state-path uid' >&2
                exit 2
            fi
            mkdir -p "$guard_directory" || exit 1
            resolution_log=$(mktemp "$guard_directory/.event-resolution-log.XXXXXXXX") || exit 1
            yes y | pimsync resolve-conflicts "$1" > "$resolution_log" 2>&1
            result=$?
            cat -- "$resolution_log" >&2
            if grep -Eq '412|Error uploading resolved item' "$resolution_log"; then exit 1; fi
            if [ "$result" -ne 0 ]; then
                exit "$result"
            fi
            "$helper" conflict-clear "$2" "$3" || exit 1
            if [ "$#" -eq 6 ]; then
                # 0.5.7 resolution leaves remote versions to settle on normal sync.
                # Keep cache publication scoped even if that pass downloads other items.
                settlement=0
                pimsync sync "$1" >/dev/null 2>&1 || settlement=2
                "$helper" refresh-cache-entry "$4" "$5" "$6" "$3" < /dev/null || exit 2
                exit "$settlement"
            fi
            ;;
        mutate)
            if [ "$#" -ne 4 ]; then
                printf '%s\n' 'Usage: conflict-broker.sh mutate directory cache source-id operation' >&2
                exit 2
            fi
            "$helper" mutate "$@"
            ;;
        mutate-group|resolve-group)
            mkdir -p "$guard_directory" || exit 1
            guard_temporary="$guard_path.$$"
            printf '%s\n' "$pending_directory" "$pending_cache" "$3" "$was_active" "$5" "$state_path" > "$guard_temporary" || exit 1
            mv -- "$guard_temporary" "$guard_path" || exit 1
            /usr/bin/sync -f "$guard_path" || exit 1
            if [ "$operation" = mutate-group ]; then
                "$helper" mutate-group "$@"
            else
                "$helper" group-review-begin "$4" "$5" "$6" < /dev/null || exit 1
                # Review callbacks intentionally return unresolved. Native preparation
                # requires every member's unchanged pair, regardless of pimsync status.
                yes y | CALENDAR_GROUP_PHASE=review CALENDAR_GROUP_UID="$5" CALENDAR_GROUP_REVISION="$6" pimsync resolve-conflicts "${CALENDAR_PAIR:-$3}"
                "$helper" group-prepare "$@" < /dev/null || exit 1
                resolution_log=$(mktemp "$guard_directory/.group-resolution-log.XXXXXXXX") || exit 1
                yes y | CALENDAR_GROUP_PHASE=apply CALENDAR_GROUP_UID="$5" CALENDAR_GROUP_REVISION="$6" pimsync resolve-conflicts "${CALENDAR_PAIR:-$3}" > "$resolution_log" 2>&1
                result=$?
                cat -- "$resolution_log" >&2
                if [ "$result" -ne 0 ] || grep -Eq '412|Error uploading resolved item' "$resolution_log"; then
                    printf '%s\n' 'group resolution incomplete; sync remains paused for resource review' >&2
                    exit 4
                fi
                "$helper" group-finish "$@" < /dev/null
            fi
            ;;
        recover-group)
            if [ "$#" -eq 4 ] || [ -z "$recovery_uid" ]; then
                "$helper" recover-group "$@" < /dev/null
            else
                "$helper" recover-group "$@" "$recovery_uid" < /dev/null
            fi
            ;;
    esac
}

case "${1:-}" in
    resolve|mutate|mutate-group|recover-group|resolve-group)
        operation=$1
        shift
        # Explicit online resolution must honor the same managed-collection preflight
        # as a timer sync, before acquiring the broker's shared lifecycle lock.
        case "$operation" in
            resolve) pair=${1:-} ;;
            resolve-group) pair=${CALENDAR_PAIR:-${3:-}} ;;
            *) pair= ;;
        esac
        case "$pair" in
            qs_caldav_*) "$helper" caldav preflight "${pair#qs_caldav_}" >/dev/null || exit 1 ;;
        esac
        run_serialized "$operation" "$@"
        exit $?
        ;;
esac

if [ "$#" -ne 2 ]; then
    printf '%s\n' 'Usage: conflict-broker.sh resolve calendar-id | mutate directory cache source-id operation | local-ics remote-ics' >&2
    exit 2
fi

mkdir -p "$(dirname "$state_path")"
if [ "${CALENDAR_CAPTURE_ONLY:-0}" = 1 ]; then
    "$helper" conflict-capture "$state_path" "$1" "$2"
    exit 1
fi
if [ -n "${CALENDAR_GROUP_PHASE:-}" ]; then
    case "$CALENDAR_GROUP_PHASE" in review|apply) ;; *) exit 1 ;; esac
    if "$helper" group-callback "$state_path" "${CALENDAR_GROUP_UID:-}" "${CALENDAR_GROUP_REVISION:-}" "$CALENDAR_GROUP_PHASE" "$1" "$2"; then
        if [ "$CALENDAR_GROUP_PHASE" = apply ]; then exit 0; fi
        exit 1
    fi
    "$helper" conflict-capture "$state_path" "$1" "$2"
    exit 1
fi
if "$helper" conflict-apply "$state_path" "$1" "$2"; then
    exit 0
fi

"$helper" conflict-capture "$state_path" "$1" "$2"
exit 1
