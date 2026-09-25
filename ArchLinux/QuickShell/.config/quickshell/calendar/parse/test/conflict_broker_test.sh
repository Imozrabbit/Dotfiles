#!/bin/sh
set -eu

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
mkdir "$workdir/bin"
cat > "$workdir/bin/systemctl" <<'SYSTEMCTL'
#!/bin/sh
printf 'systemctl %s\n' "$*" >> "$LOG"
case "$2" in
    is-active)
        state=$(cat "$STATE")
        printf '%s\n' "$state"
        test "$state" = active
        ;;
    stop)
        test "${STOP_FAIL:-0}" != 1 || exit 9
        printf '%s\n' inactive > "$STATE"
        ;;
    start)
        test "${START_FAIL:-0}" != 1 || exit 8
        printf '%s\n' active > "$STATE"
        ;;
    *) exit 2 ;;
esac
SYSTEMCTL
cat > "$workdir/bin/pimsync" <<'PIMSYNC'
#!/bin/sh
printf 'pimsync %s\n' "$*" >> "$LOG"
if [ "${PIMSYNC_WAIT:-0}" = 1 ]; then sleep 1; fi
read -r answer || true
exit "${PIMSYNC_EXIT:-0}"
PIMSYNC
cat > "$workdir/fake-helper" <<'HELPER'
#!/bin/sh
printf 'helper %s\n' "$*" >> "$LOG"
cat >/dev/null
exit "${HELPER_EXIT:-0}"
HELPER
chmod +x "$workdir/bin/systemctl" "$workdir/bin/pimsync" "$workdir/fake-helper"
mkdir "$workdir/runtime"
export PATH="$workdir/bin:$PATH" STATE="$workdir/state" LOG="$workdir/log" XDG_RUNTIME_DIR="$workdir/runtime"
export CALENDAR_SYNC_HELPER="$workdir/fake-helper"
broker=./conflict-broker.sh

printf '%s\n' inactive > "$STATE"
: > "$LOG"
"$broker" resolve personal "$workdir/conflicts.json" event-1
test "$(cat "$STATE")" = inactive
if grep -q 'systemctl --user stop\|systemctl --user start' "$LOG"; then exit 1; fi
grep -q 'pimsync resolve-conflicts personal' "$LOG"
grep -q 'helper conflict-clear .* event-1' "$LOG"

printf '%s\n' active > "$STATE"
: > "$LOG"
if STOP_FAIL=1 "$broker" resolve personal "$workdir/conflicts.json" event-1; then exit 1; fi
test "$(cat "$STATE")" = active
if grep -q '^pimsync ' "$LOG"; then exit 1; fi
grep -q 'systemctl --user start pimsync.service' "$LOG"

printf '%s\n' active > "$STATE"
: > "$LOG"
if PIMSYNC_EXIT=7 "$broker" resolve personal "$workdir/conflicts.json" event-1; then exit 1; fi
test "$(cat "$STATE")" = active
grep -q 'systemctl --user start pimsync.service' "$LOG"
if grep -q 'helper conflict-clear' "$LOG"; then exit 1; fi

printf '%s\n' active > "$STATE"
: > "$LOG"
if HELPER_EXIT=9 "$broker" resolve personal "$workdir/conflicts.json" event-1; then exit 1; fi
test "$(cat "$STATE")" = active
grep -q 'helper conflict-clear .* event-1' "$LOG"
grep -q 'systemctl --user start pimsync.service' "$LOG"

printf '%s\n' active > "$STATE"
: > "$LOG"
if START_FAIL=1 "$broker" resolve personal "$workdir/conflicts.json" event-1; then
    exit 1
else
    status=$?
fi
test "$status" -eq 3
test "$(cat "$STATE")" = inactive
grep -q 'helper conflict-clear .* event-1' "$LOG"

printf '%s\n' inactive > "$STATE"
: > "$LOG"
if HELPER_EXIT=2 "$broker" mutate one two three create < /dev/null; then exit 1; else status=$?; fi
test "$status" -eq 2
test "$(cat "$STATE")" = inactive
if grep -q 'systemctl --user stop\|systemctl --user start' "$LOG"; then exit 1; fi

printf '%s\n' inactive > "$STATE"
PIMSYNC_WAIT=1 "$broker" resolve personal "$workdir/conflicts.json" event-1 &
first_pid=$!
sleep 0.1
if "$broker" resolve personal "$workdir/conflicts.json" event-1; then exit 1; fi
wait "$first_pid"

printf '%s\n' active > "$STATE"
: > "$LOG"
PIMSYNC_WAIT=1 "$broker" resolve personal "$workdir/conflicts.json" event-1 &
interrupted_pid=$!
sleep 0.1
kill -TERM "$interrupted_pid"
if wait "$interrupted_pid"; then exit 1; fi
test "$(cat "$STATE")" = active
grep -q 'systemctl --user start pimsync.service' "$LOG"

printf '%s\n' 'Conflict broker tests passed'
