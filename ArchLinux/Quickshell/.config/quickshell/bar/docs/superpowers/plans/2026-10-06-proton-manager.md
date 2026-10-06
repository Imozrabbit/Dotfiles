# Proton Manager Implementation Plan

Execution status: Tasks 1–7 implemented and audited locally; independent review
findings fixed with regressions. Detailed evidence/rulings: `../proton-progress.md`.
Final graphical testing remains manual; no real installation mutations tested.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans for inline execution or superpowers:subagent-driven-development if the user chooses delegation. Execute task-by-task; checkboxes track progress.

**Goal:** Replace the accepted visual preview with safe, on-demand GE/CachyOS management and umu selection, preserving the UI.

**Architecture:** One shared QML service runs a Python helper and consumes validated JSON events. Module-local UI components present its state; Python modules separate release/network work from filesystem/TOML safety. Transactions preserve working installations and fail closed at destructive boundaries.

**Tech Stack:** Quickshell, QtQuick/Controls/Layouts, QML JavaScript, Python 3.11+ standard library, existing `pacman`/`checkupdates`, Node, and `qml6` offscreen verification. No new runtime dependencies.

**Spec:** `docs/superpowers/specs/2026-10-06-proton-manager-design.md`

## Global Constraints

- All source work remains inside selected `bar/` root. Previously authorized external scripts are read-only references; do not modify them.
- Support GE-Proton x86_64 and CachyOS Proton SLR x86_64_v3 only.
- Default host compatibility tools: `/home/Steam/.local/share/Steam/compatibilitytools.d`.
- Default host umu config: `/home/Steam/.config/umu-launcher/config.toml`.
- Default sandbox-visible compatibility tools: `/home/Zrabbit/.local/share/Steam/compatibilitytools.d`.
- Keep `modules.protonManager` disabled by default; service and popup are shared, not per-output.
- No Activity tab, continuous upstream polling, package installation, shell interpolation, or new dependencies.
- Preserve accepted appearance, fonts, icon placement/open color, confirmation, selector, and footer.
- Preserve unknown folders, umu-selected versions, working installations, and unrelated TOML settings.
- Block mutations when Steam/umu/games run or relevant process state cannot be inspected; recheck before commits/removals.
- Never run destructive tests on real installations or write the real umu config in automated verification.
- Keep work uncommitted. This overrides skill defaults requesting frequent commits.

## Review Focus

1. A process starts after confirmation: activation/config writes/removal must recheck and stop (Task 4).
2. Config or installation changes after confirmation: refuse stale intent, retain intervening edits/folders (Tasks 2 and 4).
3. Published archive contains legitimate relative symlinks: accept contained links, reject escaping links and link-assisted traversal (Task 2).
4. Release naming evolves or an API response selects another architecture: match exact supported assets, reject ambiguity rather than guessing (Task 3).
5. Helper exits without a valid terminal event, or sends malformed/stale events: leave finite unavailable/error state, never fake success or retain permanent busy state (Task 5).

## File Map

Create under `proton/`:

- `backend.py`: CLI, local inspection, process/package checks, confirmation preparation, transaction orchestration.
- `releases.py`: official release lookup, asset/checksum selection, bounded network requests and verified downloads.
- `storage.py`: installation validation, locking, safe extraction/activation/removal, atomic targeted TOML editing.
- `State.js`: event validation and pure state updates, independently testable with Node.
- `Service.qml`: one request/process lifecycle and shared state.
- `Palette.qml`: module-local colors grouped/named by purpose, using bar theme for fonts/dim text.
- `Action.qml`: shared existing button appearance/interaction.
- `Messages.qml`: grouped severity-colored message presentation.
- `Manager.qml`: window/card composition, local tab/confirmation/expanded-entry state.
- `UpdatesTab.qml`, `InstalledTab.qml`, `LauncherTab.qml`: one tab each.
- `GeSelector.qml`: existing connected wheel dropdown and accessible selection behavior.
- `Confirmation.qml`: existing in-card confirmation overlay.

Modify `Config.qml`, `core/BarConfig.js`, `shell.qml`, `BarWindow.qml`,
`widgets/Workspaces.qml`, `README.md`, existing focused Proton tests.
Retire `ProtonManagerPreview.qml` only after new module is wired and verified.
Do not modify unrelated services, editor configuration, or existing scripts.

Tests: `tests/test_proton_storage.py`, `tests/test_proton_releases.py`,
`tests/test_proton_backend.py`, `tests/proton-state-checks.mjs`, existing
`tests/proton-*-checks.mjs`, and existing bar configuration checks.

## Shared Interfaces

Python configuration dictionary has exactly `compatibilityToolsDir`, `umuConfigPath`,
and `sandboxCompatibilityToolsDir`, each an absolute, nonempty path without NUL.
QML global configuration key is `protonManager`; no per-monitor path overrides.

Helper CLI: `python3 <shellPath>/proton/backend.py --request <JSON>`.
Request: `{id, action, config, payload}`; `id` is a bounded unique string.
Actions: `inspect`, `refresh`, `prepareInstall`, `prepareRemove`, `install`,
`remove`, `selectGe`, `syncGe`. Helper independently validates every request.

Events have `{id, type, data}`. Types: `snapshot`, `confirmation`, `progress`,
`result`. Exactly one terminal `result` per request, even on handled failure.
Result: `{status, area, messages, snapshot}` where status is `success`,
`partial`, `blocked`, or `error`; area is `updates`, `installed`, `package`,
or `selection`. Message: `{severity, text}`, severity `info|success|warning|error`.
Progress: `{stage, fraction, downloadedBytes, totalBytes}`; unknown fraction
is `null`, otherwise a finite number in `[0,1]`. Bound message/event sizes.

Snapshot: `{installations, geVersions, currentGeVersion, releases, package,
blockers, locations, messages}`. Missing selection is `null`, not newest GE.
Installation: `{name, family, version, path, umuSelected, identity}`;
family is `ge|cachyos`. `identity` represents validated directory identity.
Release: `{family, tag, name, version, archiveName, archiveUrl, checksumUrl}`.
Package: `{state, installedVersion, availableVersion, messages}`;
state is `upToDate|updateAvailable|notInstalled|unavailable`.

Confirmation: `{action, target, cleanupCandidates, fingerprint}`. The helper
constructs fingerprints from validated release, installation identities, and
umu configuration identity/content digest. Mutations reconstruct and compare
the descriptor; request-supplied names/URLs alone never authorize deletion.
Changed release/candidate/config state requires fresh confirmation.

Service interface: required `config`; readonly `busy`, `snapshot`,
`confirmation`, `progress`, `messages`; methods `inspect()`, `refresh()`,
`prepareInstall(family)`, `prepareRemove(name)`, `confirm(descriptor)`,
`selectGe(name)`, `syncGe()`. Only one helper request runs at a time.
Service result messages are retained separately by area; popup visibility is
not operation lifetime. Config changes during an operation affect subsequent
requests, not the running request's captured config.

### Task 1: Validated configuration and local inventory

**Files:** `Config.qml`, `core/BarConfig.js`, `proton/backend.py`, `proton/storage.py`,
`tests/test_proton_backend.py`, existing config tests.

**Interfaces:** Produce `validate_config(value: dict) -> dict`,
`inspect_local(config: dict, proc_root: Path = Path('/proc')) -> dict`, and
`installation_identity(path: Path) -> dict`. Implement
`storage.validate_installation(path: Path) -> dict` here as the shared read-only
family/metadata/launcher validator; Task 2 adds mutations without replacing it.
Local inspection never invokes a release API or writes umu/installations.

- [ ] Write failing config tests for defaults/valid overrides and malformed/relative/NUL paths; reject monitor-specific path overrides. Existing monitor/module inheritance must remain unchanged.
- [ ] Write `test_inventory_filters_and_sorts`, using temporary GE-Proton11-7/11-6, supported old/new CachyOS naming, arbitrary folders, incomplete folders, and directory symlinks. Assert valid GE order `["GE-Proton11-7", "GE-Proton11-6"]`, exact family classification, no unknown cleanup eligibility.
- [ ] Run `python3 -m unittest discover -s tests -p 'test_proton_backend.py'`; observe missing-interface failures. Run existing configuration checks and observe new validation assertions fail.
- [ ] Implement configuration validation and read-only inspection. Compare numeric version/date components, not lexicographic names. Read umu with `tomllib`; map only exact sandbox-base/version paths to validated host GE. Report invalid/missing config rather than selecting a fallback.
- [ ] Add/run `test_unreadable_process_state_blocks`, `test_missing_selected_ge`, and `test_foreign_or_missing_package_is_not_current`. `pacman -Q` plus official repository evidence identifies package state; `checkupdates` exit 2 means successfully checked/no updates, other failures mean unavailable. Use a private temporary checkupdates database; no host sync database mutation.
- [ ] Run focused Python and configuration checks to green. All fixture reads/writes stay in temporary directories.

### Task 2: Safe filesystem and TOML primitives

**Files:** `proton/storage.py`, `tests/test_proton_storage.py`.

**Interfaces:** Consume Task 1's `validate_installation(path: Path) -> dict`;
produce `operation_lock(base: Path)` context manager, `extract_verified(archive: Path, staging: Path) -> Path`,
`activate(staged: Path, base: Path, name: str) -> Path`,
`write_umu_selection(config_path: Path, proton_path: str, expected_digest: str) -> None`,
and `remove_installation(base: Path, name: str, expected_identity: dict) -> None`.
Raise descriptive exceptions; orchestration maps them to area/status later.

- [ ] Write `test_extract_contained_links` and rejection cases for `../`, absolute paths, symlink-parent traversal, escaping symlink/hardlink, devices/FIFOs, duplicate conflicting members, and unexpected/multiple roots. Fixtures are tiny tar.gz/tar.xz archives.
- [ ] Write `test_atomic_activation_preserves_existing`, `test_lock_excludes_second_worker`, and `test_removal_rejects_changed_identity_or_symlink`.
- [ ] Write `test_toml_preserves_unrelated_values_and_comments`, including escaped/quoted path strings, quoted table keys, dotted keys, CRLF, missing `[umu].proton`, and malformed/ambiguous config. Assert preserved mode, concurrent-content change rejection, and old bytes retained on failure. Unsupported valid syntaxes must safely refuse editing, not corrupt them.
- [ ] Run `python3 -m unittest discover -s tests -p 'test_proton_storage.py'` and confirm expected failures.
- [ ] Implement with `tarfile`, `pathlib`, `fcntl`, `hashlib`, `tomllib`, and atomic filesystem rename. Stage under private hidden directory on destination filesystem. Cap archive members at 500000 and declared extracted bytes at 30 GiB; reject before extraction when exceeded. No ownership restoration or special/setuid permissions. Revalidate all paths before activation/removal.
- [ ] Implement narrowly targeted TOML edit, encoding path as valid TOML string; verify reparsed unrelated data is unchanged, compare expected file digest, preserve permissions, then atomically replace. Fail safely on symlinked configuration or unsupported edits. Do not create missing configuration automatically.
- [ ] Run storage tests to green, including `test_archive_limits` and no-replace destination behavior. Real installation paths must not occur in test filesystem operations.

### Task 3: Release discovery and verified download

**Files:** `proton/releases.py`, `tests/test_proton_releases.py`.

**Interfaces:** Produce `latest_release(family: str, fetch=None) -> dict`,
`select_release(family: str, metadata: dict) -> dict`, and
`download_verified(release: dict, destination: Path, emit_progress, fetch=None) -> Path`.
Default network implementation uses `urllib.request`; tests inject bounded fixture responses.

- [ ] Write `test_exact_build_selection` with GE x86_64/aarch64 and CachyOS slr x86_64/x86_64_v3/arm64 assets. Assert supported archive and same-stem `.sha512sum` only. Include CachyOS version-prefixed release names, not just the preview's date-only names.
- [ ] Write `test_missing_ambiguous_checksum_blocks`, `test_checksum_filename_mismatch`, `test_checksum_mismatch_leaves_no_verified_archive`, and HTTP rate-limit/timeout/malformed JSON cases.
- [ ] Run `python3 -m unittest discover -s tests -p 'test_proton_releases.py'`; verify failures before implementation.
- [ ] Implement official HTTPS latest-release lookup, strict bounded asset metadata, checksum parsing tied to archive filename, and streaming SHA-512 verification. Connect/read timeout 30 seconds; metadata limit 4 MiB, checksum limit 64 KiB, archive limit 4 GiB. Allow redirects only to HTTPS GitHub asset delivery hosts, not arbitrary/private endpoints.
- [ ] Emit download progress at most four times per second and once at completion; no whole-archive memory buffers. Use actual extracted root/metadata for installation name, not archive basename with architecture suffix.
- [ ] Run release tests to green; no test downloads real Proton archives.

### Task 4: Confirmed transactions and helper protocol

**Files:** `proton/backend.py`, `tests/test_proton_backend.py`.

**Interfaces:** Consume Tasks 1–3; produce `dispatch(request: dict, emit, dependencies=None) -> None`,
`prepare_confirmation(config: dict, action: str, target: str, snapshot: dict) -> dict`,
and `ensure_idle(proc_root: Path = Path('/proc')) -> None`.
Dependencies injection supplies fixture release lookup, package/process inspection,
and event sink without modifying production behavior or real paths.

- [ ] Write `test_prepare_does_not_mutate`, `test_install_activates_then_updates_umu_then_cleans`, `test_cachyos_does_not_change_umu`, and `test_select_and_sync_rescan_ge` against temporary installations/config.
- [ ] Write `test_stale_confirmation_refused`, `test_process_starts_before_commit`, `test_process_starts_before_each_removal`, `test_selected_ge_never_removed`, and `test_cleanup_never_deletes_newer_or_unknown`.
- [ ] Write `test_umu_failure_retains_new_and_old_ge`, `test_cleanup_failure_preserves_success`, and `test_interrupted_staging_not_inventory`. Assert concrete directory existence/config bytes plus terminal result status, not merely mocked call counts.
- [ ] Run backend tests and observe expected missing-transaction failures.
- [ ] Implement independently validated CLI/actions and newline-delimited events. Take lock before mutation, revalidate descriptor, stage/verify/extract, recheck process state, activate, recheck before config edit, update GE config, then recheck before each confirmed cleanup. Reject absent/malformed requests and unsupported actions. No broad directory deletion.
- [ ] Detect Steam, umu, Proton/Wine game processes through `/proc` executable/command evidence, handling normal process disappearance without failure and permission-denied inspection conservatively. Do not classify a grep or incidental text argument as a game.
- [ ] Implement `selectGe` and `syncGe` as config-only transactions with fresh inventory and process/config checks. Success snapshot includes refreshed GE entries, committed selector value, and umu marker; no downloads.
- [ ] Run all Python tests, including `test_protocol_has_one_terminal_result`, `test_lock_serializes_mutations`, and actual temporary-file contention/concurrent-edit cases.

### Task 5: Shared service and lifecycle

**Files:** `proton/State.js`, `proton/Service.qml`, `shell.qml`,
`tests/proton-state-checks.mjs`, `tests/proton-icon-checks.mjs`.

**Interfaces:** `State.js` produces `parseEvent(line, requestId) -> object|null`
and `applyEvent(state, event) -> object`; expose Service interface above.
Use `Quickshell.Io.Process` argv and `SplitParser` for streaming events; bound
diagnostic stderr. Python stdout is protocol only.

- [ ] Write failing Node tests for wrong request IDs, truncated/malformed JSON, nonfinite/out-of-range progress, malformed snapshots/messages, extra/duplicate terminal events, and valid success/partial snapshots.
- [ ] Run `node tests/proton-state-checks.mjs`; observe expected failures.
- [ ] Implement validator/reducer and service with immutable published snapshots. Request completion waits for terminal result plus process/stream completion; unexpected exit becomes actionable error. Preserve previously committed selection on failed selection and clear busy on every exit/error path.
- [ ] Add one shared service loader in `shell.qml`, active for `root.uses("protonManager") || service.busy`; no per-screen subprocesses. No timer polling. Opening inspects/refreshes on demand; Refresh invokes full checks. Busy requests are rejected, not stacked indefinitely.
- [ ] Keep active transactions alive if popup closes/module disables. Never use a generic watchdog that kills an installation/config transaction midway; Python network operations have bounded timeouts.
- [ ] Run Node state checks and lint Service/shell. Test invalid/abnormal helper exit via a small offscreen service fixture; busy becomes false and committed state is not falsified.

### Task 6: UI split, palette, and live state

**Files:** All listed `proton/*.qml` UI files, `BarWindow.qml`,
`widgets/Workspaces.qml`, `shell.qml`, existing `tests/proton-*-checks.mjs`.

**Interfaces:** Manager requires `theme` and `service`, exposes `barRevealed`,
and uses inherited `screen`/`visible`. Tabs require `theme`, `palette`, `service`;
their UI state stays local, service owns committed data and results.
GeSelector requires `versions` and `currentVersion`; emits `selectRequested(name)`.
Confirmation requires descriptor and emits confirm/cancel; confirm delegates
to Service. Messages consumes an array of validated severity/text objects.

- [ ] Capture current named geometry/style values in focused regression checks. Update tests to follow new component paths, but keep first-open/reopen geometry and no-anchor-warning assertions. Add fixtures for no installations, unavailable releases/package/config, busy, real selection, and partial success.
- [ ] Run relevant Node/offscreen tests and observe failures for absent new components/live bindings.
- [ ] Extract components without redesign. Name every module literal color in Palette groups: surfaces/borders/text/semantic/interaction. Keep numeric margins, connected dropdown shape, centered texts/independent icons, wheel sizes, fonts, and monitor anchoring unchanged.
- [ ] Move tabs/viewport/action row as directly nested siblings in Manager's tab card. Update offscreen fixture to load real split components with fixture theme/service; do not flatten into a different layout for testing.
- [ ] Replace placeholders with snapshots/messages. Updates selection controls prepare install confirmation; Installed trash prepares removal confirmation. Confirmation executes only validated descriptor. GE menu calls service on explicit committed selection, not initial delegate/Tumbler setup; scrolling alone must not generate repeated config writes. Sync calls `syncGe()`.
- [ ] Wire header Refresh, version sorting/current selection/umu marker, actual locations, package state, message groups, and shared progress/idle footer. Handle zero GE choices and absent selection without indexing `-1` into the wheel.
- [ ] Rename preview wiring to `protonManagerScreen`/`openProtonManager`, preserve module icon/open/hover behavior, remove preview tooltip copy. Retain IPC `bar previewProton` as a compatibility alias opening the functional manager; also expose `bar protonManager`.
- [ ] Remove old preview file after wiring/tests pass. Run focused Node/offscreen checks and lint every changed QML file.

### Task 7: Documentation and complete verification

**Files:** `README.md`, plan checkboxes, focused tests as needed.

- [ ] Document module paths/defaults, Python version/optional package commands, supported builds, on-demand refresh, Sync-installed semantics, safety restrictions, partial outcomes, and IPC alias. Remove visual-preview-only documentation.
- [ ] Run `python3 -m unittest discover -s tests -p 'test_proton_*.py'` and `for test in tests/proton-*-checks.mjs; do node "$test" || exit; done`; expected all PASS. Run existing bar configuration checks and report any unrelated failures rather than silently omitting them.
- [ ] Run `/usr/lib/qt6/bin/qmllint -I /usr/lib/qt6/qml -I <current Quickshell VFS import path> <each changed QML file>`; expected exit 0. Discover import path from current runtime/editor context, not an assumed stale VFS path.
- [ ] Run `git diff --check -- <explicit changed paths>` and review diff scope. Confirm no edits to Battery, existing gaming scripts, external configuration, or real installations.
- [ ] Ask whether user will perform final graphical smoke test or wants assistant to run it; preserve manual preference. If assistant requested, launch only selected `bar/` config by absolute path. Read-only checks first; never confirm real install/removal/config writes as smoke testing without separate explicit authorization.
- [ ] Report completed behavior, fresh verification evidence, and unresolved limitations; do not commit/push or claim live destructive operations were tested.

## Plan Self-Review

- Spec coverage: configuration/inventory (Task 1); archive/TOML safety (2);
  checksum/upstream behavior (3); process/confirmation/partial success (4);
  service lifecycle/events (5); accepted UI and named colors (6); docs/testing (7).
- Interface names and request/event shapes are shared above and referenced consistently.
- Review Focus conditions each have explicit runnable checks in owning tasks.
- Scope remains one optional module. Dependencies are standard library/existing tools.
- No commits, real-path destructive tests, continuous polling, or unrelated audits.
