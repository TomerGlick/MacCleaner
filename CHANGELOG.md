# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
