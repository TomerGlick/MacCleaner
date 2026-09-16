# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
