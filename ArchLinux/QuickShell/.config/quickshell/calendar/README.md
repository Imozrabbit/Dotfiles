# Calendar

Calendar is a desktop timetable built with Quickshell. It shows events in week,
month, and two-week agenda views. You can add events to local calendars, import
read-only ICS feeds, and review sync conflicts by choosing the complete Local or
Remote version. Holiday labels appear alongside events.

## How it works

`shell.qml` connects `CalendarService.qml` to the window and exposes IPC target
`calendar`, function `toggle`. Views render service-owned data; they do not
parse ICS or talk to remote calendars.

Calendar profiles live in `profiles.json`. Local profiles save editable events
as JSON. Imported profiles display JSON generated from an ICS file or folder.
The separate `holidays_fr.json` feed supplies holiday labels. Synced profiles
use one ICS file per event as canonical data; their `.sync.json` file is a
rebuildable cache. `pimsync` performs remote synchronization, while
`parse/conflict-broker.sh` coordinates synced mutations and conflict resolution.

Storage paths:

- `${XDG_DATA_HOME:-$HOME/.local/share}/calendars/profiles.json`: profile registry.
- `${XDG_DATA_HOME:-$HOME/.local/share}/calendars/<id>.json`: local/imported data.
- `${XDG_DATA_HOME:-$HOME/.local/share}/calendars/<id>/<sha256(uid)>.ics`: canonical synced events.
- `${XDG_DATA_HOME:-$HOME/.local/share}/calendars/<id>.sync.json`: derived synced cache.
- `${XDG_STATE_HOME:-$HOME/.local/state}/quickshell-calendar/conflicts.json`: conflict choices.

Calendar startup prepares the data directory with mode `0700`. Native helper
writes use mode `0600`. Quickshell `FileView` files inherit process `umask` but
remain inside the private data directory. Detaching a profile removes its
registry entry; event files stay on disk. Replacing an imported profile
requires explicitly editing that same profile.

## Run and verify

Build the native converter and sync helper, then run C++, shell, and Node tests:

```sh
make -C parse test
qmllint shell.qml common/*.js services/*.qml ui/*.qml
quickshell -c /home/Zrabbit/Documents/Dotfiles/ArchLinux/QuickShell/.config/quickshell/calendar
```

Use your calendar toggle shortcut, or call IPC target `calendar.toggle`. Tests
live under `parse/test/` and `dev/tests/`; they do not run with the desktop
shell. `make -C parse clean` removes generated binaries and objects, so rebuild
before launching the calendar afterward.

Build requires a C++17 compiler, Make, `pkg-config`, libical, and Qt6Core.
Tests additionally use Node.js, `jq`, and common shell utilities. Runtime
synced calendars require configured `pimsync.service`, Hyprland, and Quickshell.
`install.sh` remains a placeholder for separate installation work.

## Limits and audit

Recurring ICS events are omitted from the synced cache with a warning.
Conflict review chooses a complete event version, not a per-field merge.
Synced mutations rebuild their entire JSON cache; explicit ICS imports wait
2 seconds for source stability. These costs were retained for data safety and
simplicity. A crash between the separate registry and imported-cache commits
can require manual recovery; real CalDAV interaction was not covered by the
isolated smoke test.

The [full audit](dev/AUDIT.md) records correctness/data-integrity fixes,
security and plain-text checks, runtime-overhead decisions, redundancy cuts,
and regression results. Its deferred test-harness cleanup has not been applied.
