# Execution ledger — plan: docs/superpowers/plans/2026-10-06-proton-manager.md

Root: ~/.config/quickshell/bar (resolved to existing Dotfiles bar directory).
Execution: native, sequential, self-audit each task, independent final audit.
No commits; no worktree; no real gaming/config mutations during testing.

## Pre-flight
- Tasks 1→2: inventory consumes storage validation; validation belongs to Task 1, mutation primitives to Task 2.
- Tasks 1–3→4: validated configuration/installations/releases feed confirmed transactions; interfaces consistent.
- Task 4→5: helper emits bounded NDJSON; service validates and waits for process/stream completion.
- Tasks 5→6: service owns committed data/results; UI owns transient navigation/confirmation only.
- Tasks 1–6→7: isolated fixture tests plus user graphical review; no real paths in test mutations.

Ruling: Keep ledger under selected root rather than skill's repository-root workspace/scripts — user explicitly limits access/work to bar/ and wants no commits; cost: task bookkeeping is manual.
Ruling: Existing proton-ge-menu-checks.mjs fails with SyntaxError from indentation-sensitive extraction — migrate this test during Task 6, do not alter accepted UI to satisfy a brittle parser; cost: baseline suite is not entirely green until migration.

## Tasks
- [x] 1: configuration/inventory
- [x] 2: storage/TOML safety
- [x] 3: release/checksum/download
- [x] 4: confirmed transactions/protocol
- [x] 5: shared service
- [x] 6: split UI/palette/live wiring
- [x] 7: dummy demo/documentation/full verification

## Audits
Task 1: complete — Python inventory/config/process checks 6/6; bar config Node checks pass. Audit: read-only inspection, numeric family sorting, unknown/incomplete/symlink installations excluded, missing selection reported, paths validated globally rather than per monitor.
Task 2: complete — combined Python 17/17. Audit: private extraction, archive limits/link validation, Linux no-replace atomic activation, nonblocking lock, identity-checked quarantine removal, parse/equivalence/digest-checked TOML replacement. No real gaming paths used.
Task 3: complete — combined Python 24/24. Audit: exact supported build/same-stem SHA-512, official release URLs/HTTPS redirect hosts, bounded responses/streaming archive, checksum tied to filename, corrupt downloads removed, throttled progress.
Task 4: complete — Python 40/40 before precision regression; post-audit identity regression RED→GREEN. Audit includes stale confirmation, GE update-before-cleanup, CachyOS config preservation, current GE/CachyOS removal blocking, concurrent locks, process starts after download and between removals, partial failures preserving installations.
Task 5: complete — state Node checks, isolated offscreen Quickshell lifecycle checks, Python 41/41, service/shell/config QML lint pass. Audit: no permanent busy on invalid output, terminal/stream/exit synchronization, duplicate/malformed validation, cached remote status preserved across local changes, busy service retained when module disabled.
Task 6: complete — all 23 bar Node checks pass, Python 41/41, all changed QML lint clean. Offscreen test exercises actual split UI first-open, Installed expansion, Launcher, empty GE and reopen; accepted refresh/insets/colors/wheel geometry retained. Old preview retired only after wiring and tests passed.
Ruling: Add shared Label.qml and Section.qml for styles reused across extracted components — avoids duplicate font/card declarations; cost: two small local style files.
Ruling: Name palette instance `colors` and explicitly qualify local Action/Label/Palette where QtQuick.Controls imports collide — Qt 6.11 provides inherited palette and native Action/Label/Palette types; cost: explicit local namespace at composition sites.
Ruling: Wheel navigation only previews; entry tap or Enter commits — repeated automatic TOML writes while scrolling/initializing are unsafe; cost: navigation requires explicit selection commit.
Ruling: Use streaming StdioCollector rather than SplitParser — SplitParser has no streamFinished signal; collector supplies actual stream/exit completion and streamed NDJSON, bounded accepted output; cost: retained output buffer (helper bounds events, accepted total 8 MiB).
Ruling: Exercise Process with isolated offscreen Quickshell rather than qml6 — Quickshell plugins are statically registered by its executable; all test cache/runtime paths are under temporary fixture root; cost: test needs installed Quickshell.
Ruling: Encode nanosecond mtime as string in installation identity — JS/QML numbers cannot losslessly carry it through confirmation; cost: consumers must treat identity timestamp as opaque text.
Ruling: Unsupported valid TOML spellings fail safely rather than adding a TOML writer dependency — preserves unrelated source text and parsed data; cost: user may need conventional [umu] / single-line proton syntax.
All per-task audits and independent final review completed.
Task 7: documented configuration/safety/IPC/dummy adapter. Manual graphical testing confirmed by user. Retained demo /tmp/opencode/proton-demo-p936xyba. Live metadata lookup passes for both supported upstream builds; no actual Proton archives downloaded or gaming configuration changed.
Final review: independent general reviewer; four concrete findings reproduced and fixed in one pass.
Final: fixed equivalent selected paths — test_equivalent_selected_paths_protected RED→GREEN.
Final: fixed replaced installed target confirmation — test_replaced_existing_target_invalidates_confirmation RED→GREEN.
Final: fixed executable/other-UID process evidence — executable, other UID and unavailable executable checks RED→GREEN.
Final: fixed uncertain official package status — foreign version check RED→GREEN; repository/name, foreign-package query and version consistency now required.
Final: Ruling: Check command lines across all UIDs, readable executable evidence across all UIDs, and fail closed on unreadable executable evidence for desktop/install/config owners — blindly blocking every unreadable root daemon makes normal unprivileged desktop use impossible; cost: an inaccessible unrelated-UID executable with disguised argv can evade detection.
Final: Ruling: Keep local ledger and uncommitted implementation rather than deleting bookkeeping — user requested no commits; cost: additional tracked documentation until user chooses cleanup.
Final: omitted live archive/install/game/compositor testing — deliberately reserved for user's manual dummy review and later real-PC testing; metadata selection verified read-only.
Final verification: `python3 -m unittest discover -s tests -p 'test_proton_*.py'` → 51/51; all `tests/*.mjs` → 23/23; changed QML including demo lint clean using current .qmlls.ini import path; explicit-path `git diff --check` clean. Work kept local/uncommitted per user instructions.
