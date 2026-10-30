# Maintenance and cleanup

Use this guide to change a calendar's connection, remove it or understand a recovery
warning. For installation and everyday use, start with the [README](../README.md).

**Local** means this computer. **Remote** or **server** means your online calendar
service; a server **collection** is one calendar there. A **cache** is a saved copy
used to display events, not necessarily the only copy of your data.

| What you want to do | Where to look |
| --- | --- |
| Add/edit an online calendar or fix refresh problems | [Synced calendars](#panel-added-caldav) or [URL subscriptions](subscriptions.md) |
| Import a calendar file once | [ICS import](#one-time-import-workspace) |
| Keep events after an online calendar becomes unavailable | [Remote collection unavailable](#remote-collection-unavailable) |
| Create an online calendar | [Create a remote calendar](#create-a-remote-calendar) |
| Delete an online calendar but keep a copy here | [Delete from server, keep local](#delete-from-server-keep-local) |
| Connect a local calendar to an online one | [Local-to-synced attachment](#local-to-synced-attachment) |
| Delete this computer's synced copy | [Synced removal](#synced-removal) |
| Stop syncing but keep events here | [Synced-to-local conversion](#synced-to-local-conversion) |
| Understand an unfinished operation | [Recovery](#recovery) |
| Update Calendar or remove old test files | [Client update and cleanup](#client-update-and-cleanup) |

## Preserve runtime state

**Use Calendar's controls to remove calendars. Do not delete their folders by hand.**
Some JSON files contain your actual local events; others are display copies. File
extensions alone do not tell you what is safe to delete.

These actions have different consequences:

| Action | On this computer | On the server |
| --- | --- | --- |
| **Delete local** | Permanently deletes the selected calendar and its local data | Leaves server events alone; sends no pending local changes |
| **Convert to local** | Keeps chosen events and disconnects after a final sync | That final sync can change events, including pending additions/edits/deletions |
| **Keep local** for an unavailable calendar | Keeps available events and disconnects without a final sync | Makes no requests or changes |
| **Delete remote** | Keeps the reviewed calendar as local | Deletes the whole server calendar, affecting other syncing devices |

Keep passwords, sync settings, databases and any files named in recovery warnings.
A **recovery guard** is a safety check that keeps work stopped when an earlier operation
has not finished safely. Never remove one merely to make sync or an update run.

Change refresh intervals through **Manage calendars → Edit**: CalDAV defaults to
5 minutes, URL subscriptions to 10 minutes, both with a 5-minute minimum. Updates keep
your settings. You do not need to edit configuration files or reinstall to change them.

<details>
<summary>Technical reference: data paths, file ownership, background services and staging</summary>

Panel-added synced calendars reference credentials without owning or deleting them.
They own only generated CalDAV configuration, collection/cache, pair status/database
and timers; unrelated URL calendars stay untouched. Failed Add must undo attempt-created
resources. Later sync failures retain sources/state and published cache. UI edits update
only affected cache entries, without blanket offline-editing restrictions or full-directory
fallbacks. Development tests perform no live setup/migration; final smoke needs separate
user confirmation.

Defaults below respect XDG overrides where shown:

| Path | Purpose |
| --- | --- |
| `$HOME/.config/quickshell/calendar` | Module and native runtime helpers |
| `${XDG_DATA_HOME:-$HOME/.local/share}/calendars/profiles.json` | Profile registry |
| `.../calendars/<id>.json` | Local events or imported cache; distinguish before deleting |
| `.../calendars/<id>/source.ics` | Authoritative managed source for single-file local ICS imports |
| `.../calendars/<id>/*.ics` | Canonical synced resources; remote names may differ from authored UID hashes |
| `.../calendars/<id>.sync.json` | Rebuildable synced cache |
| `${XDG_STATE_HOME:-$HOME/.local/state}/pimsync/status` | Installer's sync status; preserve custom configured locations too |
| `${XDG_CONFIG_HOME:-$HOME/.config}/pimsync` | User configuration and credentials |
| `${XDG_STATE_HOME:-$HOME/.local/state}/quickshell-calendar` | Conflicts, installer receipts and recovery state |
| `.../quickshell-calendar/conflicts-<id>.json` | Panel-added CalDAV calendar's conflict snapshots |
| `.../quickshell-calendar/caldav/status.json` | Per-calendar sync status; not event data |
| `.../quickshell-calendar/caldav/daemon.conf` | Derived daemon configuration excluding timer-managed pairs |
| `.../calendars/.calendar-convert-<id>-<token>/` | Private original sync copies and prepared final local result during conversion |
| `.../quickshell-calendar/caldav/conversion-<id>.json` | Scoped conversion pause and retained-session descriptor; not disposable status |
| `.../calendars/.calendar-attach-<id>-<token>/` | Private local original, review, read-only remote baseline and activation recovery during attachment |
| `.../quickshell-calendar/caldav/attachment-<id>.json` | Attachment session, phase, choices, ownership digests and writable-sync boundary |
| `.../calendars/.calendar-remote-delete-<id>-<token>.json` | Single preserved review payload, later verified final local JSON, during remote deletion |
| `.../quickshell-calendar/caldav/remote-delete-<id>.json` | Compact remote-deletion session, digests, prior scheduling and finish-forward state |

[URL-subscription Remove](subscriptions.md) permanently deletes local
ICS/JSON/database/configuration and profile/status entries, with ordinary-error rollback before commit.
Standalone local Remove deletes only `<id>.json` and its `profiles.json` entry: stage data
beside its original path, atomically commit the registry, then purge staging. Pre-commit
errors restore data; failed restore retains staging and reports its path. It never changes
pimsync configuration, units or online calendars. Local ICS Remove deletes managed source,
cache and profile, not the original download path; it needs no valid ICS/JSON and never
changes pimsync/services. [Synced Remove](#synced-removal) also permanently deletes local
data, rather than merely detaching.
Malformed stores are protected, not overwritten. Data directories use 0700; native writes
use 0600. `calendar-sync-helper` initializes registries/local event JSON create-only at
0600 even with umask 0022. FileView atomic saves preserve that mode without per-event helper
calls or chmod sweeps. Keep the built helper available for local creation, not only sync.

Keep required `pimsync.service`, `quickshell-calendar-import.service`,
`quickshell-calendar-import.path` and
`pimsync.service.d/calendar-group-recovery.conf`. They are runtime wiring, not test
artifacts. URL Remove adjusts shared wiring and removes only unused owned units/drop-ins
and enablement links; preserve unrelated/custom configuration.
Panel-added CalDAV also needs `quickshell-calendar-caldav@.service`, its individual
`quickshell-calendar-caldav-<id>.timer`, and `pimsync.service.d/calendar-caldav.conf`.
The daemon drop-in runs native pimsync against derived configuration without managed
CalDAV pairs. Never bypass that exclusion or run an unrestricted second daemon.
The import service refreshes caches on watched changes and updater-triggered refresh.
The recovery drop-in supplies exact broker `ExecCondition` and `XDG_STATE_HOME`.

Removal stages data under `.calendar-remove-<id>-<random>` in each affected
data/state/configuration/unit/link parent, keeping moves on their filesystems. Commit or successful
rollback removes staging; rollback/purge failure retains recoverable contents and reports
paths. Do not broadly delete them or mistake them for test artifacts. There is no
automatic crash recovery.

Legacy polling intervals remain in the user's `pimsync.conf`; updates preserve older/custom
settings. Managed intervals use the manager; see [refresh intervals](#preserve-runtime-state).

</details>

### Panel-added CalDAV

These are **synced** calendars added through **Manage calendars**. CalDAV is the
protocol used to exchange events with the online service; pimsync runs the transfers.

To add an existing server calendar:

1. Open **Manage calendars → New calendar** and choose **synced**.
2. Enter the server URL and username, then select an **existing private password file**.
   The form does not accept a typed password; hidden and extensionless files are selectable.
3. Click **Connect** to list server calendars without changing them.
4. Choose a calendar if several appear; a single result is selected automatically.
5. Set name, color, local ID and refresh interval, then **Add**. The default is 5 minutes.

Use HTTPS; HTTP is allowed only for tests against this same computer (loopback).
Cancelling discovery discards its temporary list. Successful Connect clears earlier errors;
Add without a selection shows a warning. Calendar appears only after initial sync and
complete conversion succeed. Settings save the password-file path, never its contents.
To create a new server calendar instead, use [Create a remote calendar](#create-a-remote-calendar).

- Use **Edit** to change name, color or refresh interval. The connected server calendar
  cannot be changed to a different one through settings.
- The password picker references an existing file, including hidden or extensionless
  files. It never copies, consumes or deletes it. Cancel keeps the previous selection;
  changed connection details require **Connect** again.
- Use **Refresh now** to request a sync. Wait for a running job to finish; if ordinary
  event conflicts block Refresh/settings, review those conflicts first. Calendar-scoped
  conflicts remain accessible even when no event is displayed in the main view.
- A failed refresh keeps the last complete displayed events and local sync data. It
  does not mean that every event currently on the server has been downloaded.
- If status looks out of date, reopen the manager. Do not clear status files, stop
  healthy jobs or delete/re-add a real calendar to refresh the UI.

An ordinary failed Add undoes only resources created locally by that attempt. It never
rolls back server data or takes ownership of your password. If Calendar is killed while
adding, leftover files may need separate inspection before retrying; there is no automatic
crash recovery for Add. Review overlapping hand-written settings rather than deleting them.

<details>
<summary>Technical reference: managed configuration, Add checks and complete-cache publication</summary>

Owned configuration lies between `# BEGIN quickshell-calendar caldav v1` / `# END`
markers. Metadata and rendered storage/pair blocks must agree; edit name/color/interval
through the manager, not those blocks. Password paths reference user-owned credentials,
never cleanup targets. The manual-overlap guard also detects
unreferenced storage blocks. Inspect exact routing before proposing cleanup and obtain
separate live-edit approval.

Timers and Refresh now invoke the same locked `calendar-sync-helper caldav sync <id>`
worker. Missing/linked collections, unsafe resources or missing pair state fail before
server access. Failed sync retains local ICS/database state and last published JSON;
editing still works under ordinary stale/conflict checks. Publication requires successful
pimsync and complete staged conversion; edits/resolutions update only affected entries.
Do not manually rebuild after failed sync if unrelated partial downloads must stay hidden.

Ordinary Add failures roll back attempt-created files, pair database/sidecars, units and
profile/config changes—not server data. Add never adopts credentials or writes a crash
journal. A killed Add may leave unregistered resources; inspect exact owned paths/timers
before retrying. Never broadly delete calendar storage. Read-only Qt6Network discovery uses
principal/calendar-home requests without configuration or credential copies. Cancel discards
results while the bounded worker finishes. HTTPS verifies certificates; HTTP is loopback-test-only.

Add exclusively creates its local collection, checks its identity before use/cleanup,
and compares configuration/unit snapshots just before publication. Late user files are
never adopted/overwritten. After reload, effective systemd command/environment checks
preserve and reject custom overrides that restore unrestricted daemon routing. Duplicates
are detected by resolved collection URL/account, not discovery entry path. Opening the
manager reconciles interrupted worker status even when its Loader recreates the panel.
After setup creates missing directories, the shared settings service re-arms config/status
watchers, keeping completion/failure updates live without polling or changing backend busy
state. Never clear live status, stop healthy jobs or re-add calendars to fix stale UI.
Accepted CalDAV refresh clears the banner; rows show sync progress/results. Trigger failures
retain their actual errors.

</details>

### Remote collection unavailable

Before syncing a managed calendar, Calendar checks whether its online calendar is
accessible. If it is missing or hidden by permissions, sync pauses and a warning stays
visible. **Local events are not deleted, and the server calendar is not recreated.**
An **unavailable** message does not prove deletion; login, network and protocol failures
remain ordinary refresh errors.

Closing or reopening Calendar does not clear this pause. Changing name, color or refresh
interval does not clear it either. Other calendars keep working.

<details>
<summary>Technical reference: availability checks, HTTP responses and persistent pause state</summary>

Managed sync, explicit conflict resolution and final online conversion run bounded native
read-only DAV preflight before pimsync. It verifies authenticated account home, same-origin
target and calendar resource type without event downloads or new polling. It cannot prevent
server deletion between preflight and sync. Conversion rejected by this preflight has not
attempted sync, so Cancel stays safe; after a pimsync attempt, no-discard recovery guards remain.

- Complete child `404`: **Remote calendar unavailable**; deletion and permission filtering
  cannot be distinguished. Local collection/cache/database stay unchanged.
- Complete child `410 Gone` and omission from verified accessible home: **Remote calendar
  deleted**. Local data stays unchanged; no automatic removal/conversion.
- Network/TLS/authentication failures, redirects, malformed/incomplete responses or
  inaccessible home: ordinary sync error, not inferred deletion/unavailability.
  Failed preflight never invokes pimsync.

The `caldav/status.json` target record stores `remoteState` (`unavailable` or `deleted`)
and `remoteTarget` (connection/collection identity hash, excluding interval). This record
is the durable pause; no new controller, marker or timer. Paused timer workers return
without credentials/network/pimsync; enablement stays unchanged. Other calendars keep
working. Name/color/interval edits do not clear pauses, and another connection's status
cannot authorize local preservation.

</details>

Row warnings stay visible with actions collapsed. Expand the conversion arrows for
**Conversion options → Keep local**, or trash for **Removal options → Delete local**.
Expansion never checks the server or starts work:

- **Keep local** reviews the events available here, including unsynced additions/edits,
  supported recurrence, timezones and reminders. Details that cannot be edited safely stay
  read-only. Previously saved server conflict versions can be chosen offline, but are
  not presented as current server data. Invalid, outdated, ambiguous or unpreservable
  data blocks the operation rather than being dropped. Final **Keep local** disconnects
  the calendar with no final sync, server discovery, password read, upload or deletion request.
  Events never downloaded to this computer cannot be recovered.
- **Delete local** works offline and asks for confirmation naming the calendar to delete.
  Unsynced changes and stored conflict copies are permanently deleted on this device;
  no server requests or password-file deletion.
- The refresh arrow becomes **Check remote availability**: one explicit read-only recheck,
  even with ordinary conflicts. Verified accessibility clears the pause for later normal
  sync; the check itself never synchronizes events. Missing/failed checks keep the pause, as do
  dismiss/reopen/restart.

Cancel before the local copy becomes active keeps the availability pause. Retry during
review rebuilds it offline; Retry during final cleanup finishes locally while preserving
newer edits. Keep every reported recovery file until the problem is understood.

<details>
<summary>Technical reference and optional disposable-calendar test</summary>

Local preservation reuses the two-file retirement journal/payload with `preserveLocalOnly: true`
and `kind: local-preserve`. No local-only phase enters DELETE/outcome verification. Cancel
before activation restores owned scheduling but keeps the pause. Review Retry rebuilds
local/captured versions offline; activation/cleanup Retry finishes locally, preserving newer
edits. Warnings never claim this client deleted the remote calendar. Never sweep pending
journal/payload files. Remove rollback/crash limits stay unchanged.

This applies to managed CalDAV, not unmanaged/legacy pimsync pairs. For user-manual smoke,
use a fresh disposable collection: sync test events, delete it in Radicale, refresh, verify
warning/preserved events; test Keep/Cancel, Keep/restart, then Delete local/Cancel/Delete
separately. Never use Personal/SEME or provoke live permission/network failures. Automated
tests use isolated loopback fixtures.

</details>

### Create a remote calendar

This creates a new calendar on your existing service, not a new account. You need
permission to create calendars there. Your password remains in its existing private file.

In **New calendar → synced**, select the existing password file and Connect. The picker
offers **Create new remote calendar…**, even for empty accounts. Connect/selection are
read-only. Enter separate **Remote calendar name** and **Collection identifier**, then
submit **Create and add**:

- Remote name: one nonempty line, up to 512 characters, with no control characters such
  as tabs or line breaks.
- Collection ID: a server-side identifier such as `family-calendar`, up to 128 characters.
  Start with a lowercase letter or digit; use only lowercase letters, digits, `_` and `-`.
- Local ID and displayed name are separate from these server names. No new account or
  password store is created.

<details>
<summary>Technical reference: create-only server request and registration</summary>

The exact collection ID rule is `^[a-z0-9][a-z0-9_-]*$`, the same as local IDs. The remote
name limit is 512 Unicode characters. No compensating DELETE is sent after successful
creation; an uncertain result makes no ownership claim and never retries MKCALENDAR.

Authenticated native `MKCALENDAR` uses discovered home, escaped XML and create-only
`If-None-Match: *`. Existing/concurrently created collections are never overwritten/adopted.
The target is verified before Add/initial pimsync registration. Connection changes invalidate
discovery; successful first creation re-arms the same config/status watchers as existing Add.

</details>

**Remote calendar created; adding it locally failed** means the server collection remains.
The form keeps your entries and selects that calendar for **Add**, not another creation.
Calendar does not delete the new server calendar to undo a local failure. If creation's
result is uncertain, **Connect** again and explicitly select an existing calendar instead
of repeating creation. After closing/restarting, Connect/Add can attach the created calendar.

### Delete from server, keep local

**This deletes the entire online calendar, not just this device's connection.** Other
syncing devices lose that server calendar; only this computer keeps the reviewed local copy.
To stop syncing without deleting the server calendar, use
[Convert to local](#synced-to-local-conversion) instead.

1. Expand **Trash → Removal options → Delete remote**. Its accessible name is
   **Delete from server, keep local**. Opening the options does not start deletion.
2. Review the local events and a fresh download of server events. Events found on only
   one side are kept. For different versions of the same event, choose Local or Remote;
   recurring series are chosen as a whole. These choices are made offline.
3. Read the final confirmation naming the calendar, collection ID and server target.
   Avoid edits from another device between the final check and deletion: Calendar cannot
   lock the whole server. If contents changed, review and confirm again, even with no conflicts.
4. Confirm only when you intend to delete that online calendar. No final upload-capable
   sync or conflict resolution runs. The local calendar keeps its ID, name, color and visibility.

The local copy preserves supported event details; anything that cannot be kept safely
blocks deletion. The password file is not deleted. Ordinary conflicts need not be resolved
online before starting this review.

If the server's response is uncertain, Calendar stays paused and keeps recovery files.
Use **Close / Retry**, not a forced Cancel or a repeated deletion. Retry makes one read-only
check, or finishes a known local save/cleanup; it never uploads, repeats deletion, recreates
the server calendar or overwrites a newer local file. Other local calendars remain usable.

After server deletion succeeds, any unfinished local save or cleanup must be completed;
the server deletion is not undone. Keep the named recovery files and use the offered Retry. Guards remain
active until completion, even if the calendar already appears local.

<details>
<summary>Technical reference: preservation rules, reminder handling, deletion outcomes and recovery</summary>

Preparation durably guards the calendar, pauses only its timer/owned enablement, and reads
checked canonical local sources plus a fresh complete remote snapshot. Local-only/remote-only
events survive; identical identities appear once. Different versions use local/remote cards
and offline Confirm, without the third keep-local-only card. Whole groups choose an entire
side, including valid asymmetric membership. Cross-side member UIDs with different logical
identities are refused, never silently assigned grouped/ordinary versions.
Equality compares complete libical-normalized resources, not displayed fields or byte-sensitive
mutation revisions. Folding/property/component order and safely equivalent explicit-UTC
reminder durations need no choices. Only bookkeeping fields (`PRODID`, `DTSTAMP`, `CREATED`,
`LAST-MODIFIED`, `SEQUENCE`) are excluded; hidden properties, alarm details, recurrence
exceptions and complete timezone definitions still distinguish versions. Supported recurrence,
timezones, reminders and foreign/read-only ICS survive as local JSON v3. Malformed, partial
or unpreservable content blocks deletion.
Simple day/week DISPLAY reminders become exact minute offsets only with original explicit-UTC
DTSTART without TZID. One unambiguous simple `-P1D` on a non-recurring all-day event appears
as “1 day before” while keeping its nominal-day alarm across edits. Removing it removes that
alarm; remove it before changing to timed/recurring. Synced-to-local conversion keeps this
event read-only because numeric reminders cannot express the distinction. Named-zone,
floating, recurring, richer and ambiguous nominal alarms stay opaque; never flatten civil
days across DST. Review distinguishes `-P1D` from elapsed `-PT1440M`; editing/removing
recognized UTC reminders uses the same classification to prevent duplicates. Unmodeled event
and recurrence properties, rich alarms and unreferenced timezone definitions survive in read-only
embedded ICS. Groups whose opaque content cannot fit local logical recurrence are refused
before deletion; no lossy group format is added.

Final confirmation rechecks the complete href/ETag/content fingerprint, not only collection
CTag. Changes refresh review and require explicit confirmation even without conflicts.

Pending deletion adds at most two durable files: a 0600 payload beside final local JSON and
a 0600 operation record under CalDAV state, with 0700 parents. No database/collection backup
tree, credential copy, per-step log or retry daemon. Replacement records old/pending payload
digests before publication; interrupted preparing/ready stages never authorize DELETE.
Retry rebuilds review; Cancel restores unchanged owned scheduling, including originally
stopped/runtime timers.

Before DELETE, preflight rechecks local destination absence, including broken symlinks.
Safe read/validation failure, Cancel or definite refusal restores prior setup/scheduling
and cleans operation files when safe. After possibly applied DELETE, one bounded read-only
check classifies the result:

- Confirmed DELETE success, or explicit `410 Gone` with accessible expected home and no
  listed target: finish locally, no second DELETE.
- Child `404` plus home omission does not prove absence; permissions can hide both. After
  a lost reply, 404-only servers leave the operation paused with preservation data for
  manual inspection, not a false success claim.
- Original collection still present with identical contents: restore previous sync when
  the response excludes pending asynchronous/partial acceptance.
- Changed/inaccessible/ambiguous state, including 202/207 acceptance: remain paused,
  retain payload/record and offer **Close / Retry**, not discard-Cancel.

Retry performs one read-only verification or resumes known local completion. Confirmed absence
moves the payload create-only to `<id>.json` and updates profile/current shared configuration
without restoring stale unrelated settings. Cleanup removes only unchanged owned resources;
new sources/custom units and newer local edits are preserved/reported. Incomplete activation
or cleanup stays guarded after restart, even with a local profile. Retry never recreates the
collection, uploads, repeats DELETE or overwrites newer local files. Success/safe rollback
removes operation files; never sweep reported pending copies as caches. Local create/update/delete
and both ends of moves stay guarded until completion; unrelated local calendars stay
writable. Ordinary Remove confirmation replaces the lifecycle footer temporarily and cannot
submit the pending target's DELETE.

Live smoke needs separate permission and a user-chosen disposable calendar, never Personal/SEME:
Create and add; verify names/event sync; try Cancel; Delete remote and review choices/final
confirmation; verify local restart persistence and remote absence from another client;
remove the resulting local test calendar normally. Default smoke is user-manual. Never
provoke uncertain live outcomes. Reminder delivery and updater verification are separate checks.

</details>

### Local-to-synced attachment

Use **Conversion options → Attach to remote** to connect a local calendar to an existing
or new server calendar.
Its ID, name, color and visibility stay unchanged. Events unique to either side are kept;
different versions of the same event need a whole-event or whole-series choice.
Matching internal identifiers (**UIDs**), not similar titles/times, establish event identity.

**With no conflicts, or after the last conflict choice, attachment proceeds automatically
through a final refresh and a sync that can write to the server. There is no second final
confirmation.** If the refresh finds changed versions, review those again; unchanged choices
are kept. Avoid editing from other devices between that refresh and the end of sync.

1. Select **Attach to remote**, enter server URL and username, choose the existing password
   file, then **Connect**. Discovery is read-only.
2. Select an existing empty/populated server calendar, set its interval, then **Attach and sync**.
   Or choose **Create new remote calendar…**, enter a separate remote name and unused collection
   identifier, then **Create and attach**. This also works for an empty account. Selecting the
   option alone creates nothing.
3. Review any Local/Remote choices for complete events or series. Choices are staged without
   event uploads until review is complete. With no conflicts, attachment proceeds automatically.

- Before any sync that can write to the server starts, cancellation or failure restores the local
  calendar and prior scheduling, cleaning only unchanged files created by the attempt.
- A newly created server calendar remains even if attachment fails or is cancelled.
  If creation succeeded but preparation failed, retry **Attach and sync** against that
  existing target. If creation is uncertain, **Connect** and explicitly select the target;
  never repeat creation automatically or delete it to start over.
- Once a sync that can write to the server may have started, never force the calendar
  back to local or assume server changes were undone. Use attachment **Retry** for an
  interrupted step. After its cleanup finishes, use ordinary **Refresh** or conflict review.
- A warning that local data/settings changed means reopen the flow, not bypass the check.
  Keep all reported recovery files. Other local calendars stay usable.

<details>
<summary>Technical reference: identities, timezones, creation, writable-sync boundary and cleanup</summary>

Attachment reuses discovery and credential selection, including creation for empty accounts.
Profile metadata stays; only type changes to `synced`. UIDs, not titles/times, determine
identity. Unique events form a union; different matching events/series require whole
Local/Remote choices. The codec keeps preservable opaque ICS verbatim; unsupported or
ambiguous identity/schema/fidelity blocks attachment rather than losing content.
Editor-created timed one-offs may save a timezone. Attachment keeps it as
`X-QUICKSHELL-TIMEZONE` alongside standard UTC instants so DST ambiguity cannot shift events.
Recurrence keeps existing TZID/rules. Equivalent `.000Z`/`Z` spellings compare by instant;
nonzero fractional seconds, including submilliseconds, fail before writes. External
local-data/profile/configuration changes invalidate staging; reopen instead of activating a different
revision. Newer data/configuration stay intact.

`attach-begin` downloads read-only review. Explicit `createRemote: true` first validates
profile/configuration revisions, source export, interval, credentials and local/managed-target
collisions, then uses authenticated create-only DAV creation at the discovered home.
Existing/concurrently created collections are never overwritten/adopted; creation uploads no events.

The form stays open during creation. Known-created targets preserve inputs and permit only
attachment retry; uncertain results invalidate discovery. Created collections are never
rollback/cleanup DELETE targets. After restart, Connect and select the existing target.

Confirm stages a choice; this direction has no keep-local-without-upload option. Once
all choices exist, the service requests `attach-finish` automatically. Final read-only
pimsync pull stages portable pair history. Changed contents retain only choices with
matching UID/revision; the rest return to review. With no outstanding decisions, activation
and first writable sync need no second confirmation. Normal sync conflict/race handling
remains authoritative. Avoid other-client edits during the final refresh/sync gap; this
is not a server-wide transaction.

Changed/foreign files are preserved/reported, never swept. While the session exists, guards cover direct
local persistence, initialization, event/profile mutations, removal and ordinary sync for
this target; other local calendars stay usable.

Writable attempts retain active canonical resources, cache and pair history, including after
process interruption. Failed Retry never resets that boundary. Cleanup-only Retry never
synchronizes again or overwrites newer edits. First-sync failure is not successful sync
or remote deletion.

Cleanup checks private ownership/known contents before removing unneeded scratch originals,
read-only seed config/data/history, review and activation records, including after safe failures.
Required active data/history, unresolved conflicts and pending recovery stay; errors name
retained paths. Never delete markers/staging to bypass guards; resolve the problem and
Retry/Cancel. In `discarding`, original local state is authoritative and only owned scratch
cleanup remains; Retry never syncs, even without staging. User passwords, unrelated/shared
resources and historical source/recovery backups are excluded. Historical archive purge
needs separate authorization.

User-manual smoke uses disposable local/remote calendars, never Personal/SEME: Cancel populated
review and verify unchanged originals; reattach with unique events and a deliberate matching
UID; confirm each winner choice in separate runs; verify automatic sync, metadata, server
contents and restart. Test empty collections separately. Never provoke failed/uncertain
live writes; private fixtures cover them.

</details>

### Optional files and diagnostics

Some files do not exist until you use their feature. Missing holiday data, pre-setup
configuration or unused status files normally need no action. Do not create empty files
or delete/re-add a real calendar merely to silence logs. If an error names lost conflict
data or unreadable files, investigate it rather than clearing the error state.

<details>
<summary>Technical reference: optional-file watchers and selective diagnostics</summary>

Missing optional `holidays_fr.json`, pre-setup configuration, unused sync-status and conflict
snapshots are normal. Their FileViews suppress automatic missing-file diagnostics, retaining
explicit nonmissing I/O errors and parse protections. Losing a file with known conflicts
invalidates state and reports an error; it must never silently clear conflicts. No placeholders
or global log filter are needed. Watching stays enabled, including imported-file reloads and first-Add
config/status re-arming. To check, restart Calendar in the foreground and open the manager;
never delete/re-add real calendars or change sync state merely to check logs.

</details>

### Synced removal

Use this when you want to **delete this device's copy**, not keep its events as local:

**There is no final sync or password access. Unsynced local additions/edits are lost;
pending local deletions are not sent. The server calendar and password file stay unchanged.**

1. In **Manage calendars**, expand the calendar's trash icon and choose **Delete local**.
2. Read the confirmation naming the calendar. **Cancel** changes nothing.
3. **Delete** permanently removes its local events, settings, sync history and conflict copies.

Removal works offline, including with an unavailable password file. A failed sync or
ordinary unresolved conflict alone does not block it. Active sync or coordinated work,
possibly for another calendar, can block removal temporarily; wait rather than interrupting it.
Shared settings, unsafe links or resources used by another calendar may require review.

Normal errors before the removal is committed restore files and relevant background jobs.
If that restoration fails, keep the reported files and do not start jobs against uncertain
data. **“Calendar removed; temporary cleanup incomplete”** instead means removal succeeded
but temporary copies remain. There is no automatic retry or crash/power-loss recovery.

<details>
<summary>Technical reference: removal checks, exact footprint, shared services and rollback</summary>

The manager captures confirmed profile/configuration revision and uses
`calendar-sync-helper caldav remove`, not the URL-only remover.

The nonblocking shared lease and worker state exclude active sync/coordinated changes,
including another calendar's operation. Never interrupt work or bypass event-write recovery
guards. Failed/completed sync, stale JSON busy flags and ordinary conflicts do not themselves
block removal. Missing targets count as absent; malformed disposable ICS/cache/conflicts need
no parsing. Invalid shared metadata, custom ownership/dependencies or unsafe links stop
removal. This includes another URL/unmanaged pair selecting the collection, or custom
last-CalDAV daemon/retained-guard routing whose prerequisites cannot safely be removed.
Review dependencies; never delete shared collections/derived configuration to force Remove.
Failed conflict-worker launches report errors and release stale busy state; running workers stay protected.

Cleanup covers the ID-derived collection, `<id>.sync.json`, `qs_caldav_<id>.status` with
`-wal`, `-shm`, `-journal`, `conflicts-<id>.json`, selected profile/config/status entries,
timer and exact matching user/runtime enablement links. CalDAV template, daemon drop-in
and derived `daemon.conf` are removed after their last dependency. Generated URL watcher/import
units, daemon and recovery wiring stay while another calendar/application needs them;
unused recognized owned wiring is removed. Custom files/development backups are never swept.
Required registry/configuration/coordination guards stay.

The selected timer stops first; non-last removal leaves unrelated daemon/watchers running.
Last-CalDAV removal may pause/reconfigure the shared daemon, then restore prior activity
for remaining sources. Derived config is retired only after daemon stop. Exact install
links are staged reversibly; systemd reloads only changed definitions. Data stays on its
original filesystems, with small shared-file backups beside staging. Profile updates late;
required runtime settles before commit. QML blocks late writes and retires event/conflict
stores, selection and editor only after committed success.

Ordinary pre-commit errors restore data, shared bytes/modes, links and timer/daemon activity
without overwriting newer replacements. Incomplete rollback retains staging and reports
paths; never start jobs against uncertain state. Post-commit purge failure reports successful
removal with **“Calendar removed; temporary cleanup incomplete”** and retained locations.
No automatic retry, removal journal, recovery wizard or crash/power-loss guarantee.

Synthetic tests do not authorize deleting real calendars. Desktop smoke stays user-manual;
live data/configuration inspection or changes need separate permission.

</details>

### Synced-to-local conversion

**Convert to local** keeps chosen events on this computer and stops future syncing.
It keeps the same ID, name, color and visibility, and leaves the online calendar and
password file in place. Unlike **Delete local**, it does not throw away this device's events.

**The final sync can send other pending additions, edits and deletions too.** Back up
important data and review the warning before confirming. This is not a way to keep the
server completely untouched; use the choices below carefully. The separate **Keep local**
flow for an unavailable server has no final sync.

1. Open the calendar's arrows (**⇄**) → **Conversion options → Convert to local**.
2. If there are conflicts, review each pair of versions, select a card and **Confirm**.
   Confirm only saves a choice for this conversion; it does not contact the server yet.
3. Read the final named confirmation, then **Convert** to run one final calendar-wide
   sync and disconnect. Before final work begins, **Cancel conversion** or **Cancel**
   returns to the synced calendar and restores its previous scheduling.

You can reopen the manager to continue a conversion. Its review is separate from ordinary
conflict resolution. Ordinary conflicts dim Refresh/settings for that calendar, but
visibility, conversion, navigation and confirmed removal stay available. Other calendars
and background schedules are unchanged.

<details>
<summary>Interface reference: conflict controls, locked actions, conversion icon and navigation</summary>

Settings gear always opens Manage calendars and turns muted amber for ordinary conflicts;
there is no separate warning icon/badge. The normal footer adds amber **Resolve conflicts
(count)** (**Conflicts (count)** in compact panels), opening ordinary resolution. Closing
review resolves nothing. The action hides without conflicts or during settings, deletion
confirmation or conversion. Reopen the manager to continue conversion; staged review stays
separate from ordinary resolution.

Confirmed ordinary conflicts add a count to idle synced rows, such as `synced · 3 conflicts`.
Tooltips keep the last refresh error/success time; conflicts can coexist with connection or
authentication failures. Manual Refresh/settings disable and dim for that calendar, including
an open Save if conflicts arrive. Hover locked actions for reasons. Resolving all conflicts
unlocks controls. Visibility, conversion review, navigation and Remove with destructive
confirmation stay available. Other calendars/background timers are unchanged. Tooltips
anchor below the hovered option, flip above if needed and stay within the window horizontally.

The conversion icon matches neighboring controls, supports pointer/keyboard use and exposes
expanded state to accessibility tools. Arrows use a centered fixed box independent of font
bearings. Tooltips remain available when paused conversion disables the icon. The separate
footer **Convert** starts final work. Only reviewed server changes are intended; this action
does not attach local calendars to CalDAV.
See [conversion testing](conversion-testing.md) for a disposable-calendar walkthrough
covering both directions without hand-editing event UIDs.

The manager highlights the conversion target by session ID with blue border/faint fill,
including paused/reopened review and final confirmation. Cancel/completion clears it;
unrelated rows stay unchanged.

</details>

For each differing event, choose one version and Confirm. A repeating event is chosen
as a whole series:

| Choice followed by Confirm | Kept on this computer | Left on the server |
| --- | --- | --- |
| **This device**, without the keep-local top card | Local version | Local version |
| **Other device** | Remote version | Remote version |
| **Keep local, leave server unchanged** top card | Local version | Remote version, unchanged |

**Keep local, leave server unchanged** is a conversion-only top card. It selects both
itself and the local version below; clicking it again does not turn it off. To choose
the normal local version that updates the server, click the local version card alone.
Choosing the remote card also clears the top card. Nothing is saved until **Confirm**.

Choices stay offline until final **Convert**. Previous/Next and Review choices restore
confirmed selections, including both highlights for the keep-local choice. Unsaved selections
are discarded when you navigate away or reopen review. Closing the panel keeps the conversion;
restarting Calendar keeps its pause and recovery copies, but may require choosing again.
Cancel before final work removes only unchanged temporary conversion files; added or changed
recovery contents stay at the reported paths with a warning. Active work or pending event/series
recovery blocks conversion. Never kill jobs or bypass the safety check.

The stored event sources must match the complete displayed copy before conversion starts.
If Calendar reports an outdated or incomplete copy, refresh and review it first. It will
not silently convert partial downloads or discard source events.

<details>
<summary>Technical reference: local event format after conversion</summary>

Local JSON v3 keeps logical UIDs, timezone/recurrence/reminders and embedded read-only ICS.
Local v1/v2 remain compatible. Sync-only source/revision/group bookkeeping is dropped;
later edits persist locally without recreating or refreshing a sync pair.

</details>

Final work rechecks the reviewed versions and refuses writes if their saved versions no
longer match. Another device can still make changes during the operation. Failure or an
uncertain result leaves the calendar synced but paused, with originals and the prepared
local copy at the reported private paths. Never retry automatically, delete recovery records,
run an unrestricted pimsync job or assume server changes were undone. Inspect the retained
data and server result first, with separate permission for live operations. Calendar cannot
make the whole remote operation indivisible or guarantee recovery after a crash or power loss.

After server success, disconnection must finish locally even if saving or registering the
local calendar fails. Warnings name the surviving local result and recovery files. A warning
about temporary cleanup can accompany a successful conversion; it does not mean the conversion
was undone or that every copy was deleted. Never sweep those paths. Unexpected new source files
cause a collection copy to be retained; newer replacement files are preserved, with the intended
result kept at its reported recovery path. Scroll the manager's message to read every path.

<details>
<summary>Technical reference: successful conversion cleanup</summary>

Complete success retires the same owned footprint as Remove except profile and `<id>.json`;
shared dependencies/credentials stay. Purge failure lists every retained location. Unexpected
source files retain a conservative collection copy, and a late destination replacement is
preserved. Bounded manager messages scroll through the final path without card clipping.

</details>

#### Manual smoke (disposable calendar by default)

This is an optional hands-on test, run by the user unless assistant execution is separately
requested. **Use a disposable server calendar and a backup: final confirmation changes
server events.** Do not reset an existing calendar to recreate this test. The steps below
are for new disposable tests.

<details>
<summary>Maintainer note: already-completed Personal test, not a setup instruction</summary>

The user completed Personal's A/B/C review/reopening/Cancel, final conversion with expected
results on both machines, restart persistence and local-only edits. Never reset Personal
or recreate its events.

</details>

1. Add the test server calendar through the manager. Include an ordinary editable event
   and, if available, a read-only event from another app with repetition or zero duration
   and an alarm.
2. Sync three test events, then edit each on both devices. Refresh to capture conflicts
   and record both versions.
3. Choose **Convert to local**. Review local/remote previews; try Previous/Next and
   close/reopen review. Edits/Refresh should be blocked for that calendar. Cancel before
   final confirmation; verify it stays synced with prior scheduling restored. Ordinary
   conflict-related restrictions stay until those conflicts are resolved.
4. Repeat: A local version card only, B remote version card, C keep-local top card
   (top card and local version both selected). Confirm each offline choice. Final
   confirmation must name the calendar and warn about other pending additions/edits/deletions. Convert.
5. Expect local A/local, B/remote, C/local; inspect the other device for server A/local,
   B/remote, C/remote. Local views alone do not prove server preservation.
6. Restart this Calendar configuration, not just its window. Name/color/visibility and recurrence/reminders remain; read-only
   events stay read-only. Edit an ordinary local event; verify it never reaches the server.
   This checks stored reminders; notification delivery has separate regression coverage.
7. On warning, stop and keep every listed file. Ask separately for read-only inspection
   of those specific paths; permission to edit the program does not authorize live-data reads.

### Local-only pimsync configuration

Sync settings and passwords belong in a private local folder, not in publicly shared
dotfiles. The installer/updater does not move linked settings, remove files from Git
tracking or rewrite history for you. If it rejects an unknown or linked layout, review
that separately; never delete settings or recovery files to pass the check.
Use a real directory, not a link into public configuration. Fresh clients start empty
and add sources through Calendar's UI.

### One-time import workspace

Use a one-time import for a **read-only** calendar from one local `.ics` file, not automatic
updates. **Successful import moves the file into Calendar storage and removes the unchanged
original. Keep a separate copy first if you need the download.**

1. Open **Manage calendars → New calendar** and choose **imported**.
2. Enter a name, unique ID and color.
3. Choose **one local `.ics` file**, up to **16 MiB**, then **Import**.

Calendar parses a private copy before saving. Failure preserves the original and undoes
import-owned changes; if only deleting the original fails, the calendar stays usable with
a warning. Existing IDs/files are never overwritten. Name and color remain editable,
but events do not. To use another file, remove the old calendar and import again; folder
import and Replace are unavailable. Valid empty calendars and missing optional titles,
descriptions, locations or reminders are accepted; original ICS contents and alarms are kept.
For online calendar links, use a [URL subscription](subscriptions.md) instead.

Missing/invalid stored ICS hides events but leaves the calendar listed with an error.
**Trash → Delete local → Delete** permanently removes its managed source, display files
and profile, even if the source cannot parse. Cancel changes nothing; other calendars
and the original download location stay untouched.

If an import is interrupted, keep any files named in the error until their contents are
checked. Do not edit files externally or run another Calendar instance during import.
Removing the imported calendar never deletes from the original download location.

<details>
<summary>Technical reference: import staging, source ownership and interruption limits</summary>

Persistent data remains in `${XDG_DATA_HOME:-$HOME/.local/share}/calendars/`:

```text
profiles.json             # Calendar profiles
<calendar-id>/source.ics  # Authoritative managed source
<calendar-id>.json        # Generated display cache
```

Local import publishes managed source/cache/profile. Files use 0600, directories 0700.
Source bytes, including optional data/alarms, stay unchanged. The managed source is authoritative;
missing/invalid ICS hides events with a short status and Remove, including legacy JSON-only
imports. Removal needs no successful parsing and never revisits the old source path.
Imports stage in `.import-local-<id>-<random>`. Source/cache publication and registry commit
hold the native runtime lease; shell profile metadata changes wait until completion.
Ordinary failures clean only unchanged import-owned objects, preserving/reporting changed
ones. Original deletion first claims the file into private same-filesystem staging beside
it, verifies identity/content, then deletes. Changed originals are restored without
overwriting replacements. Inspect reported `.calendar-import-source-*` paths before deletion;
they may hold preserved candidates or incomplete cleanup. Never edit externally or run
concurrent instances during import. There is no cross-file crash transaction or automatic recovery.
Interrupted imports may retain staging/unregistered source/cache; inspect exact ownership and
contents before cleanup. Never broadly delete calendar storage.

</details>

### Retained low-level snapshot CLI

This older command-line interface is for integrations, not the normal file-import form.
Most users do not need it. Its working files are not a reason to clean calendar storage
while an import is running.

<details>
<summary>Technical reference: legacy import sessions, orphan cleanup and sync guards</summary>

Legacy `convert import` file/folder/URL remains for low-level integration, separate from
the panel's local-file flow. Downloads/staged JSON live under
`${XDG_DATA_HOME:-$HOME/.local/share}/calendars/.imports/import-<random>/` with mode
0700; files are private. Active sessions hold the job's `.calendar-sync.lock` until callers
finish/close. Normal success/failure and stdin EOF remove the job. Termination may leave
a marked orphan for the next import to remove after lease unlock. Session death kills
downloader/converter children. Base `.imports/.calendar-sync.lock` stays as runtime
coordination, not build debris.

Never broadly delete `.imports` during import. Orphan cleanup ignores unmarked, unowned or
linked directories and active jobs. It deletes only known generated regular files without
recursion or permission changes; unexpected contents preserve jobs/ownership markers.
Inspect exact owned artifacts if cleanup reports changed paths, ownership or permissions.
Original ICS, committed snapshot JSON and profiles are not disposable. One-time import
never saves source URLs/passwords, but tokens within event data remain private calendar data.

Guard verification loads units without starting them, checking ExecCondition, Environment,
EnvironmentFiles and UnsetEnvironment. EnvironmentFile entries or state-directory unsetting
fail closed; inspect custom units rather than silently rewriting them. Keep the legacy callback:

```text
conflict_resolution cmd sh -c 'exec "$HOME/.config/quickshell/calendar/parse/conflict-broker.sh" "$1" "$2"' conflict-broker
```

Panel-added pairs pass `CALENDAR_ID=<id>` through `/usr/bin/env` to the same broker.
Group resolution keeps pair separate from calendar ID. New guards retain target UID and
conflict-state path; legacy four-line guards stay supported. Never remove guards to restart sync.

Preserve `on_empty sync` and `on_delete skip`. Never clear a calendar to remove test
events; delete only identified disposable events through the normal whole-series UI.

</details>

## Recovery

A recovery warning means an operation did not finish safely. **Keep the reported files
and leave sync stopped.** Recovery files may contain the only preserved copy of an event
version; they are not ordinary caches.

Do not delete a guard, force another sync or assume the server was rolled back. Some
local-only recovery can finish after a file-permission problem is fixed, but an uncertain
server change needs inspection first. Ask for help with the exact message and paths;
do not share passwords or private calendar links. Live data or server inspection needs
separate permission when someone else is helping.

<details>
<summary>Technical reference and read-only diagnostic commands</summary>

Preserve remaining `group-recovery`, `group-resolution.json` or
`.calendar-series-transaction.json` and keep sync stopped. Never delete guards, bypass
ExecCondition or retry uncertain remote applies. Review resources/pimsync status first.
Serialized `recover-group` finishes verified local/cache recovery, not remote rollback.
Committed resolution with only cache-refresh failure can recover once its target is
writable. Uncertain remote resolution has no automatic override.

Read-only diagnostics after the current version is installed:

```sh
sh "$HOME/.config/quickshell/calendar/parse/conflict-broker.sh" verify-group-guard
sh "$HOME/.config/quickshell/calendar/parse/conflict-broker.sh" check-recovery
systemctl --user status pimsync.service quickshell-calendar-import.path
```

The first two commands should exit 0 silently. Inspect failure diagnostics; never remove
state merely to pass checks.

</details>

## Client update and cleanup

Follow the [update instructions](installation.md#update). Updating replaces program
code, not calendar data. Keep the previous working version until you have opened the new
one and checked it; only then confirm removal of old code. Rollback restores the previous
program and its owned services, **not events or server changes**.

For cleanup:

- Never reinstall or reset live calendar data to remove old files.
- Keep installation records, locks, background service definitions and recovery files.
  A lock file can remain after a normal run; its existence alone does not mean work is active.
- Stop test instances before deleting their files. Remove only exact, inspected disposable
  paths, not whole data/configuration folders. Disconnect disposable imported test calendars
  through the UI first; never disconnect real calendars for a cleanup test.
- If an update or recovery is unfinished, follow its warning before deleting anything.
  Never edit recovery phases or discard newer settings to force confirmation or rollback.

<details>
<summary>Technical reference: update records, confirmation, rollback and inspected-file cleanup</summary>

Never reinstall or reset live data as cleanup. Verify installation/update before deep
cleanup. The [installation guide](installation.md) uses matching archive/checksum assets from stable
`calendar-v<version>` GitHub Releases, not `master` or repository-wide latest.
`--archive PATH` accepts unpublished local candidates/betas with adjacent checksums.
Discovery stays stable-only; betas use `-beta.N`, never the stable tag. Whole-app artifacts
go in `dist/releases/`; never publish test-only `dist/fixtures/`. Keep a known-good module
until updated code passes manual desktop/sync checks. Clients never build source.

Owned `installer/installed.json` records inventory, version and routing. Private
same-filesystem `calendar.update-rollback-<unique-id>/module` holds old code;
`installer/pending.json` binds old/new inventories, unit preimages, configuration hashes
and original activity. Downloads/staging clean after handled success/failure when safe;
unknown/newly tracked artifacts stay. Unrelated backups and calendar/credential data are
never cleanup targets. Old source installs, custom files and incompatible layouts need
separate review.

Interrupted/unconfirmed deployments block replacement. Run `update.sh --confirm` only
after manual verification, with journal `ready` or already-approved `confirming` cleanup.
Interrupted approved deletion continues only for unchanged old-code remainders. Never edit
phases/delete receipts to bypass checks. `update.sh --rollback` restores code/owned units,
not data or remote state. Changed settings/units, pending native recovery or unsafe Git or
routing can stop rollback with services paused for review.

Never unlink `calendar-pimsync.lock` or remove installer state to force another updater.
Persistent locks may remain after normal runs; existence does not prove activity.
Fsynced journals and ordinary-error recovery do not guarantee remote/data atomicity or
exhaustive power-loss/fsync-failure handling.

Stop fixtures before deleting files. Inspect copied transfer/test files; remove only exact,
confirmed-unused paths. Never remove canonical calendars or broadly clean data/config directories.

If an imported test profile still uses an ICS file, detach it through the UI before
confirming file deletion. Never detach real calendars.

```sh
# Replace this placeholder with an exact, inspected disposable archive path.
rm -i -- /path/to/disposable-calendar-archive.tar.gz
```

Missing-file errors mean nothing needs removal. Inspect exact module/helper backup paths;
remove only recognized backups after retaining a newer working copy. Never use broad
`rm -rf` or `git reset`. Fixtures under `parse/output/grouped-resolution-*/manual` are
disposable only after stopping their instances; distinguish fake HOME/data from real stores.

Never remove installer receipts or runtime systemd units/drop-ins. Never remove
recovery guards or bypass conflict callbacks to force sync. Cleanup needs no changes to
Hyprland, credentials, real collections or pimsync status.

</details>
