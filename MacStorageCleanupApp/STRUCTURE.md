# Mac Storage Cleanup App Structure

## Directory layout

```text
MacStorageCleanupApp/
|-- MacStorageCleanupApp.swift
|-- Info.plist
|-- MacStorageCleanupApp.entitlements
|-- Assets.xcassets/
|-- Models/
|   |-- CleanupCandidateData.swift
|   |-- StorageCategoryData.swift
|   `-- StorageItemData.swift
|-- Services/
|   |-- ApplicationCoordinator.swift
|   |-- LoggingService.swift
|   |-- MenuBarManager.swift
|   |-- NotificationService.swift
|   |-- PreferencesService.swift
|   |-- StorageAnalysisService.swift
|   |-- StorageInspectionService.swift
|   `-- SystemStatsService.swift
|-- ViewModels/
|   |-- StorageViewModel.swift
|   |-- CleanupCandidatesViewModel.swift
|   |-- CleanupPreviewViewModel.swift
|   |-- CleanupProgressViewModel.swift
|   |-- CleanupResultsViewModel.swift
|   |-- PreferencesViewModel.swift
|   |-- FileBrowserViewModel.swift
|   |-- ApplicationsViewModel.swift
|   |-- ApplicationUninstallViewModel.swift
|   `-- BackupManagementViewModel.swift
|-- Views/
|   |-- MainWindowView.swift
|   |-- PermissionRequestView.swift
|   |-- PreferencesView.swift
|   |-- PreferencesWindow.swift
|   |-- StorageHeaderView.swift
|   |-- StorageVisualizationView.swift
|   |-- CategoryBreakdownView.swift
|   |-- CategoryDetailView.swift
|   |-- ScanView.swift
|   |-- CleanupCandidatesView.swift
|   |-- CleanupPreviewView.swift
|   |-- CleanupProgressView.swift
|   |-- CleanupResultsView.swift
|   |-- FileBrowserView.swift
|   |-- ApplicationsListView.swift
|   |-- ApplicationUninstallView.swift
|   |-- BackupManagementView.swift
|   `-- StatusMenuView.swift
`-- Tests/
    |-- StorageViewModelTests.swift
    |-- CleanupProgressViewModelTests.swift
    |-- CleanupResultsViewModelTests.swift
    `-- CleanupCandidatesViewModelTests.swift
```

## Runtime flow

1. `MacStorageCleanupApp` evaluates Full Disk Access via `FullDiskAccessDetector`.
2. If access is denied, `PermissionRequestView` is shown.
3. If access is available (or check is inconclusive), `MainWindowView` is shown.
4. `StorageViewModel` orchestrates storage loading and cleanup scan actions.
5. `StorageAnalysisService` computes category totals/details.
6. `StorageInspectionService` performs directory walks with per-session caching.
7. `ApplicationCoordinator` bridges UI actions to `MacStorageCleanupCore` operations.

## Responsibilities

- `Services/`
  - App-level integrations and cross-cutting concerns (logging, notifications, menu bar, preferences, coordination).
- `ViewModels/`
  - UI state and task orchestration.
  - Cancellation boundaries for storage analysis and scan flows.
- `Views/`
  - Presentation and user interaction.
- `Models/`
  - App-facing data structs for storage and cleanup screens.

## Notes

- Launch-at-login UI is currently disabled until login item integration is implemented.
- Storage analysis and cleanup scans are intentionally cancellable through separate view model pathways.
