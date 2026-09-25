#!/bin/sh
set -eu

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
mkdir "$workdir/input"

printf '%s\n' staged > "$workdir/staged.json"
printf '%s\n' existing > "$workdir/target.json"
if ./convert commit "$workdir/staged.json" "$workdir/target.json" create; then
    exit 1
fi
test "$(cat "$workdir/target.json")" = existing
test -f "$workdir/staged.json"
./convert commit "$workdir/staged.json" "$workdir/target.json" replace
test "$(cat "$workdir/target.json")" = staged
test ! -e "$workdir/staged.json"

printf '%s\n' \
    'BEGIN:VCALENDAR' \
    'BEGIN:VEVENT' \
    'UID:test@example' \
    'DTSTART:20260614T140000Z' \
    'DTEND:20260614T150000Z' \
    'SUMMARY:Test event' \
    'END:VEVENT' \
    'END:VCALENDAR' > "$workdir/input/test.ics"

./convert "$workdir/input" "$workdir/edt_unistra.json"

./convert "$workdir/input" "$workdir/holidays_fr.json" holidays_fr

node - "$workdir/holidays_fr.json" <<'NODE'
const fs = require("node:fs")
const document = JSON.parse(fs.readFileSync(process.argv[2], "utf8"))
if (document.events[0].uid !== "holidays_fr:test@example")
    process.exit(1)
if (document.events[0].calendarId !== "holidays_fr")
    process.exit(1)
NODE

node - "$workdir/edt_unistra.json" <<'NODE'
const fs = require("node:fs")
const document = JSON.parse(fs.readFileSync(process.argv[2], "utf8"))
if (document.version !== 1 || document.events.length !== 1)
    process.exit(1)
if (document.events[0].uid !== "edt_unistra:test@example")
    process.exit(1)
if (document.events[0].title !== "Test event")
    process.exit(1)
NODE

unchanged_inode=$(stat -c '%i' "$workdir/edt_unistra.json")
./convert "$workdir/input" "$workdir/edt_unistra.json"
test "$unchanged_inode" = "$(stat -c '%i' "$workdir/edt_unistra.json")"

printf '%s\n' \
    'BEGIN:VCALENDAR' \
    'BEGIN:VEVENT' \
    'UID:unstable@example' \
    'DTSTART:20260614T140000Z' \
    'DTEND:20260614T150000Z' \
    'SUMMARY:Initial event' \
    'END:VEVENT' \
    'END:VCALENDAR' > "$workdir/input/unstable.ics"
(
    sleep 1
    printf '%s\n' \
        'BEGIN:VCALENDAR' \
        'BEGIN:VEVENT' \
        'UID:unstable@example' \
        'DTSTART:20260614T140000Z' \
        'DTEND:20260614T150000Z' \
        'SUMMARY:Updated event' \
        'END:VEVENT' \
        'END:VCALENDAR' > "$workdir/input/unstable.ics"
    sleep 1
    printf '%s\n' \
        'BEGIN:VCALENDAR' \
        'BEGIN:VEVENT' \
        'UID:unstable@example' \
        'DTSTART:20260614T140000Z' \
        'DTEND:20260614T150000Z' \
        'SUMMARY:Final event' \
        'END:VEVENT' \
        'END:VCALENDAR' > "$workdir/input/unstable.ics"
) &
./convert "$workdir/input" "$workdir/stable.json"
./convert "$workdir/input" "$workdir/edt_unistra.json"
test "$unchanged_inode" != "$(stat -c '%i' "$workdir/edt_unistra.json")"
node - "$workdir/stable.json" <<'NODE'
const fs = require("node:fs")
const document = JSON.parse(fs.readFileSync(process.argv[2], "utf8"))
if (document.events.find(event => event.uid === "edt_unistra:unstable@example").title !== "Final event")
    process.exit(1)
NODE

mkdir -p "$workdir/home/.local/share/calendars/edt_unistra"
cp "$workdir/input/test.ics" "$workdir/home/.local/share/calendars/edt_unistra/"
env -u XDG_DATA_HOME HOME="$workdir/home" ./convert
test -f "$workdir/home/.local/share/calendars/edt_unistra.json"

cp "$workdir/input/test.ics" "$workdir/input/duplicate.ics"
printf '%s\n' sentinel > "$workdir/expected.json"
cp "$workdir/expected.json" "$workdir/edt_unistra.json"
if ./convert "$workdir/input" "$workdir/edt_unistra.json"; then
    exit 1
fi
cmp "$workdir/expected.json" "$workdir/edt_unistra.json"
rm "$workdir/input/duplicate.ics"

printf '%s\n' 'sentinel' > "$workdir/edt_unistra.json"
printf '%s\n' 'not an ics file' > "$workdir/input/broken.ics"
if ./convert "$workdir/input" "$workdir/edt_unistra.json"; then
    exit 1
fi
if [ "$(cat "$workdir/edt_unistra.json")" != "sentinel" ]; then
    exit 1
fi
