# Calendar

Desktop calendar for Quickshell and Hyprland, with Week, Month and 14-day Agenda
views. Supports editable local calendars, read-only ICS imports, CalDAV sync through
pimsync, reminders, holiday labels and whole-event Local/Remote conflict review.

## Recurring events

Local and Personal calendars support Daily, Weekly with multiple weekdays, Monthly
dates or ordinal weekdays, and Yearly month/date pairs. Each supports an interval
and Never, inclusive Until, or total Count ending. Missing dates and nonexistent DST
start times are skipped; duplicate matches count once.

Timed events retain their creation timezone and duration; views use local time.
All-day events occupy one date. Editing/deletion applies to the whole series.
Imported exceptions and foreign rules that cannot be edited losslessly stay
read-only. Incomplete or conflicting synced groups stay protected until reviewed.

## How it works

`shell.qml` connects storage services to the window and exposes `calendar.toggle`.
Local events are JSON; imports are converted from ICS; synced ICS files are canonical
and their JSON cache is rebuildable. Native C++/libical helpers expand only requested
ranges. QML renders occurrences, rather than implementing recurrence arithmetic.

Yearly date pairs may span several standard ICS resources but appear as one series.
The broker pauses sync and journals grouped writes; conflicts choose a complete
Local or Remote series. Local journaling does not make remote synchronization atomic.

Data defaults to `~/.local/share/calendars`; sync configuration/credentials and
recovery state remain outside the module. Installation does not reset existing
calendar data. [Storage, recovery and cleanup](https://github.com/Imozrabbit/Dotfiles/blob/master/ArchLinux/QuickShell/.config/quickshell/calendar/docs/maintenance.md).

## Dependencies

| Purpose | Required |
| --- | --- |
| Desktop | Quickshell, Hyprland, Qt 6 |
| Native helpers | libical, Qt6Core, C++17 compiler, Make, pkg-config |
| Installer | curl, tar, systemd, standard POSIX/coreutils tools |
| Sync/import services | pimsync, systemd user services, util-linux `flock` |
| Updater | jq, systemd `busctl`, existing desktop-session environment |
| Fonts | Atkinson Hyperlegible Next, JetBrainsMono Nerd Font |

PC-local tests additionally use Node.js, jq and Python/PySide6. Tests/editor/agent tooling
are intentionally excluded from Git and client installations. See
[development checks](https://github.com/Imozrabbit/Dotfiles/blob/master/ArchLinux/QuickShell/.config/quickshell/calendar/docs/development.md#checks).

## Install

Download and inspect the installer, then run it:

```sh
curl -fsSLo calendar-install.sh 'https://raw.githubusercontent.com/Imozrabbit/Dotfiles/master/ArchLinux/QuickShell/.config/quickshell/calendar/install.sh'
sh calendar-install.sh
```

It downloads GitHub's `master` archive, extracts only this module into
`~/.config/quickshell/calendar`, and builds both native helpers before replacing an
existing module. Development tests/tools, docs, Git policy, prebuilt PC binaries,
generated output and archives/logs/caches are excluded from deployment; native build
sources and runtime scripts remain. Docs and `.gitignore` stay tracked in Git.
Replacement and timestamped backup require your choices. Missing
packages can be installed with approval; sync sources are selected interactively.
Supply your own feed URL/CalDAV credentials for selected sources.

Setup installs user sync/import services and a recovery startup guard. Existing
custom configuration and non-empty unmanaged directories require review rather
than silent replacement. Failed setup can be rerun; receipts track completed steps.
No `.git` checkout is needed in the installed module.

## Run

For a source checkout, first build both helpers:

```sh
make -C parse convert calendar-sync-helper
quickshell -c "$HOME/.config/quickshell/calendar"
```

Toggle the running window:

```sh
quickshell -c "$HOME/.config/quickshell/calendar" ipc call calendar toggle
```

Use these commands in your existing startup/keybind configuration. The installer
does not edit Hyprland settings. Single-click selects; double-click opens details or
conflict review. Ctrl-wheel adjusts zoom in each view; ordinary wheel scrolls.

## Update

**PC:** publish reviewed changes to GitHub `master` first. Uncommitted/unpushed work
is not available to the updater. Git checkouts/symlinked modules are not updater
targets; maintain the source checkout normally.

**ThinkPad / standalone installation:** from a desktop-session terminal:

```sh
sh "$HOME/.config/quickshell/calendar/update.sh"
```

For an older installation without `update.sh`, bootstrap after publication:

```sh
sh -eu -c 'work=$(mktemp -d "${XDG_RUNTIME_DIR:?Run from your desktop session}/calendar-bootstrap.XXXXXXXX")
cleanup() { rm -rf -- "$work"; }
trap cleanup EXIT
trap "exit 129" HUP
trap "exit 130" INT
trap "exit 143" TERM
curl -fsSLo "$work/update.sh" https://raw.githubusercontent.com/Imozrabbit/Dotfiles/master/ArchLinux/QuickShell/.config/quickshell/calendar/update.sh
sh "$work/update.sh"'
```

Updater fetches current installer, builds the complete module in staging and keeps
a temporary rollback copy. Source/credential setup is skipped. Only calendar's
running instance and relevant services are paused/restarted; disabled/inactive units
are not enabled. A running import watcher gets a one-shot cache refresh. Compatible
manual service definitions are preserved; changed import definitions need approval.
Pending recovery or unsafe/custom guard settings stop the update.

Open calendar and verify it, then answer **yes** to permanent rollback cleanup.
Previous module (including its old transfer archives), temporary downloads and
object files are removed. Local edits inside the module are replaced; event stores,
credentials and pimsync status remain outside it and are not replaced.

If not ready to confirm, answer no; verify later and run:

```sh
sh "$HOME/.config/quickshell/calendar/update.sh" --confirm
```

Another replacement is blocked while confirmation/recovery is pending. Ordinary
failures restore prior code/runtime when safe; uncertain recovery retains files for
review. Never delete recovery receipts or bypass guards to force an update.

[Development, recurrence contracts and verification limits](https://github.com/Imozrabbit/Dotfiles/blob/master/ArchLinux/QuickShell/.config/quickshell/calendar/docs/development.md).
