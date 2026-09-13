# Project Improvement Plan

_Last updated: 2026-09-13_

## Status
- Git repository: already initialized locally (`.git/` present)
- Current branch detected during scan: `main`
- Note: existing uncommitted changes were present before Phase 1 work began

## Goals
1. Improve correctness and consistency in app state and preferences
2. Reduce lifecycle bugs in always-on services
3. Prepare the codebase for deeper Phase 2 refactors
4. Keep changes small, testable, and safe

## Phase 1 — Correctness & Cleanup

### Planned items
- [x] Confirm local Git repo exists before changes
- [x] Make menu bar setup idempotent
- [x] Prevent duplicate system stats monitoring timers
- [x] Align settings defaults for `showMenuBarIcon`
- [x] Fix incorrect app test expectation in `StorageViewModelTests`
- [x] Validate edited files
- [x] Run focused build/tests

### Notes
- This phase avoids large architecture changes and Xcode project restructuring.
- Preference persistence unification is intentionally deferred to Phase 2 because it touches app/core boundaries.

## Phase 2 — Preference & Configuration Unification
- [x] Replace scattered `UserDefaults` key usage with one shared persistence path
- [x] Route cleanup debug/simulation mode through configuration instead of direct global reads
- [x] Align `ApplicationCoordinator`, `PreferencesViewModel`, and core `PreferencesStore`
- [x] Add migration handling for legacy preference keys if needed

## Phase 3 — Storage Analysis Refactor
- [x] Split `StorageViewModel` responsibilities
- [x] Extract filesystem sizing/detail loading into dedicated services
- [x] Improve cancellation semantics for storage analysis vs cleanup scans
- [x] Reduce repeated directory walks and add session caching

## Phase 4 — Categorization & Core Logic Cleanup
- [x] Deduplicate cleanup categorization logic between scanner and analyzer
- [x] Make thresholds configurable from preferences
- [x] Expand tests around categorization edge cases

## Phase 5 — Logging, UX, and Docs
- [x] Replace `print` debugging with structured logging
- [ ] Review Full Disk Access detection flow
- [x] Implement or disable `Launch at login` until wired up
- [ ] Refresh `README.md`, `STRUCTURE.md`, and implementation docs

## Phase 1 Work Log
- 2026-09-13: Verified repository already initialized; began first implementation batch.
- 2026-09-13: Completed first Phase 1 fixes in `MenuBarManager`, `SystemStatsService`, `PreferencesViewModel`, and `StorageViewModelTests`.
- 2026-09-13: `MacStorageCleanupApp` app build succeeded locally via Xcode command-line build.
- 2026-09-13: Attempted automated tests, but the Xcode schemes are not configured for a test action and the Swift package test suite currently has pre-existing compile failures unrelated to this batch.
- 2026-09-13: Unified shared preferences through `PreferencesStore`, migrated legacy standalone keys, and routed cleanup debug mode through the shared configuration path.
- 2026-09-13: Centralized cleanup categorization rules, made size/age thresholds preference-driven, and preserved safe old-file exclusions inside `StorageAnalyzer`.
- 2026-09-13: Replaced remaining runtime `print` debugging in app/core services with structured logging and disabled the not-yet-wired `Launch at login` control in Preferences.
- 2026-09-13: Fixed the Swift package test target import configuration, cleaned up package target source declarations, and re-ran the full Swift package test suite successfully (`213` tests passing).
- 2026-09-13: Rebuilt the `MacStorageCleanupApp` Xcode scheme successfully after the preference, logging, and warning cleanup changes.
- 2026-09-13: Completed the Phase 3 storage analysis refactor by extracting dedicated storage inspection/analysis services, separating analysis cancellation from cleanup scans, and adding session-scoped caching for repeated directory sizing and detail loading.
- 2026-09-13: Completed Phase 4 by adding focused shared categorization edge-case tests covering case-insensitive browser cache detection, Application Support temporary paths, deterministic age thresholds, and protected/app-bundle old-file exclusions.
