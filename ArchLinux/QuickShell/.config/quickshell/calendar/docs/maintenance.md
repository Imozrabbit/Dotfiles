# Maintenance and cleanup

## Preserve runtime state

Defaults below respect XDG overrides where shown:

| Path | Purpose |
| --- | --- |
| `$HOME/.config/quickshell/calendar` | Module and native runtime helpers |
| `${XDG_DATA_HOME:-$HOME/.local/share}/calendars/profiles.json` | Profile registry |
| `.../calendars/<id>.json` | Local events or imported cache; distinguish before deleting |
| `.../calendars/<id>/<sha256(uid)>.ics` | Canonical synced resources; directory may be a symlink |
| `.../calendars/<id>.sync.json` | Rebuildable synced cache |
| `${XDG_STATE_HOME:-$HOME/.local/state}/pimsync/status` | Installer's sync status; preserve custom configured locations too |
| `${XDG_CONFIG_HOME:-$HOME/.config}/pimsync` | User configuration and credentials |
| `${XDG_STATE_HOME:-$HOME/.local/state}/quickshell-calendar` | Conflicts, installer receipts and recovery state |

Detaching a profile removes its registry entry, not event files. Malformed stores
are protected, not overwritten. Data directories use 0700; native writes use 0600.

Keep `pimsync.service`, `quickshell-calendar-import.service`,
`quickshell-calendar-import.path` and
`pimsync.service.d/calendar-group-recovery.conf`. They are runtime wiring, not test
artifacts. The import service refreshes caches at startup and on watched changes.
The recovery drop-in supplies exact broker `ExecCondition` and `XDG_STATE_HOME`.

Guard verification loads the unit definition without starting it. It checks
ExecCondition, Environment, EnvironmentFiles and UnsetEnvironment. EnvironmentFile
entries or state-directory unsetting fail closed; inspect custom units rather than
silently rewriting them. The sync callback must remain:

```text
conflict_resolution cmd sh -c 'exec "$HOME/.config/quickshell/calendar/parse/conflict-broker.sh" "$1" "$2"' conflict-broker
```

Preserve `on_empty sync` and `on_delete skip`. Never clear an entire calendar to
remove test events. Delete only deliberately identified disposable events through
the normal whole-series UI.

## Recovery

If `group-recovery`, `group-resolution.json` or a calendar's
`.calendar-series-transaction.json` remains, preserve it and keep sync stopped.
Do not delete guards, bypass ExecCondition or retry an uncertain remote apply.
Resources and pimsync status need review first. Serialized `recover-group` can finish
verified local/cache recovery, not establish remote rollback. A committed resolution
with only cache-refresh failure can recover once its cache target is writable.
Uncertain remote resolution has no automatic recovery override.

Read-only diagnostics after the current version is installed:

```sh
sh "$HOME/.config/quickshell/calendar/parse/conflict-broker.sh" verify-group-guard
sh "$HOME/.config/quickshell/calendar/parse/conflict-broker.sh" check-recovery
systemctl --user status pimsync.service quickshell-calendar-import.path
```

First two commands should exit 0 without output. On failure, inspect the diagnostic;
do not remove state just to obtain a successful result.

## Client update and cleanup

Do not reinstall or reset live data as cleanup. Disposable-file cleanup can happen
before publishing/updating. A later update using [README instructions](../README.md)
requires publishing the reviewed version first: GitHub installer fetches `master`,
not unpublished local changes. Keep one known-good module backup until the updated
version passes desktop/sync checks. Run diagnostics above after installing it.

The updater owns only its temporary `calendar.update-rollback-<timestamp>-<pid>`
directory and `installer/update-previous` receipt. Confirmed cleanup removes that
directory and receipt, including obsolete transfer archives inside the previous
module. Downloads/staging/object files are cleaned separately. Unrelated backups
outside the replaced module are not silently deleted.

An interrupted/unconfirmed update blocks another replacement. Use `update.sh
--confirm` only after successful runtime checks; incomplete runtime recovery has no
ready marker and cannot be purged that way. Preserve its module/unit preimages and
activity records for review. This is code/runtime rollback, not calendar-data or
remote rollback; no power-loss atomicity is claimed.

Stop disposable fixtures before removing their files. Inspect copied transfer/test
files and remove only exact paths you have confirmed are unused. Do not remove
canonical calendar files or apply broad cleanup patterns to data/config directories.

If a test ICS file is still used by an imported profile, detach that test profile
through the UI before confirming its deletion. Do not detach real calendars.

```sh
# Replace this placeholder with an exact, inspected disposable archive path.
rm -i -- /path/to/disposable-calendar-archive.tar.gz
```

Missing-file errors mean there is nothing there to remove. For an older module/
helper backup, inspect its exact path and remove only that recognized backup after
retaining a newer working copy. Do not use broad `rm -rf` or `git reset` commands.
Fixtures under `parse/output/grouped-resolution-*/manual` are disposable only after
their instances stop; never confuse their fake HOME/data with real stores.

Do not remove installer receipts or runtime systemd units/drop-ins. Never remove
the recovery guard or bypass the conflict callback to force synchronization.
Cleanup does not require modifying Hyprland settings, credentials, real calendar
collections, or pimsync status.
