# Proton manager backend

Status: reconstructed from previously approved backend requirements. Review this
written specification before producing the implementation plan. No product code
has changed during this reconstruction.

## Goal and scope

Replace the accepted Proton manager preview's placeholders with real state and
safe operations. Preserve its appearance, per-output opening behavior, three
tabs, inline GE selector, confirmation overlay, and shared progress footer.
Management remains optional, controlled by `modules.protonManager`.

Support GE-Proton x86_64 and CachyOS Proton SLR x86_64_v3 only. Check official
Arch `umu-launcher` package status without installing or updating packages.
No Activity tab, raw log viewer, background upstream polling, new dependencies,
or unrelated bar refactoring.

## Architecture

- Group module code under `proton/` using ordinary relative QML imports.
- `Manager.qml`: window lifecycle, card geometry, tabs, and composition. Keep
  tabs, scroll viewport, and action row directly inside the tab card.
- `UpdatesTab.qml`, `InstalledTab.qml`, `LauncherTab.qml`: presentation and
  actions through explicit service properties/signals. Extract the GE selector
  and confirmation panel only where this keeps these components comprehensible.
- `Palette.qml`: one module-local, named color section grouped into surfaces,
  borders, text, semantic states, and interaction states. Preserve existing colors
  and continue using the bar theme's font and inherited dim text color.
- `Service.qml`: one shared instance, operation state, subprocess lifecycle,
  validated helper events, and tab-specific results. Do not create processes per
  output. Instantiate only when an enabled output uses the module.
- `backend.py`: on-demand Python standard-library helper for inspection,
  release checks, filesystem transactions, TOML changes, and process checks.
  JSON requests and newline-delimited JSON events; no shell interpolation.

## Configuration and data

Add a global, validated `protonManager` configuration object to existing bar
configuration. Paths are not per-monitor settings; they describe one shared
installation/configuration. Document host-specific overrides.

Current host defaults:

- Compatibility tools: `/home/Steam/.local/share/Steam/compatibilitytools.d`.
- umu config: `/home/Steam/.config/umu-launcher/config.toml`.
- Sandbox-visible compatibility tools:
  `/home/Zrabbit/.local/share/Steam/compatibilitytools.d`.

Read/install using host paths; write the corresponding sandbox-visible version
path into `[umu].proton`. Invalid paths, inaccessible directories, malformed
TOML, missing commands, and uninspectable running-process state produce stable
unavailable/blocked results, not invented defaults or destructive fallback.

Recognize installations by supported family/version naming plus valid local
Proton installation metadata and launcher. Do not follow installation-directory
symlinks or treat arbitrary folders as cleanup candidates. GE choices contain
valid installed GE versions only, sorted newest-first. Exclude CachyOS, unknown
folders, and Steam-managed installations.

## Inspection and release checks

Opening the manager inspects local state and checks releases on demand; explicit
Refresh repeats checks. Reuse the latest service snapshot across monitors and
serialize checks against operations. No continuously running upstream timer.

Use official GitHub repositories `GloriousEggroll/proton-ge-custom` and
`CachyOS/proton-cachyos`, selecting the exact requested architecture/build and
matching published checksum asset. Reject ambiguous/malformed metadata, unsafe
URLs, and unavailable checksums. Apply timeouts and bounded metadata reads.
Report API/network/rate-limit failures independently for each family.

Package status distinguishes installed, update available, not installed, and
unavailable. Use `pacman` for installed identity and `checkupdates` for current
official-repository update evidence; missing/failed commands must not imply
up-to-date. Do not alter the host package database or run package installation.

## Mutations and safety

All mutations are serialized by the service and an interprocess helper lock.
Reinspect Steam/umu/game processes before committing filesystem/configuration
changes and before each removal. Running or uninspectable relevant processes
block mutation; UI disabling alone is not a safety boundary.

Installation sequence:

1. Confirm selected family/release and exact older-version cleanup candidates.
2. Download into private staging on the installation filesystem.
3. Verify published checksum before extraction.
4. Validate archive paths, links, entry types, and expansion limits. Reject
   traversal, escaping links, device nodes, and unexpected installation roots.
5. Validate extracted Proton installation; atomically activate without replacing
   an existing directory or following symlinks.
6. For GE, update umu to the newly installed version before deleting old GE.
7. Revalidate and remove only explicitly confirmed, older, same-family versions.

Preserve existing working versions until activation succeeds. If installation
succeeds but umu update fails, retain the installation and all older versions and
report partial success. Never remove the umu-selected version. Cleanup failure
does not undo a successful installation/config update. Interrupted staging is
not an installed version and is reported without broad recursive cleanup.
Changing candidates/releases since confirmation requires a fresh confirmation.

Manual removal is a separate confirmed operation against one revalidated local
installation. Unknown folders and current/newer versions are never inferred as
older cleanup candidates.

## umu selection

Manual selection changes only to a valid installed GE version. Sync latest GE
rescans installed versions, selects the newest valid GE, and writes its umu
path; it does not download another release. Installation handles upstream GE
updates separately.

Use `tomllib` to validate configuration, preserve unrelated text/settings, and
perform a narrowly targeted `[umu].proton` edit. Reparse proposed TOML and verify
unrelated parsed values are unchanged before an atomic replacement. Preserve
permissions; detect concurrent config changes rather than overwriting them.
Reject unsupported/ambiguous edits safely. Do not fabricate missing configuration.

After successful selection/config writes, refresh GE entries, current selector
value, and Installed umu marker together, including a newly discovered GE absent
from the old list. Failure leaves the previous committed selection unchanged.

## UI state and errors

Replace all sample versions, package states, warnings, outcomes, progress, and
locations. Show empty/unavailable states only when supported by actual results.
Updates owns release/install/cleanup results; Installed owns removal results;
Launcher owns package and umu results in their respective areas. Keep grouped
message columns. Shared footer shows actual current stage and progress, or idle.
Closing the popup does not kill an in-progress transaction; reopening displays
the shared service state. Prevent concurrent conflicting actions.

## Verification and delivery

Use temporary filesystem fixtures and fake release/process/package inputs for
Python tests. Cover release selection, version order, checksum failure, malicious
archives, symlinks, existing destinations, process blocking/rechecks, concurrent
operations/config changes, TOML preservation, selected-version removal, partial
success, and interrupted staging. Never perform destructive tests against real
installations or write the real umu config during automated verification.

Update focused QML/interface tests and the offscreen first-open/reopen viewport
regression for new file boundaries. Run changed-QML lint, relevant Python/Node
checks, and diff checks. Update `README.md` with configuration, commands,
limitations, and safety behavior. User performs graphical runtime testing unless
they explicitly request assistant-run smoke testing.

Keep work uncommitted. No changes to existing scripts, launch wrappers, runtime
installations, or unrelated battery code as part of implementation/testing.
