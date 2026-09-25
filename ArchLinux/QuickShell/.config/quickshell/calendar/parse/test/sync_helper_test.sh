#!/bin/sh
set -eu

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
mkdir "$workdir/personal"
printf '%s\n' \
    'BEGIN:VCALENDAR' \
    'BEGIN:VEVENT' \
    'UID:sync-test' \
    'DTSTART:20260614T140000Z' \
    'DTEND:20260614T150000Z' \
    'SUMMARY:Sync test' \
    'BEGIN:VALARM' \
    'ACTION:DISPLAY' \
    'TRIGGER:-PT15M' \
    'END:VALARM' \
    'END:VEVENT' \
    'END:VCALENDAR' > "$workdir/personal/event.ics"
printf '%s\n' 'not an iCalendar file' > "$workdir/personal/broken.ics"
printf '%s\n' \
    'BEGIN:VCALENDAR' \
    'BEGIN:VEVENT' \
    'UID:recurring-test' \
    'DTSTART:20260614T140000Z' \
    'DTEND:20260614T150000Z' \
    'RRULE:FREQ=WEEKLY' \
    'SUMMARY:Recurring test' \
    'END:VEVENT' \
    'END:VCALENDAR' > "$workdir/personal/recurring.ics"

./calendar-sync-helper rebuild "$workdir/personal" "$workdir/personal.sync.json" personal
before_mtime=$(stat -c '%Y' "$workdir/personal.sync.json")
sleep 1
./calendar-sync-helper rebuild "$workdir/personal" "$workdir/personal.sync.json" personal
test "$before_mtime" -eq "$(stat -c '%Y' "$workdir/personal.sync.json")"

node - "$workdir/personal.sync.json" <<'NODE'
const fs = require("node:fs")
const document = JSON.parse(fs.readFileSync(process.argv[2], "utf8"))
if (document.version !== 2 || document.events.length !== 1 || document.warnings.length !== 2)
    process.exit(1)
if (document.events[0].uid !== "personal:sync-test")
    process.exit(1)
if (document.events[0].reminders[0].minutesBefore !== 15)
    process.exit(1)
if (!document.events[0].revision)
    process.exit(1)
NODE

cp "$workdir/personal/event.ics" "$workdir/personal/duplicate.ics"
before_duplicate_hash=$(sha256sum "$workdir/personal.sync.json")
if ./calendar-sync-helper rebuild "$workdir/personal" "$workdir/personal.sync.json" personal; then
    exit 1
fi
test "$before_duplicate_hash" = "$(sha256sum "$workdir/personal.sync.json")"
rm "$workdir/personal/duplicate.ics"

printf '%s\n' '{"uid":"created","title":"Created","description":"","location":"","start":"2026-06-14T14:00:00Z","end":"2026-06-14T15:00:00Z","allDay":false,"reminders":[{"minutesBefore":15}]}' \
    | ./calendar-sync-helper mutate "$workdir/personal" "$workdir/personal.sync.json" personal create
created_hash=$(printf '%s' created | sha256sum)
created_hash=${created_hash%% *}
test -f "$workdir/personal/$created_hash.ics"
created_revision=$(jq -r '.events[] | select(.sourceUid == "created") | .revision' "$workdir/personal.sync.json")
printf '%s\n' '{"uid":"created","revision":"'$created_revision'","title":"Updated","description":"","location":"","start":"2026-06-14T14:00:00Z","end":"2026-06-14T16:00:00Z","allDay":false,"reminders":[]}' \
    | ./calendar-sync-helper mutate "$workdir/personal" "$workdir/personal.sync.json" personal update
updated_revision=$(jq -r '.events[] | select(.sourceUid == "created") | .revision' "$workdir/personal.sync.json")
printf '%s\n' '{"uid":"created","revision":"'$updated_revision'"}' \
    | ./calendar-sync-helper mutate "$workdir/personal" "$workdir/personal.sync.json" personal delete

test "$(find "$workdir/personal" -name '*.ics' | wc -l)" -eq 3

mkdir "$workdir/open-stdin"
mkfifo "$workdir/request"
{ printf '%s\n' '{"uid":"open-stdin","title":"Open stdin","description":"","location":"","start":"2026-06-14T14:00:00Z","end":"2026-06-14T15:00:00Z","allDay":false,"reminders":[]}'; sleep 3; } > "$workdir/request" &
producer=$!
timeout 1 ./calendar-sync-helper mutate "$workdir/open-stdin" "$workdir/open-stdin.sync.json" personal create < "$workdir/request"
status=$?
kill "$producer" 2>/dev/null || true
wait "$producer" 2>/dev/null || true
test "$status" -eq 0
test "$(find "$workdir/open-stdin" -name '*.ics' | wc -l)" -eq 1

exec 9>"$workdir/personal/.calendar-sync.lock"
flock -n 9
if ./calendar-sync-helper rebuild "$workdir/personal" "$workdir/locked.json" personal; then
    exit 1
fi
exec 9>&-

mkdir "$workdir/rollback"
printf '%s\n' '{"version":2,"events":[],"warnings":[]}' > "$workdir/rollback.sync.json"
if printf '%s\n' '{"uid":"bad","title":"Bad","description":"","location":"","start":"not-a-time","end":"not-a-time","allDay":false,"reminders":[]}' \
    | ./calendar-sync-helper mutate "$workdir/rollback" "$workdir/rollback.sync.json" personal create; then
    exit 1
fi
test "$(find "$workdir/rollback" -name '*.ics' | wc -l)" -eq 0
test "$(cat "$workdir/rollback.sync.json")" = '{"version":2,"events":[],"warnings":[]}'

if printf '%s\n' '{"uid":"reversed","title":"Reversed","description":"","location":"","start":"2026-06-14T15:00:00Z","end":"2026-06-14T14:00:00Z","allDay":false,"reminders":[]}' \
    | ./calendar-sync-helper mutate "$workdir/rollback" "$workdir/rollback.sync.json" personal create; then
    exit 1
fi
test "$(find "$workdir/rollback" -name '*.ics' | wc -l)" -eq 0
test "$(cat "$workdir/rollback.sync.json")" = '{"version":2,"events":[],"warnings":[]}'

if printf '%s\n' '{"uid":"reversed-day","title":"Reversed day","description":"","location":"","start":"2026-06-15","end":"2026-06-14","allDay":true,"reminders":[]}' \
    | ./calendar-sync-helper mutate "$workdir/rollback" "$workdir/rollback.sync.json" personal create; then
    exit 1
fi
test "$(find "$workdir/rollback" -name '*.ics' | wc -l)" -eq 0
test "$(cat "$workdir/rollback.sync.json")" = '{"version":2,"events":[],"warnings":[]}'

if printf '%s\n' '{"uid":"missing-reminders","title":"Missing","description":"","location":"","start":"2026-06-14T14:00:00Z","end":"2026-06-14T15:00:00Z","allDay":false}' \
    | ./calendar-sync-helper mutate "$workdir/rollback" "$workdir/rollback.sync.json" personal create; then
    exit 1
fi
test "$(find "$workdir/rollback" -name '*.ics' | wc -l)" -eq 0
test "$(cat "$workdir/rollback.sync.json")" = '{"version":2,"events":[],"warnings":[]}'

if printf '%s\n' '{"uid":"wrong-reminders","title":"Wrong","description":"","location":"","start":"2026-06-14T14:00:00Z","end":"2026-06-14T15:00:00Z","allDay":false,"reminders":"15"}' \
    | ./calendar-sync-helper mutate "$workdir/rollback" "$workdir/rollback.sync.json" personal create; then
    exit 1
fi
test "$(find "$workdir/rollback" -name '*.ics' | wc -l)" -eq 0
test "$(cat "$workdir/rollback.sync.json")" = '{"version":2,"events":[],"warnings":[]}'

mkdir "$workdir/cache-failure"
printf '%s\n' blocker > "$workdir/cache-failure/output-blocker"
if output=$(printf '%s\n' '{"uid":"cache-commit","title":"Committed","description":"","location":"","start":"2026-06-14T14:00:00Z","end":"2026-06-14T15:00:00Z","allDay":false,"reminders":[]}' \
    | ./calendar-sync-helper mutate "$workdir/cache-failure" "$workdir/cache-failure/output-blocker/cache.json" personal create 2>&1); then
    status=0
else
    status=$?
fi
test "$status" -eq 2
case "$output" in
    *"event committed but cache rebuild failed"*) : ;;
    *) exit 1 ;;
esac
test "$(find "$workdir/cache-failure" -name '*.ics' | wc -l)" -eq 1

mkdir "$workdir/preserve"
preserve_hash=$(printf '%s' preserve | sha256sum)
preserve_hash=${preserve_hash%% *}
cat > "$workdir/preserve/$preserve_hash.ics" <<'ICS'
BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:preserve
DTSTART:20260614T140000Z
DTEND:20260614T150000Z
SUMMARY:Before
CLASS:PRIVATE
X-CUSTOM:keep-me
BEGIN:VALARM
ACTION:EMAIL
TRIGGER:-PT5M
DESCRIPTION:Unsupported reminder
END:VALARM
END:VEVENT
END:VCALENDAR
ICS
./calendar-sync-helper rebuild "$workdir/preserve" "$workdir/preserve.sync.json" personal
preserve_revision=$(jq -r '.events[0].revision' "$workdir/preserve.sync.json")
printf '%s\n' '{"uid":"preserve","revision":"'$preserve_revision'","title":"After","description":"","location":"","start":"2026-06-14T14:00:00Z","end":"2026-06-14T15:00:00Z","allDay":false,"reminders":[]}' \
    | ./calendar-sync-helper mutate "$workdir/preserve" "$workdir/preserve.sync.json" personal update
preserve_ics=$(cat "$workdir/preserve/$preserve_hash.ics")
case "$preserve_ics" in
    *"CLASS:PRIVATE"*"X-CUSTOM:keep-me"*"ACTION:EMAIL"*) : ;;
    *) exit 1 ;;
esac

mkdir "$workdir/conflict"
cat > "$workdir/conflict/local.ics" <<'ICS'
BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:conflict-event
DTSTART:20260614T140000Z
DTEND:20260614T150000Z
SUMMARY:Local version
X-LOCAL:preserve
END:VEVENT
END:VCALENDAR
ICS
cat > "$workdir/conflict/remote.ics" <<'ICS'
BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:conflict-event
DTSTART:20260614T140000Z
DTEND:20260614T150000Z
SUMMARY:Remote version
X-REMOTE:preserve
END:VEVENT
END:VCALENDAR
ICS
cp "$workdir/conflict/local.ics" "$workdir/conflict-original-local.ics"
cp "$workdir/conflict/remote.ics" "$workdir/conflict-original-remote.ics"
./calendar-sync-helper conflict-capture "$workdir/conflict.state.json" "$workdir/conflict/local.ics" "$workdir/conflict/remote.ics"
test "$(stat -c '%a' "$workdir/conflict.state.json")" = 600
test "$(jq -r '.conflicts | length' "$workdir/conflict.state.json")" -eq 1
test "$(jq -r '.conflicts[0].local.title' "$workdir/conflict.state.json")" = "Local version"
test "$(jq -r '.conflicts[0].remote.title' "$workdir/conflict.state.json")" = "Remote version"
cp "$workdir/conflict.state.json" "$workdir/protected.state.json"
protected_before=$(sha256sum "$workdir/protected.state.json")
chmod 000 "$workdir/protected.state.json"
if ./calendar-sync-helper conflict-capture "$workdir/protected.state.json" "$workdir/conflict/local.ics" "$workdir/conflict/remote.ics"; then
    exit 1
fi
chmod 600 "$workdir/protected.state.json"
test "$protected_before" = "$(sha256sum "$workdir/protected.state.json")"
./calendar-sync-helper conflict-select "$workdir/conflict.state.json" conflict-event remote
remote_before=$(sha256sum "$workdir/conflict/remote.ics")
chmod 400 "$workdir/conflict/remote.ics"
./calendar-sync-helper conflict-apply "$workdir/conflict.state.json" "$workdir/conflict/local.ics" "$workdir/conflict/remote.ics"
chmod 600 "$workdir/conflict/remote.ics"
test "$remote_before" = "$(sha256sum "$workdir/conflict/remote.ics")"
cmp "$workdir/conflict/local.ics" "$workdir/conflict/remote.ics"
case "$(cat "$workdir/conflict/local.ics")" in
    *"SUMMARY:Remote version"*"X-REMOTE:preserve"*) : ;;
    *) exit 1 ;;
esac
./calendar-sync-helper conflict-clear "$workdir/conflict.state.json" conflict-event
test "$(jq -r '.conflicts | length' "$workdir/conflict.state.json")" -eq 0

cp "$workdir/conflict-original-local.ics" "$workdir/conflict/local.ics"
./calendar-sync-helper conflict-capture "$workdir/conflict.state.json" "$workdir/conflict/local.ics" "$workdir/conflict/remote.ics"
./calendar-sync-helper conflict-select "$workdir/conflict.state.json" conflict-event local
cp "$workdir/conflict/remote.ics" "$workdir/conflict/local.ics"
if ./calendar-sync-helper conflict-apply "$workdir/conflict.state.json" "$workdir/conflict/local.ics" "$workdir/conflict/remote.ics"; then
    exit 1
fi
cmp "$workdir/conflict/local.ics" "$workdir/conflict/remote.ics"
cp "$workdir/conflict-original-local.ics" "$workdir/conflict/local.ics"
local_before=$(sha256sum "$workdir/conflict/local.ics")
chmod 400 "$workdir/conflict/local.ics"
./calendar-sync-helper conflict-apply "$workdir/conflict.state.json" "$workdir/conflict/local.ics" "$workdir/conflict/remote.ics"
chmod 600 "$workdir/conflict/local.ics"
test "$local_before" = "$(sha256sum "$workdir/conflict/local.ics")"
cmp "$workdir/conflict/local.ics" "$workdir/conflict/remote.ics"
./calendar-sync-helper conflict-clear "$workdir/conflict.state.json" conflict-event

cp "$workdir/conflict-original-local.ics" "$workdir/conflict/local.ics"
cp "$workdir/conflict-original-remote.ics" "$workdir/conflict/remote.ics"
./calendar-sync-helper conflict-capture "$workdir/conflict.state.json" "$workdir/conflict/local.ics" "$workdir/conflict/remote.ics"
./calendar-sync-helper conflict-select "$workdir/conflict.state.json" conflict-event remote
./calendar-sync-helper conflict-capture "$workdir/conflict.state.json" "$workdir/conflict/local.ics" "$workdir/conflict/remote.ics"
test "$(jq -r '.conflicts[0].choice' "$workdir/conflict.state.json")" = remote
cat > "$workdir/conflict/remote.ics" <<'ICS'
BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:conflict-event
DTSTART:20260614T140000Z
DTEND:20260614T150000Z
SUMMARY:Updated remote version
END:VEVENT
END:VCALENDAR
ICS
./calendar-sync-helper conflict-capture "$workdir/conflict.state.json" "$workdir/conflict/local.ics" "$workdir/conflict/remote.ics"
test "$(jq -r '.conflicts[0].choice' "$workdir/conflict.state.json")" = ""
if ./calendar-sync-helper conflict-apply "$workdir/conflict.state.json" "$workdir/conflict/local.ics" "$workdir/conflict/remote.ics"; then
    exit 1
fi

printf '%s\n' '{"uid":"stale","title":"Current","description":"","location":"","start":"2026-06-14T14:00:00Z","end":"2026-06-14T15:00:00Z","allDay":false,"reminders":[]}' \
    | ./calendar-sync-helper mutate "$workdir/personal" "$workdir/personal.sync.json" personal create
stale_hash=$(printf '%s' stale | sha256sum)
stale_hash=${stale_hash%% *}
stale_file="$workdir/personal/$stale_hash.ics"
cp "$stale_file" "$workdir/stale-before.ics"
if printf '%s\n' '{"uid":"stale","revision":"old-revision","title":"Overwrite","description":"","location":"","start":"2026-06-14T14:00:00Z","end":"2026-06-14T16:00:00Z","allDay":false,"reminders":[]}' \
    | ./calendar-sync-helper mutate "$workdir/personal" "$workdir/personal.sync.json" personal update; then
    exit 1
fi
cmp "$stale_file" "$workdir/stale-before.ics"

stale_revision=$(jq -r '.events[] | select(.sourceUid == "stale") | .revision' "$workdir/personal.sync.json")
cache_before_missing=$(sha256sum "$workdir/personal.sync.json")
rm "$stale_file"
if printf '%s\n' "{\"uid\":\"stale\",\"revision\":\"$stale_revision\"}" \
    | ./calendar-sync-helper mutate "$workdir/personal" "$workdir/personal.sync.json" personal delete; then
    exit 1
fi
test "$cache_before_missing" = "$(sha256sum "$workdir/personal.sync.json")"

cat > "$workdir/personal.json" <<'JSON'
{"version":1,"events":[{"uid":"migrate-event","calendarId":"personal","title":"Migrate me","description":"notes","location":"Room 1","start":"2026-06-15T10:00:00Z","end":"2026-06-15T11:00:00Z","allDay":false,"reminders":[{"minutesBefore":30}]}]}
JSON
./calendar-sync-helper verify-migration "$workdir/personal.json" "$workdir/migrated" "$workdir/migrated.sync.json" personal
./calendar-sync-helper migrate "$workdir/personal.json" "$workdir/migrated" "$workdir/migrated.sync.json" personal
test -f "$workdir/personal.json"
test "$(find "$workdir/migrated" -name '*.ics' | wc -l)" -eq 1
node - "$workdir/migrated.sync.json" <<'NODE'
const fs = require("node:fs")
const document = JSON.parse(fs.readFileSync(process.argv[2], "utf8"))
if (document.version !== 2 || document.events.length !== 1)
    process.exit(1)
if (document.events[0].uid !== "personal:migrate-event"
        || document.events[0].reminders[0].minutesBefore !== 30)
    process.exit(1)
NODE
