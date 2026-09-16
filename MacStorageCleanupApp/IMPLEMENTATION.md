# Mac Storage Cleanup Implementation Summary

_Last updated: 2026-09-13_

## Overview

This document summarizes the current app implementation after completing roadmap phases 1 through 4 and the remaining Phase 5 polish.

## Completed implementation milestones

## Phase 1: correctness and lifecycle cleanup

- Made `MenuBarManager.setupMenuBar()` idempotent.
- Prevented duplicate stats timers in `SystemStatsService`.
- Aligned `showMenuBarIcon` default handling.
- Corrected app test expectation in `StorageViewModelTests`.

## Phase 2: shared preferences and configuration

- Unified app/core preference persistence through `PreferencesStore`.
- Added migration for legacy preference keys.
- Routed cleanup debug behavior through shared preferences.
- Updated `ApplicationCoordinator` and `PreferencesViewModel` to use shared paths.

## Phase 3: storage analysis refactor

- Reduced `StorageViewModel` responsibility by extracting services.
- Added `StorageAnalysisService` for category summaries and details.
- Added actor-backed `StorageInspectionService` for filesystem inspection.
- Added session-scoped caches to reduce repeated directory walks.
- Separated cancellation semantics for storage analysis vs cleanup scanning.

## Phase 4: categorization and core logic cleanup

- Centralized categorization rules in `CleanupCategorizer`.
- Switched scanner/analyzer thresholds to preference-driven configuration.
- Added focused `CleanupCategorizerTests` edge-case coverage.

## Phase 5: UX and documentation follow-through

- Replaced runtime `print` debugging with structured logging in active paths.
- Kept launch-at-login UI disabled until system integration is wired.
- Reviewed Full Disk Access detection and moved checks to shared detector logic.
- Refreshed top-level and app architecture documentation.

## Full Disk Access flow

`FullDiskAccessDetector` is used by both app startup and permission re-check actions.

Probe order:
1. `~/Library/Safari`
2. `~/Library/Mail`
3. `~/Library/Messages`

Behavior:
- If a protected directory is readable, access is treated as granted.
- If access is explicitly denied with no-permission error, access is denied.
- If no probe directories are present, status is treated as undetermined and startup is allowed.

## Current module boundaries

- `MacStorageCleanupCore` (Swift package)
  - scanning, categorization, cleanup execution, backups, safe-list handling
- `MacStorageCleanupApp` (SwiftUI shell)
  - screens, view models, app services, system integrations

## Validation baseline

Recent validation performed in this workspace:

- `xcodebuild clean build -project MacStorageCleanupApp.xcodeproj -scheme MacStorageCleanupApp -destination 'platform=macOS' | cat`
- `swift test --filter CleanupCategorizerTests | cat` (from `MacStorageCleanup/`)
- `swift test | cat` (from `MacStorageCleanup/`)

At the time of these validations, app build and package tests were passing.
