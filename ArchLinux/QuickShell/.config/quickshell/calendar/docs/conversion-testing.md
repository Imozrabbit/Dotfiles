# Manual conversion test

This optional walkthrough checks both ways of changing a calendar:

- **Attach to remote** connects a local calendar to an online calendar and syncs both ways.
- **Convert to local** stops that connection after one final sync, keeping events here.

Here, **local** means this computer; **remote** or **server** means your online calendar
service. A remote **collection** is one calendar on that service. A **conflict** means
the same event has different versions here and on the server.

**Use disposable calendars only. These steps upload and replace events on the server.**
Never use Personal, SEME, or any calendar with events you need. Run this test yourself;
automated implementation checks do not authorize an assistant to change live calendars.

## 1. Prepare a disposable test pair

1. Choose one remote setup:
   - Existing collection: in the server UI or another client, create an empty collection
     named `Conversion remote test` and record its identifier and address (href).
   - New collection: reserve unused identifier `conversion-created-test` and name
     `Conversion created test` for step 3; do not create it yet.
   Do not add another synced calendar entry for this same target or use a real calendar.
2. In Quickshell **Manage calendars → New calendar**, create a **local** calendar:
   - Name: `Conversion local test`.
   - ID: `conversion-test-local` (or another unused ID).
   - Choose an obvious color; leave it visible.
3. Add two ordinary test events on visible dates:
   - `Conversion A — base`, with a description/location and a reminder.
   - `Conversion B — base`, at another time.
4. Record their times and the calendar's ID, name, color and visibility.
5. Have your server URL, username and private password file ready. Do not
   copy password contents into event fields or terminal commands.

If Calendar is not running, use the [installed Calendar launch command](../README.md#run).
If already running, use your normal reload/reopen; do not start a second instance.

<details>
<summary>For maintainers: source-checkout launch example</summary>

This is the maintainer's machine-specific source path, not the installation path for
other users. For a prepared development checkout at that location, launch only this config:

```sh
quickshell -c /home/Zrabbit/Documents/Dotfiles/ArchLinux/QuickShell/.config/quickshell/calendar
```

</details>

## 2. Check the compact manager controls

1. Open **Manage calendars**. Cards start collapsed, without wide conversion/deletion
   buttons below the icon row.
2. Click the local test calendar's opposing arrows (**⇄**, **Conversion options**).
   - Its card expands and shows **Attach to remote**.
   - No connection form, conversion session or sync starts.
3. Click the same icon again: the card collapses.
4. Expand its trash icon (**Removal options**).
   - **Delete local** appears without a deletion confirmation.
   - Conversion choices close. Do not select deletion during this test.
5. Optionally create a second empty disposable local calendar and expand its options:
   the previous card closes. Do not use Personal/SEME for this check.
6. Use Tab to focus these controls, then Space/Return/Enter to activate them. Check they
   also fit in a narrow window.
7. Return to the disposable calendar and expand **Conversion options**.

## 3. Local → remote, empty collection

1. Select **Attach to remote** to open the attachment form.
2. Check ID/name/color stay unchanged, not replaced by remote metadata.
3. Enter the server URL and username; select your existing password file.
4. Click **Connect**, then either:
   - Choose the exact existing disposable collection from step 1; or
   - Choose **Create new remote calendar…**, enter `Conversion created test` as remote
     name and unused `conversion-created-test` as collection identifier. The option
     must appear even in an empty account.
5. Leave the refresh interval at five minutes or more. Existing target: **Attach and sync**.
   New target: **Create and attach** creates the server calendar before connecting and syncing.
   Selecting the option or entering names alone must create nothing.

For a new target, **Cancel** before submitting, verify no collection was created, then
reopen and repeat. After creation, Cancel/failure never deletes the collection. If
preparation fails, retry **Attach and sync** against the selected existing target.
An uncertain reply requires **Connect** and explicit selection, not repeated creation.
Do not force live failures; isolated fixtures cover them.

Expected:

- An empty collection needs no conflict choices. Calendar switches to synced and starts
  its first sync automatically; this direction has no final Convert confirmation.
- The calendar entry becomes `synced`; its ID, name, color and visibility stay unchanged.
- Both events stay visible and editable, with unchanged times, details and reminder.
- Refresh the other client: both events appear in the disposable remote collection.
- The row reports a successful update, not remote deletion or conversion to local.

First sync is immediate; do not wait for the timer to verify success.
Refresh the other calendar app explicitly if it still shows an older copy.

## 4. Synced → local, then build real UID conflicts

1. On the now-synced test card, open **Conversion options → Convert to local**.
2. With no conflicts, the manager offers the final **Convert** button.
   - Try **Cancel** first. It must remain synced with the same events.
3. Select **Convert to local** again, then final **Convert**.
   - This performs one final calendar-wide sync before disconnecting.
   - The calendar entry becomes `local`; its settings/events and the server calendar remain.
4. Reopen the calendar and confirm events remain editable.
5. While it is disconnected, edit the **existing** A and B events locally:
   - A title: `Conversion A — LOCAL`.
   - B title: `Conversion B — LOCAL`.
6. In the other client, edit the same **existing remote events**, without deleting or
   recreating them:
   - A title: `Conversion A — REMOTE`.
   - B title: `Conversion B — REMOTE`.
7. Add `Unique local event` locally and `Unique remote event` remotely.

Each event carries a unique internal identifier, its **UID**. This round trip preserves
those UIDs, so editing the existing events creates genuine matching-event conflicts.
Creating separate events with similar titles or times does not.

## 5. Populated collection: Cancel and choose winners

**Confirming the last conflict automatically runs a final refresh, switches the calendar
to synced and starts a sync that can write to the server.** There is no further approval
button. Test Cancel before confirming the last choice.

1. Reattach the local test calendar to that same disposable remote collection using
   **Conversion options → Attach to remote → Connect → select → Attach and sync**.
2. Review should show differing A/B versions, without conflicts for unique events.
3. Before confirming all conflicts, select **Cancel conversion**.
   - The calendar stays local with its LOCAL titles and unique local event.
   - The server retains its REMOTE titles and unique remote event.
   - No reviewed winner has been uploaded.
4. Reattach. For A select **THIS DEVICE**, then **Confirm**. For B select
   **SERVER**, then **Confirm**.

Expected after completion:

- The calendar is synced with unchanged ID, name, color and visibility.
- A is `Conversion A — LOCAL` on both devices.
- B is `Conversion B — REMOTE` on both devices.
- Both unique events exist locally and remotely, without logical duplicates.
- **Keep local, leave server unchanged** is absent: it belongs only to synced→local review.

Close/reopen normally. Verify the calendar stays synced, both sides' unique events and
chosen titles remain, and the successful status persists.

## 6. Optional: final-refresh choice retention

Repeat step 4 for local A/B versions with matching server UIDs, then edit them differently
on each side.

1. Begin attachment and confirm a choice for A, leaving B unresolved.
2. Before confirming B, edit remote B again in the other client; wait for the server save.
3. Confirm B's now-outdated displayed version.
4. Final refresh should ask you to review B again. A's unchanged choice stays saved for
   this conversion.
5. Review the new B content and confirm it. Automatic completion resumes.

Do not edit from another client after final refresh until the sync finishes. Calendar
cannot lock the whole server while it checks and applies your choices.

## 7. Optional recurrence and recovery checks

- Create a repeating test event in Calendar, then repeat attach → convert-to-local →
  edit locally → reattach. Review must select the whole series, not individual files
  that represent it. Start with ordinary A/B events; other apps may rewrite recurrence details.
- **Cancel** the connection form; calendar entry, type and events must stay unchanged. Reopening the
  manager should leave action categories collapsed.
- If attachment fails before a sync that can write to the server, verify the original
  local calendar remains. If a warning says local data or settings changed, reopen the
  conversion; never bypass the safety check.
- If a sync that can write to the server may have started, the calendar must not silently revert to local.
  Use attachment **Retry** when shown; after cleanup, use **Refresh** or conflict review.
  Do not force failures, delete recovery records or kill running sync jobs; isolated
  automated tests cover interrupted and partial writes.

Stop and report changes to non-test calendars, missing events, the wrong calendar type,
repeated automatic submissions or warnings naming retained recovery files. Keep those
files until the cause is understood.

After successful testing, remove only unneeded disposable calendars.
**Removal options → Delete local** removes the test calendar from this device, not the
server calendar; delete that separately in the server UI. Do not clean up during
pending conversion or recovery.
