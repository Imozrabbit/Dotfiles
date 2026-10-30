# Installation and updates

Use complete Calendar release packages, not `git pull`, a standalone script from
`master` or a source build on the client. For launch commands and your first event,
see the [README](../README.md).

Source version **`0.1`** is prepared locally but not yet published. Until publication,
use a reviewed local archive and its matching checksum from `dist/releases/`.

## Requirements

| Purpose | Required |
| --- | --- |
| Desktop | Quickshell, Hyprland, Qt 6 |
| Packaged native helpers | Linux x86_64, libical 4, compatible Qt6Core/Qt6Network (`qt6-base`) and C/C++ runtime libraries |
| Installer/updater | Python 3.11+ standard library, systemd/`busctl`, coreutils; Git when installation is inside a checkout |
| Runtime fetch/sync tooling | curl, pimsync (tested with 0.5.7), util-linux `flock` |
| Reminders | `notify-send` (`libnotify`), running desktop notification service |
| Fonts | Atkinson Hyperlegible Next, JetBrainsMono Nerd Font |

Install Python before starting. On Arch Linux, the installer offers other missing
runtime packages through pacman only with approval. No client compilation or third-party
Python packages are needed.

**The supplied archive does not run on every Linux distribution.** Current builds require
Qt `6.12` symbols, `libical.so.4.0`, `GLIBC_2.38` and `GLIBCXX_3.4.32`. The name
`linux-x86_64` identifies the operating system and processor, not general distribution
compatibility. The installer privately probes the native helpers before activation;
this does not replace checking the installed application on your desktop.

## Install

1. Download a **Calendar-specific release** from
   [Releases](https://github.com/Imozrabbit/Dotfiles/releases), not Dotfiles' unrelated
   latest release. Obtain both its `.tar.gz` archive and matching `.sha256` file.
   Unpublished candidates use the matching local files from `dist/releases/`.
2. Put both files in the same folder and open a terminal there.
3. Extract into a **new temporary directory outside the installation target** and run
   the installer from that extracted release.

**Only extract archives from a trusted publisher.** Checksums detect a changed/corrupt
download, not a compromised publisher. Run the following commands one at a time;
continue only if each succeeds and the checksum command reports **OK**:

```sh
sha256sum -c calendar-v0.1-linux-x86_64.tar.gz.sha256
mkdir -m 700 calendar-install
tar -xzf calendar-v0.1-linux-x86_64.tar.gz -C calendar-install
sh calendar-install/calendar/install.sh --archive "$PWD/calendar-v0.1-linux-x86_64.tar.gz"
```

The target is `~/.config/quickshell/calendar`, even when its Quickshell parent is a
symlink. Fresh installation starts empty (`{"version":1,"profiles":[]}`). It does not
select sources, ask for calendar passwords, enable/start services, launch Calendar or
change Hyprland. Start Calendar yourself and add calendars through **Manage calendars**.

Existing module/data, old installation records or unsafe/linked settings stop installation
for separate review. **Never delete calendar data, settings or recovery files to force it.**
No legacy source-setup or configuration-localization script runs.

Keep pimsync configuration and `secrets/` in a real private local directory, not a Stow
link into published dotfiles. Exclude credentials and runtime settings from Git on every
branch. Installer/updater never migrate linked configuration, untrack files or silently
adopt an unknown layout. See [private configuration](maintenance.md#local-only-pimsync-configuration).

## Git checkouts

Skip this section for a standalone installation outside Git.

An installed calendar inside a checkout must be **ignored and untracked**. The Quickshell
parent may be a symlink; `calendar/` itself must be a real directory without a nested Git
repository. Neither the index nor `HEAD` may track calendar files: staged removal alone
is insufficient. Commit their removal on the client's branch before installation.

The installer can ask to add narrowly anchored checkout-local excludes, then verifies them
after resolving parent symlinks. It never stages or untracks files. Alternatively, use
these rules in Quickshell's **parent-level** `.gitignore`, outside `calendar/`, or equivalent
anchored repository policy:

```gitignore
/calendar/
/.calendar-install.*/
/calendar.update-rollback-*/
```

Keep this policy on the client's branch; do not merge calendar's removal into the publishing
branch. Merges or branch switches can restore tracking or conflict with local files. Do not
change tracking/ignore rules during an update or while awaiting confirmation. The updater
rechecks them before replacement and cleanup; other Quickshell projects stay untouched.

## Update

Run from your **active desktop-session terminal**, not a plain SSH session:

```sh
sh "$HOME/.config/quickshell/calendar/update.sh"
```

For a newer reviewed local candidate, keep its adjacent checksum and pass its exact archive
path (example: `0.2`; explicit beta candidates use the same option):

```sh
sh "$HOME/.config/quickshell/calendar/update.sh" --archive /absolute/path/calendar-v0.2-linux-x86_64.tar.gz
```

Only installations with a verified installation record (**receipt**) can update. Source
checkouts, older/unknown layouts, data-schema changes or changed runtime-unit membership
need separate reviewed migration; there is no automatic migration switch.

Changed/unexpected program files, custom service definitions or effective overrides,
pending native recovery, an instance on another display or a busy lifecycle lock stop the
update safely. Read the message rather than removing files or bypassing checks.

Updates replace program files, not events, UIDs, recurrence, reminders, sync settings,
databases, credentials, ownership or permissions. Unknown/custom program files are refused,
not silently replaced. Ordinary failures restore prior code, owned services and activity
when safe; uncertain failures keep recovery copies instead of overwriting newer changes.

### Confirm or roll back

Successful updates keep the previous version. **Open Calendar and verify it first**, then
approve permanent removal of the old code:

```sh
sh "$HOME/.config/quickshell/calendar/update.sh" --confirm
```

Or restore the previous program and owned services, **keeping current calendar data**:

```sh
sh "$HOME/.config/quickshell/calendar/update.sh" --rollback
```

Rollback does not restore events or undo server changes. Confirmation/rollback run locally
without downloading scripts. Another update is blocked while `installer/pending.json`
exists. If settings changed after the update, rollback may need manual review; never discard
those changes to force it.

Keep installation records, locks and recovery files. Changed service paths, files or Git
policy can leave jobs paused and copies retained for inspection. A fresh install killed
before its receipt is complete needs review, not blind reinstallation. Recovery does not
guarantee every power-loss/failed disk-flush (fsync) case or make remote/data changes atomic.
See [recovery](maintenance.md#recovery) and [cleanup](maintenance.md#client-update-and-cleanup).

## Release selection

Without `--archive`, the extracted `install.sh` and installed updater choose the highest
stable numeric `calendar-v<version>` release and matching checksum. They never use the
repository-wide `/latest` release or fetch executable raw-master scripts.

Beta tags are excluded even if GitHub incorrectly marks them stable. Beta install/update
requires explicit `--archive PATH`; there is no automatic beta channel. For the same base
version, numeric ordering is `beta.2 < beta.10 < stable`. Versions `0.1` and `0.1.0` compare
equal; do not publish both. Unsupported prerelease forms and downgrades are refused.

## Technical verification and records

The installer checks checksum, exact runtime manifest, paths/types/modes, version and ELF
architecture before probing helpers. Packages contain runtime QML/JS, Python/shell deployment
files, manifest/version, conflict broker and prebuilt helpers—not native source, Makefile,
tests, developer docs/tooling or private data. Receipts live under
`${XDG_STATE_HOME:-$HOME/.local/state}/quickshell-calendar/installer/`.

The updater validates/probes the release in private same-filesystem staging, snapshots owned
units/metadata and active/enabled states, takes persistent lifecycle locks, and keeps a fsynced
journal plus the old module. Changed owned definitions need approval and use canonical native
templates. Only Calendar and its managed daemon, watchers, timers and workers pause. Previously
active units resume without enablement changes; an active import watcher queues one cache
refresh. Calendar restarts/IPC-checks only if previously running. Unrelated services stay untouched.

For source builds, release packaging, stable tag/title rules, version-only promotion and
maintained local tests, see [development](development.md#local-runtime-release-packaging).
Building a package does not commit, publish or install it. Never replace an installed
version's assets; publish a higher version after the required checks.
