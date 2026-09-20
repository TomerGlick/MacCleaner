# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.4.0] - 2026-09-20

### Changed
- Bundle identifier is now `com.tomerglick.MacStorageCleanup`. It was
  `com.example.MacStorageCleanup`, a placeholder domain reserved for documentation and
  owned by nobody
- Signing team aligned with the Developer ID certificate used for release builds

### Added
- Preferences are migrated from the previous bundle identifier's domain on first launch.
  `UserDefaults.standard` is keyed by bundle identifier, so the rename moves the whole
  preferences domain; without this every setting would silently return to its default
- Releases are signed with a Developer ID certificate and notarized by Apple, so the app
  opens without a Gatekeeper warning. Earlier releases were signed with an Apple
  Development identity and required right-click → Open

### Note
- macOS ties Full Disk Access to the bundle identifier and signature, so this release must
  be granted Full Disk Access again in System Settings › Privacy & Security

## [1.3.0] - 2026-09-20

### Added
- Per-version rows for multi-version toolchains, so accumulation is visible instead of being
  hidden behind one total per tool
- Android SDK scanning: NDK, system images, build tools, platforms, sources and extras,
  removed with `sdkmanager --uninstall`
- Android emulator (AVD) scanning, with display names from `<name>.ini`, removed with
  `avdmanager delete avd`
- Gradle breakdown: `caches/<version>` per version, wrapper distributions, dependency jars,
  build cache, toolchain JDKs, and always-safe scratch directories
- Kotlin/Native (`~/.konan`) scanning, one row per prebuilt compiler version
- Simulator runtime volumes sized with `statfs`, removed with `simctl runtime delete`
- Device Support grouped by device model, keeping the newest build per model
- Generic Electron/Chromium cache sweep across every app under Application Support and each
  browser profile, always scanned regardless of the developer cache toggle
- Android Studio `DerivedData` reported separately from the opaque Google cache blob
- Xcode Coding Assistant, build Products, duplicate `Xcode*.app` installs and Command Line
  Tools detection
- APFS local snapshot reporting via `tmutil`
- Opt-in per-project build artifact scan over folders chosen in Preferences, guarded by a
  required project marker and never following symlinks out of the chosen root
- `ProjectReferenceIndex`: projects are searched for `ndkVersion`, `buildToolsVersion`,
  `ndk.dir`, `gradle-wrapper.properties` and CI variables, so a pinned version is never
  offered for deletion and the files pinning it are shown
- Traffic-light risk indicator on every row and group heading, with a legend above the list
- Group-level checkbox with a mixed state, per-group selected totals
- Tool-owned reclaim commands (`simctl delete`, `simctl runtime delete`,
  `avdmanager delete avd`, `sdkmanager --uninstall`, `brew cleanup`) in preference to `rm`
- `MacStorageCleanupAppTests` target, so the app-layer tests actually run

### Changed
- Sizing reports allocated size rather than logical size, so APFS clones and sparse
  simulator images no longer overstate reclaimable space
- Hidden entries are included when sizing; previously everything inside `~/.gradle` and every
  dotfile in a cache was invisible
- Mount points are measured with `statfs` instead of a recursive walk that took minutes
- Unreadable paths report "permission needed" instead of silently reporting 0 bytes
- Measurements have a time budget and report a partial result rather than stalling a scan
- Developer and AI agent cache toggles are persisted and honoured by the cleanup page, not
  just the scan page
- `ProjectReferenceIndex` is skipped entirely when no versioned toolchain is installed

### Fixed
- Mounted simulator runtime volumes were counted twice — once as a volume and once as the
  downloaded asset backing it — overstating reclaimable space
- `~/Library/Application Support/Code/CachedData` was claimed by both the developer and app
  cache sweeps and reported twice
- `xcuserdata` was marked always-safe and pre-selected, but holds breakpoints and
  user-scoped schemes carrying env vars, launch arguments and test config, which do not
  regenerate and are gitignored
- Android SDK `sources` was marked always-safe despite requiring an `sdkmanager` download
- `CleanupProgressViewModelTests.testProgressUpdates` asserted against files that were never
  created on disk

## [1.2.0] - 2026-09-16

### Added
- Duplicate file finder across Documents, Desktop, Downloads, and Movies
- Downloads folder cleanup grouped by file type (documents, images, archives, installers)
- Log file cleanup category
- Vendor grouping for cache candidates (Google, Apple, JetBrains, Microsoft, Adobe, Mozilla,
  Dropbox, Slack, Zoom, Spotify) with per-group item counts and totals
- "Other Caches" bucket so small unrecognized cache folders no longer flood the candidate list
- `CleanupCategorizer` as the single shared source of categorization rules for the scanner and analyzer
- `StorageAnalysisService` and `StorageInspectionService` split out of `StorageViewModel`
- Session-scoped caching for directory sizing and detail loading
- Categorization edge-case test suite (`CleanupCategorizerTests`)

### Changed
- All settings now persist through a single `PreferencesStore`, with migration of legacy
  standalone `UserDefaults` keys
- Cleanup debug/simulation mode routed through shared configuration instead of direct global reads
- Large/old file thresholds are read from preferences by both the scanner and the analyzer
- Full Disk Access detection consolidated into one shared probe used by app startup and the
  permission re-check screen; inconclusive probes no longer block startup
- Structured logging replaces `print` debugging across app and core services
- Storage analysis cancellation is now independent of cleanup scan cancellation
- Nested candidate paths are suppressed so a tool's cache is not listed under two groups

### Fixed
- Menu bar setup is idempotent; duplicate system stats monitoring timers no longer accumulate
- `showMenuBarIcon` default aligned between app settings and preferences store
- Swift package test target import configuration

### Disabled
- "Launch at login" control is disabled until the underlying behavior is wired up

## [1.0.0] - 2026-02-26

### Added
- Initial release
- System and application cache cleanup
- Browser cache cleanup (Safari, Chrome, Firefox, Edge, Brave)
- Developer tool cache cleanup (Xcode, CocoaPods, npm, Gradle, etc.)
- AI agent cache cleanup (ChatGPT, Claude, Cursor, etc.)
- Temporary files cleanup
- Large files finder (>100MB)
- Old files finder (>1 year)
- Storage visualization and analysis
- File browser with size information
- Backup and restore functionality
- Scheduled cleanup (daily, weekly, monthly)
- Debug mode for safe testing
- Safe list protection for critical system files
- Move to Trash option (recoverable deletion)
- Customizable thresholds for large and old files
- Application uninstaller
- Real-time scan progress
- Cleanup preview before deletion
- About page with app information

### Security
- App sandbox disabled for file system access
- Safe list manager protects critical system files
- All deletions are validated before execution

## [Unreleased]

### Planned
- Duplicate file finder
- Download folder cleanup
- Smart recommendations based on usage patterns
- Export cleanup reports
- Menu bar app mode
- Localization support
- Dark mode optimization
- Custom cleanup rules
- Cloud storage integration
