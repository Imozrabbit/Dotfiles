#!/bin/sh
set -u

state_home=${XDG_STATE_HOME:-${HOME}/.local/state}
state_path="$state_home/quickshell-calendar/conflicts.json"
helper=${CALENDAR_SYNC_HELPER:-$(dirname "$0")/calendar-sync-helper}

umask 077

run_serialized() {
    operation=$1
    shift
    lock_directory=${XDG_RUNTIME_DIR:-$state_home/quickshell-calendar}
    mkdir -p "$lock_directory"
    exec 9>"$lock_directory/calendar-pimsync.lock"
    if ! flock -n 9; then
        printf '%s\n' 'another calendar sync operation is running' >&2
        return 1
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

    restore_service() {
        original_status=$?
        trap - EXIT HUP INT TERM
        final_status=$original_status
        if [ "$was_active" -eq 1 ] && ! systemctl --user start pimsync.service; then
            printf '%s\n' 'could not restore pimsync.service' >&2
            if { [ "$operation" = mutate ] && { [ "$original_status" -eq 0 ] || [ "$original_status" -eq 2 ]; } \
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

    case "$operation" in
        resolve)
            if [ "$#" -ne 3 ]; then
                printf '%s\n' 'Usage: conflict-broker.sh resolve calendar-id state-path uid' >&2
                exit 2
            fi
            yes y | pimsync resolve-conflicts "$1"
            result=$?
            if [ "$result" -ne 0 ]; then
                exit "$result"
            fi
            "$helper" conflict-clear "$2" "$3"
            ;;
        mutate)
            if [ "$#" -ne 4 ]; then
                printf '%s\n' 'Usage: conflict-broker.sh mutate directory cache source-id operation' >&2
                exit 2
            fi
            "$helper" mutate "$@"
            ;;
    esac
}

case "${1:-}" in
    resolve|mutate)
        operation=$1
        shift
        run_serialized "$operation" "$@"
        exit $?
        ;;
esac

if [ "$#" -ne 2 ]; then
    printf '%s\n' 'Usage: conflict-broker.sh resolve calendar-id | mutate directory cache source-id operation | local-ics remote-ics' >&2
    exit 2
fi

mkdir -p "$(dirname "$state_path")"
if "$helper" conflict-apply "$state_path" "$1" "$2"; then
    exit 0
fi

"$helper" conflict-capture "$state_path" "$1" "$2"
exit 1
