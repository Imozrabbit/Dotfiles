# Proton Manager

[Back to README](../README.md)

Manage GE-Proton and CachyOS Proton installations, choose an installed GE version
for umu, and inspect official Arch `umu-launcher` package status.

## Setup

Requires Python **3.11+**; Python's standard library handles management.
Optional `pacman` and `checkupdates` provide package status. The manager does
not install packages, synchronize package databases, use sudo, or manage AUR packages.

Merge these settings into your `bar-local.json`, adjusting paths for your machine:

```json
{
  "modules": { "protonManager": true },
  "protonManager": {
    "compatibilityToolsDir": "/home/Steam/.local/share/Steam/compatibilitytools.d",
    "umuConfigPath": "/home/Steam/.config/umu-launcher/config.toml",
    "sandboxCompatibilityToolsDir": "/home/Zrabbit/.local/share/Steam/compatibilitytools.d"
  }
}
```

The three paths are global, not per-monitor. They describe the author's gaming
PC; replace them for your setup. `compatibilityToolsDir` is the host folder
containing installations; `umuConfigPath` is an existing umu TOML file;
`sandboxCompatibilityToolsDir` is the tools folder as seen inside the gaming
sandbox. Without a sandbox, use the same host/tools path for both directory settings.
Paths must be absolute and contain no `..` or NUL. Existing installation/config
directories are required; installation-directory symlinks are not followed.

## Usage

Click the Proton button near the tray, or open it on the focused enabled output:

```sh
qs -c bar ipc call bar protonManager
```

`previewProton` remains a compatibility alias. Outputs in `off` mode cannot
open the manager. One service and popup are shared across monitors.

- **Updates:** check upstream versions, select a family, then use **Update & clean**.
  Confirm the release and exact older versions before continuing.
- **Installed:** inspect versions and request confirmed removal.
- **Launcher:** choose installed GE for umu or use **Sync latest GE** to select
  the newest valid installed GE. Sync does not download anything. Wheel navigation
  alone does not write: click an entry or press Enter to commit.
- **Refresh:** force release and package checks. Opening always checks local
  state; automatic upstream checks run at most once per 24 hours per Quickshell
  session. Restarting allows a new initial check. There is no background polling.

Path edits clear cached inventory and confirmations. Refresh or reopen to
inspect new paths. An active operation keeps its original paths; its old-path
snapshot is discarded on completion. Closing/disabling the popup does not stop work.

## Supported versions

Updates target official GE-Proton **x86_64** and CachyOS Proton **SLR x86_64_v3**,
with matching published SHA-512 checksums. GE names support major/minor/optional
patch and an optional `-x86_64` suffix. New installs use the full archive stem,
such as `GE-Proton11-7-x86_64` or `proton-cachyos-11.0-20261005-slr-x86_64_v3`.
Matching canonical GE archive roots are normalized to the full install name.

Up-to-date status compares versions within a family, not folder names: GE uses
major/minor/patch; CachyOS uses build date, then major/minor. Equal or newer
installed versions count as up to date.

## Safety and recovery

- Downloads stage on the installation filesystem. Checksums, archive paths/links,
  and installation metadata are validated before atomic, no-replace activation.
- GE updates umu before cleanup. Unknown folders, newer versions, and the selected
  umu version are protected. Failed umu writes retain older GE installations.
- Steam/umu/Proton/Wine process evidence blocks changes. Uninspectable executable
  state for the desktop user or installation/config owner also blocks changes.
  A narrowly matched permission-denied `systemd --user` and its direct `(sd-pam)`
  helper are exempt; unknown processes still block. Safety checks repeat before
  activation, config writes, and every removal.
- umu writes preserve TOML comments, unrelated values, and permissions. Unsafe,
  ambiguous, or unsupported TOML spellings fail without rewriting the file.
- If installation succeeds but config/cleanup fails, partial success is reported
  and working files remain. Interrupted staging is hidden from inventory and is
  not deleted automatically. Inspect reported paths before manual recovery.
- Oversized cleanup requests are rejected; remove older versions in smaller groups.

For fixture-based testing without touching gaming paths, see
[development notes](development.md#proton-demo).
