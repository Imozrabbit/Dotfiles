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

Outputs in `off` mode cannot open the manager. Closing/disabling it does not stop
an active operation. If paths change during work, that operation uses its original
paths; refresh or reopen afterwards.

- **Updates:** check upstream versions, select a family, then use **Update & clean**.
  Confirm the release and exact older versions before continuing.
- **Installed:** inspect versions and request confirmed removal.
- **Launcher:** choose installed GE for umu or use **Sync latest GE** to select
  the newest valid installed GE. Sync does not download anything. Wheel navigation
  alone does not write: click an entry or press Enter to commit.
- **Refresh:** force release/package checks. Opening checks local state; automatic
  upstream checks run at most once per 24 hours per Quickshell session, with a
  new initial check allowed after restart. There is no background polling.

## Supported versions

Updates target official GE-Proton **x86_64** and CachyOS Proton **SLR x86_64_v3**,
with published SHA-512 checksums. Install names use the full release archive stem.
Versions are compared within each family; equal or newer installs count as up to date.

## Safety and recovery

- Downloads, archive paths/links and metadata are validated before installation;
  existing installations are not overwritten.
- GE updates umu before cleanup. Unknown folders, newer versions, and the selected
  umu version are protected. Failed umu writes retain older GE installations.
- Running Steam/umu/Proton/Wine or unreadable/unknown process state can block
  changes. Close gaming processes and read the reason; do not bypass safety checks.
- umu writes preserve TOML comments, unrelated values, and permissions. Unsafe,
  ambiguous, or unsupported TOML spellings fail without rewriting the file.
- If installation succeeds but config/cleanup fails, partial success is reported
  and working files remain. Interrupted staging is hidden from inventory and is
  not deleted automatically. Inspect reported paths before manual recovery.
- Oversized cleanup requests are rejected; remove older versions in smaller groups.

For client errors, see [troubleshooting](setup.md#troubleshooting).
