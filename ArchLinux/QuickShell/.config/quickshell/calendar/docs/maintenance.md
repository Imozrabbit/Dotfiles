# Maintenance and second-machine cleanup

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

## A — current machine

Generated tests/build debris and obsolete rollout notes are cleaned from source
module. Runtime helpers, source/tests, real calendar data and configuration stay.
The approved recovery drop-in remains and passed read-only validation. Known copied
transfer archives/test exports were already absent. No live service restart or
reconfiguration was needed for cleanup.

## B — ThinkPad

Do not reinstall or reset live data as cleanup. Disposable-file cleanup can happen
before publishing/updating. A later update using [README instructions](../README.md)
requires publishing the reviewed version first: GitHub installer fetches `master`,
not unpublished local changes. Keep one known-good module backup until the updated
version passes desktop/sync checks. Run diagnostics above after installing it.

The updater owns only its temporary `calendar.update-rollback-<timestamp>-<pid>`
directory and `installer/update-previous` receipt. Confirmed cleanup removes that
directory and receipt, including the previous module's `before-readonly-fix-*.tar.gz`
archive. Downloads/staging/object files are cleaned separately. Unrelated backups
outside the replaced module are not silently deleted.

An interrupted/unconfirmed update blocks another replacement. Use `update.sh
--confirm` only after successful runtime checks; incomplete runtime recovery has no
ready marker and cannot be purged that way. Preserve its module/unit preimages and
activity records for review. This is code/runtime rollback, not calendar-data or
remote rollback; no power-loss atomicity is claimed.

Stop any disposable manual fixture, then remove only copied transfer/test files you
recognize. Each deletion asks confirmation; these are not live calendar files:

If a test ICS file is still used by an imported profile, detach that test profile
through the UI before confirming its deletion. Do not detach real calendars.

```sh
rm -i -- "$HOME/calendar-update.tar.gz" "$HOME/calendar-readonly-fix.tar.gz"
rm -i -- "$HOME/calendar-readonly-test.ics" "$HOME/Downloads/calendar-readonly-test.ics"
find "$HOME/.config/quickshell/calendar/parse/output" -maxdepth 1 -type f \
    -name 'before-readonly-fix-*.tar.gz' -ok rm -- '{}' \;
```

Missing-file errors mean there is nothing there to remove. For an older module/
helper backup, inspect its exact path and remove only that recognized backup after
retaining a newer working copy. Do not use broad `rm -rf` or `git reset` commands.
Fixtures under `parse/output/grouped-resolution-*/manual` are disposable only after
their instances stop; never confuse their fake HOME/data with real stores.

Do not remove installer receipts or runtime systemd units/drop-ins. Do not restore
the earlier missing recovery guard or bypassed callback: those were defects, not
the clean production state. No cleanup requires modifying Hyprland settings,
credentials, Personal collection, or deleting pimsync status.
