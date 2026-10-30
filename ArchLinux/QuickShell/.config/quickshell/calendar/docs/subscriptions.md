# Read-only URL calendars

A **subscription** shows events from an online calendar link and refreshes them
automatically. It is **read-only**: you cannot edit those events or send changes back.
Use a [synced CalDAV calendar](maintenance.md#panel-added-caldav) if you need
two-way editing, or [import a file once](maintenance.md#one-time-import-workspace) if no link is needed.

You need a **direct ICS URL**: a link to calendar data, not a webpage that asks you to
sign in. ICS is the standard `.ics` calendar-file format. This form does not handle
browser login or single sign-on (SSO); obtain a direct feed link from the provider.
Links starting with `webcal://` or `webcals://` are converted to HTTPS.

**Treat private calendar links like passwords.** Links may contain access tokens that
let others read your calendar. Keep settings and their backups private; do not paste
the link into public logs or screenshots.

## Add and refresh

1. Open the settings gear (**Manage calendars**) and choose **New calendar**.
2. Set type to **subscription**. Enter a name, color and direct ICS URL.
3. Leave ID blank to generate one, or choose a unique ID yourself. This internal name
   stays fixed when you edit the calendar later.
4. Choose a refresh interval, then **Save**. The default is **10 minutes**, minimum
   **5 minutes**; the form accepts minutes, hours or days.

Calendar checks the link and downloads the events before adding the calendar to the
list. A valid feed with no events is accepted. If adding fails, your entries stay in
the form and no successful addition is reported.

Use **Refresh now** on that calendar's edit form to fetch updates immediately. Automatic
refresh can continue with Calendar closed while its background user services are running.
There is no separate download preview.

A background refresh advances the last-success time only when event data changes.
An unchanged feed does not clear an earlier error automatically. Use **Refresh now**
to confirm that the feed works again, even when its events have not changed.

<details>
<summary>Technical reference: settings, background services and stored files</summary>

URL and interval are stored in the private managed section of
`$XDG_CONFIG_HOME/pimsync/pimsync.conf`. Profiles contain appearance/type, not URLs.
Links with tokens are sensitive; keep configuration and reference backups private.

Add writes the one-way pimsync source/pair and shared runtime definitions, runs
`pimsync check` and `pimsync sync <pair>`, then converts the downloaded ICS collection.
The profile appears only after all steps and required service activation succeed.
Valid empty feeds are accepted.

Shared `pimsync.service` runs `/usr/bin/pimsync daemon` with per-source
intervals. Shared `quickshell-calendar-import.path` watches all URL collections;
its service runs `calendar-sync-helper subscriptions cache` to convert caches and
update status. There are no per-calendar timers or private download previews.
Refresh continues with Quickshell closed if the user manager runs.
**Refresh now** syncs/converts the selected pair.

Background success timestamps advance only when converted data changes; unchanged
caches do not clear feed errors. **Refresh now** confirms recovery even without changes.

| Resource | Default path |
| --- | --- |
| ICS files | `~/.local/share/calendars/<id>/` |
| JSON cache | `~/.local/share/calendars/<id>.json` |
| Pimsync DB | `~/.local/state/pimsync/status/qs_subscription_<id>.status` |
| UI status | `~/.local/state/quickshell-calendar/subscriptions/status.json` |
| Profile entry | `~/.local/share/calendars/profiles.json` |
| Source/pair | `~/.config/pimsync/pimsync.conf` |

The native listing returns collection/cache/status paths. Removal uses known IDs/paths,
not a filesystem search. Missing source/configuration/data files do not block ID-based
cleanup; removal never recreates missing pimsync configuration.

Shared runtime files live under `~/.config/systemd/user/` (with XDG overrides):
`pimsync.service`, `quickshell-calendar-import.path`,
`quickshell-calendar-import.service`, and
`pimsync.service.d/calendar-group-recovery.conf`. Enablement links for daemon/watcher
are managed by systemctl; there are no per-calendar timers.

</details>

## Edit a subscription

Open **Manage calendars → Edit** for that calendar, change its settings, then **Save**.
Changing its name, color or refresh interval needs no new download. A changed URL is
downloaded and checked before it replaces the previous one. Reported failures preserve
the existing settings and displayed events.

If the form reports that settings changed while it was open, reopen it before saving.
Refreshing another subscription can cause this check; do not force an outdated form through.

## Remove a URL calendar

Open the subscription's trash icon → **Removal options → Delete local**, then choose
**Delete** in the confirmation naming that calendar.
**Cancel** changes nothing. Removal permanently deletes local copies, never online
events, and makes no requests to the feed.

Other calendars keep the background services they need. Normal errors before deletion
takes effect restore the old files and service state. A crash or power loss is different:
there is **no automatic crash recovery or retry**.

If the message says **Calendar removed; temporary cleanup incomplete**, removal succeeded
but temporary copies remain at the reported location. Inspect the warning before deleting
anything. If restoring files after a failure also fails, keep the reported recovery
files; do not treat them as disposable copies.

<details>
<summary>Technical reference: removal, shared services and rollback limits</summary>

The native helper stops relevant shared jobs and reversibly stages the selected ICS
collection, JSON and pimsync database/SQLite companions on their filesystems. It removes
source/pair and UI-status entries, updates the shared watcher, then removes the profile
last in the reversible phase. Previously running jobs resume if remaining calendars
need them. Shared registry/lock/storage roots stay for empty startup and future additions.

After the last URL subscription, unused owned import/watcher units and enablement links
are removed. The owned daemon and recovery drop-in stay while any configured pair needs
them; customized daemon definitions are preserved. Missing owned definitions still have
their known user/runtime enablement links cleaned; links to unrelated definitions stay.

Shared file contents/modes and enabled/running state stay in memory until commit.
Ordinary pre-commit failures restore moved files and prior metadata/runtime. There is no
permission preflight, durable journal, crash recovery or automatic retry. Staging
directories use 0700; new files use existing private permissions; rollback preserves modes.

After commit, staging is purged. Purge failure reports **Calendar removed; temporary
cleanup incomplete**, with remaining location and error; removal is not rolled back.
Failed rollback retains recoverable staging and reports its path; never discard it blindly.

</details>

## Errors and current scope

An ordinary failed Add removes settings/files created by that attempt and restores the
previous background services. Existing calendars and their displayed data stay intact.
If a refresh fails, read its error rather than repeatedly removing and re-adding the calendar.

Killing the process or losing power while adding a subscription may require manual cleanup.
Do not delete recovery files or bypass a safety check to retry. See
[maintenance and recovery](maintenance.md#recovery).

<details>
<summary>Technical reference: settings changes and recovery boundaries</summary>

Errors retain form values without reporting success. Ordinary failed adds remove new
configuration/files and resume previously running jobs. Failed activation also restores
shared unit enablement. Reported failures preserve existing caches/configuration.
Metadata/interval edits need no download; changed URLs are fetched before publication.

No durable settings recovery journal is written. Process death or power loss mid-add
can require manual cleanup; there is no automatic crash recovery. The independent
grouped-event recovery guard remains enforced.

This removal flow applies only to URL subscriptions, not local-file imports or
Personal-style sync. Another subscription's refresh can invalidate an open edit form;
reopen before saving if it reports changed settings.

</details>

## Manual check

Use a disposable feed/calendar for this optional check. Run it yourself; do not remove
a real calendar merely to test cleanup.

1. Add a subscription. Check that events are read-only and remain after restarting Calendar.
2. Check its refresh interval and **Refresh now**.
3. Try a bad URL for a new subscription. It should show an error without adding a calendar
   or disturbing another one.
4. Cancel removal once, then delete the test subscription. Re-add its ID and remove it again.
   When removing one of several feeds, verify the others stay intact; also test the last feed.

For a full technical cleanup check, verify that its collection/cache/DB,
configuration/profile/status references and unused user units/enablement links are gone.
Normal use does not require manually deleting these files.
