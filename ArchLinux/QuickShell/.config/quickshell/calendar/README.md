# Calendar

Desktop calendar for **Quickshell and Hyprland on Linux**, with Week, Month and 14-day
Agenda views, recurring events, reminders and holiday labels. Use local calendars,
read-only calendar files/links, or editable online calendars through CalDAV.

## Requirements

- **Linux x86_64**, **Quickshell**, **Hyprland**, **Qt 6** and **Python 3.11+**.
- pimsync for online calendars; `notify-send` and a desktop notification service for reminders.
- Compatible system libraries and fonts: see [exact requirements](docs/installation.md#requirements).

Install Python first. On Arch Linux, the installer can offer other missing runtime
packages with your approval. No client compilation or third-party Python packages are needed.
**The supplied archive does not run on every Linux distribution**; the installer checks compatibility.

## Install

Download the `.tar.gz` archive and matching `.sha256` file from a
[Calendar-specific GitHub Release](https://github.com/Imozrabbit/Dotfiles/releases).
Do not use Dotfiles' unrelated latest release or a standalone install script from `master`.

Put both files in one folder and open a terminal there.
**Only extract packages from a trusted publisher:** checksums detect changed downloads,
not publisher compromise. Use a new temporary directory outside the install target.
Run commands one at a time; continue only if each succeeds and the checksum reports **OK**:

```sh
sha256sum -c calendar-v0.1-linux-x86_64.tar.gz.sha256
mkdir -m 700 calendar-install
tar -xzf calendar-v0.1-linux-x86_64.tar.gz -C calendar-install
sh calendar-install/calendar/install.sh --archive "$PWD/calendar-v0.1-linux-x86_64.tar.gz"
```

This installs to `~/.config/quickshell/calendar` with no calendars. It does not launch
Calendar, start services or edit Hyprland. Existing calendar data is not reset.
**If existing data or settings block installation, stop and review the warning—do not delete them.**
For Git-based installations, updates, confirmation or rollback, use the
[installation guide](docs/installation.md).

## Run

Start Calendar:

```sh
quickshell -c "$HOME/.config/quickshell/calendar"
```

Show or hide its window while it is running:

```sh
quickshell -c "$HOME/.config/quickshell/calendar" ipc call calendar toggle
```

Use the toggle command instead of starting a second instance. Add these commands to
your startup/keyboard-shortcut settings yourself if wanted; the installer does not do it.

## Your first calendar and event

1. Open the settings gear (**Manage calendars**) → **New calendar**.
2. Enter a name, a unique ID such as `work-calendar`, and a color. Choose **local**, then **Save**.
3. Click the calendar-plus icon beside **Today** to open **New event**.
4. Choose your calendar, enter a title and dates/times, then **Create**. Repetition and
   reminders are available in the same form.

The ID is an internal name that stays fixed when you rename the calendar. Imported files
and URL subscriptions are read-only; creating events requires a local or synced calendar.
**Editing or deleting a recurring event affects the whole series.** Reminders work only
while this Quickshell configuration runs, even if its window/calendar is hidden.

- Choose Week (**週**), Month (**月**) or Agenda (**程**); navigate with arrows or **Today**.
- Click an event to select it; double-click for details or conflict review.
- Scroll normally to move through a view; hold **Ctrl** while scrolling to zoom.
- Click a calendar name in the main window's list to show or hide its events.

## Guides

- [Import a calendar file](docs/maintenance.md#one-time-import-workspace)—successful import moves the selected original.
- [Subscribe to an online calendar link](docs/subscriptions.md).
- [Connect an editable CalDAV calendar](docs/maintenance.md#panel-added-caldav).
- [Conversion, removal and recovery](docs/maintenance.md)—read before changing a connection or deleting data.
- [Conversion walkthrough](docs/conversion-testing.md)—optional; disposable calendars only.
- [Development, recurrence rules and reminder limits](docs/development.md).

## Roadmap

### Implemented in 0.1

- [x] Editable local calendars, read-only ICS imports and read-only URL subscriptions.
- [x] Two-way CalDAV sync, server-calendar creation and conflict review.
- [x] Conversion between local and synced calendars; keep-local recovery when a server calendar is unavailable.
- [x] Local deletion, or server-calendar deletion that keeps a reviewed local copy.
- [x] Recurring events and reminders.
- [x] Release-package installation, updates, confirmation and rollback without resetting calendar data.

### Planned features

- [ ] Portable export/import for profiles, events, recurrence, source settings,
  credentials and machine-specific recovery/state—not just ICS files.
