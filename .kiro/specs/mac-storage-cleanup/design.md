# Design Document: Mac Storage Cleanup Application

## Overview

The Mac Storage Cleanup application is a native macOS utility built using Swift and AppKit that helps users analyze disk usage and safely remove unnecessary files. The application follows a modular architecture with clear separation between the scanning engine, analysis logic, cleanup operations, and user interface.

The system operates in three main phases:
1. **Scanning Phase**: Traverses the file system to catalog files and their metadata
2. **Analysis Phase**: Categorizes files, identifies cleanup candidates, and calculates potential space savings
3. **Cleanup Phase**: Executes user-approved deletion operations with safety checks and optional backups

The application prioritizes safety through a comprehensive safe-list mechanism, user confirmation workflows, and optional backup creation before deletion.

## Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     User Interface Layer                     │
│  (SwiftUI/AppKit Views, View Models, User Interactions)     │
└────────────────────┬────────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────────┐
│                   Application Services                       │
│  (Coordination, State Management, User Preferences)         │
└────┬───────────┬──────────┬──────────┬─────────────────────┘
     │           │          │          │
┌────▼─────┐ ┌──▼────┐ ┌───▼────┐ ┌───▼──────────┐
│  File    │ │Storage│ │Cleanup │ │  Application │
│ Scanner  │ │Analyzer│ │Engine  │ │   Manager    │
└────┬─────┘ └──┬────┘ └───┬────┘ └───┬──────────┘
     │          │          │          │
┌────▼──────────▼──────────▼──────────▼────────────┐
│           Core Services Layer                     │
│  (Cache Manager, Backup Manager, Safe List)      │
└────────────────────┬──────────────────────────────┘
                     │
┌────────────────────▼──────────────────────────────┐
│              macOS System APIs                    │
│  (FileManager, NSWorkspace, Process Info)        │
└───────────────────────────────────────────────────┘
```

### Component Responsibilities

- **User Interface Layer**: Presents data to users, handles interactions, displays progress and confirmations
- **Application Services**: Coordinates operations between components, manages application state
- **File Scanner**: Traverses file system, collects file metadata, respects safe-list boundaries
- **Storage Analyzer**: Categorizes files, calculates sizes, identifies cleanup candidates
- **Cleanup Engine**: Executes deletion operations, enforces safety rules, manages transactions
- **Application Manager**: Handles application discovery and complete uninstallation
- **Cache Manager**: Identifies and manages cache files across system and applications
- **Backup Manager**: Creates and manages backups before deletion operations
- **Safe List**: Maintains and enforces protection rules for system-critical files

## Components and Interfaces

### File Scanner

**Purpose**: Traverse the file system and collect metadata about files for analysis.

**Interface**:
```swift
protocol FileScanner {
    func scan(paths: [URL], 
              categories: Set<CleanupCategory>, 
              progressHandler: @escaping (ScanProgress) -> Void) async throws -> ScanResult
    
    func cancelScan()
}

struct ScanProgress {
    let currentPath: String
    let filesScanned: Int
    let percentComplete: Double
}

struct ScanResult {
    let files: [FileMetadata]
    let errors: [ScanError]
    let duration: TimeInterval
}

struct FileMetadata {
    let url: URL
    let size: Int64
    let createdDate: Date
    let modifiedDate: Date
    let accessedDate: Date
    let fileType: FileType
    let isInUse: Bool
}
```

**Implementation Notes**:
- Uses `FileManager` for directory enumeration
- Implements batch processing (1000 files per batch) to manage memory
- Runs on background dispatch queue to maintain UI responsiveness
- Checks safe-list before adding files to results
- Uses `lstat` for file metadata to avoid following symlinks unnecessarily

### Storage Analyzer

**Purpose**: Analyze scanned files and categorize them for cleanup recommendations.

**Interface**:
```swift
protocol StorageAnalyzer {
    func analyze(scanResult: ScanResult) -> AnalysisResult
    func categorize(file: FileMetadata) -> Set<CleanupCategory>
    func calculateSavings(files: [FileMetadata]) -> Int64
}

struct AnalysisResult {
    let categorizedFiles: [CleanupCategory: [FileMetadata]]
    let totalSize: Int64
    let potentialSavings: Int64
    let duplicateGroups: [DuplicateGroup]
}

enum CleanupCategory: String, CaseIterable {
    case systemCaches
    case applicationCaches
    case browserCaches
    case temporaryFiles
    case largeFiles
    case oldFiles
    case logFiles
    case downloads
    case duplicates
}

struct DuplicateGroup {
    let hash: String
    let files: [FileMetadata]
    let totalSize: Int64
    let wastedSpace: Int64  // size * (count - 1)
}
```

**Implementation Notes**:
- Uses file extension, path patterns, and age to categorize files
- Computes SHA-256 hashes for duplicate detection (files > 1MB only)
- Caches analysis results to avoid recomputation
- Provides size calculations in bytes for precision

### Cleanup Engine

**Purpose**: Execute file deletion operations safely with validation and optional backup.

**Interface**:
```swift
protocol CleanupEngine {
    func cleanup(files: [FileMetadata], 
                 options: CleanupOptions,
                 progressHandler: @escaping (CleanupProgress) -> Void) async throws -> CleanupResult
    
    func validateCleanup(files: [FileMetadata]) -> ValidationResult
    func cancelCleanup()
}

struct CleanupOptions {
    let createBackup: Bool
    let moveToTrash: Bool  // if false, permanently delete
    let skipInUseFiles: Bool
}

struct CleanupProgress {
    let currentFile: String
    let filesProcessed: Int
    let totalFiles: Int
    let spaceFreed: Int64
}

struct CleanupResult {
    let filesRemoved: Int
    let spaceFreed: Int64
    let errors: [CleanupError]
    let backupLocation: URL?
}

struct ValidationResult {
    let isValid: Bool
    let blockedFiles: [FileMetadata]  // files on safe-list
    let warnings: [String]
}
```

**Implementation Notes**:
- Validates all files against safe-list before deletion
- Checks if files are in use using `lsof` or file handle attempts
- Uses `NSFileManager.trashItem` for trash operations
- Implements atomic operations with rollback on failure
- Creates backups before deletion if enabled

### Application Manager

**Purpose**: Manage application discovery and complete uninstallation including associated files.

**Interface**:
```swift
protocol ApplicationManager {
    func discoverApplications() async -> [Application]
    func findAssociatedFiles(for application: Application) async -> [FileMetadata]
    func uninstall(application: Application, 
                   removeAssociatedFiles: Bool) async throws -> UninstallResult
}

struct Application {
    let bundleURL: URL
    let name: String
    let version: String
    let bundleIdentifier: String
    let size: Int64
    let lastUsedDate: Date?
    let isRunning: Bool
}

struct UninstallResult {
    let applicationRemoved: Bool
    let associatedFilesRemoved: Int
    let totalSpaceFreed: Int64
    let errors: [UninstallError]
}
```

**Implementation Notes**:
- Searches `/Applications` and `~/Applications` for app bundles
- Uses `NSWorkspace` to get application metadata
- Finds associated files in:
  - `~/Library/Preferences/[bundle-id].plist`
  - `~/Library/Caches/[bundle-id]`
  - `~/Library/Application Support/[app-name]`
  - `~/Library/Logs/[app-name]`
- Checks if application is running using `NSRunningApplication`
- Prompts user to quit running applications before uninstall

### Cache Manager

**Purpose**: Identify and manage cache files across system and applications.

**Interface**:
```swift
protocol CacheManager {
    func findSystemCaches() async -> [FileMetadata]
    func findApplicationCaches() async -> [FileMetadata]
    func findBrowserCaches() async -> [BrowserCache]
    func clearCaches(caches: [FileMetadata]) async throws -> CleanupResult
}

struct BrowserCache {
    let browser: Browser
    let cacheLocation: URL
    let size: Int64
}

enum Browser: String, CaseIterable {
    case safari
    case chrome
    case firefox
    case edge
}
```

**Implementation Notes**:
- System caches: `~/Library/Caches/*`
- Application caches: app-specific cache directories
- Browser-specific cache locations:
  - Safari: `~/Library/Caches/com.apple.Safari`
  - Chrome: `~/Library/Caches/Google/Chrome`
  - Firefox: `~/Library/Caches/Firefox`
  - Edge: `~/Library/Caches/Microsoft Edge`
- Preserves directory structure when clearing caches
- Skips caches for currently running applications

### Backup Manager

**Purpose**: Create and manage backups of files before deletion.

**Interface**:
```swift
protocol BackupManager {
    func createBackup(files: [FileMetadata], 
                      destination: URL) async throws -> BackupResult
    
    func listBackups() -> [Backup]
    func restoreBackup(backup: Backup, 
                       destination: URL) async throws -> RestoreResult
    
    func deleteBackup(backup: Backup) throws
}

struct BackupResult {
    let backupURL: URL
    let filesBackedUp: Int
    let compressedSize: Int64
    let duration: TimeInterval
}

struct Backup {
    let id: UUID
    let createdDate: Date
    let fileCount: Int
    let originalSize: Int64
    let compressedSize: Int64
    let location: URL
}

struct RestoreResult {
    let filesRestored: Int
    let errors: [RestoreError]
}
```

**Implementation Notes**:
- Creates compressed archives using `Compression` framework
- Stores backups in `~/Library/Application Support/MacStorageCleanup/Backups`
- Includes manifest file with original paths and metadata
- Implements streaming compression for large file sets
- Automatically suggests cleanup of backups older than 30 days

### Safe List Manager

**Purpose**: Maintain and enforce protection rules for system-critical files and directories.

**Interface**:
```swift
protocol SafeListManager {
    func isProtected(url: URL) -> Bool
    func isProtected(path: String) -> Bool
    func updateSafeList(for macOSVersion: OperatingSystemVersion)
}

struct SafeList {
    let protectedPaths: Set<String>
    let protectedPatterns: [NSRegularExpression]
    let systemApplications: Set<String>
}
```

**Implementation Notes**:
- Protected system directories:
  - `/System`
  - `/Library/Apple`
  - `/usr` (except `/usr/local`)
  - `/bin`, `/sbin`
  - `/private/var/db`
  - `/private/var/root`
- Protected user directories:
  - `~/Library/Keychains`
  - `~/Library/Mail`
  - `~/Library/Messages`
  - `~/Library/Photos`
- System applications that cannot be uninstalled
- Updates safe-list based on macOS version
- Uses path prefix matching for efficient checking

## Data Models

### Core Data Models

```swift
// File representation with metadata
struct FileMetadata {
    let url: URL
    let size: Int64
    let createdDate: Date
    let modifiedDate: Date
    let accessedDate: Date
    let fileType: FileType
    let isInUse: Bool
    let permissions: FilePermissions
}

enum FileType {
    case cache
    case log
    case temporary
    case document
    case application
    case archive
    case media
    case other(String)
}

struct FilePermissions {
    let isReadable: Bool
    let isWritable: Bool
    let isDeletable: Bool
}

// Cleanup session tracking
struct CleanupSession {
    let id: UUID
    let startDate: Date
    let endDate: Date?
    let filesScanned: Int
    let filesRemoved: Int
    let spaceFreed: Int64
    let categories: Set<CleanupCategory>
    let backupCreated: Bool
}

// User preferences
struct UserPreferences {
    var enableScheduledCleanup: Bool
    var scheduledCleanupInterval: CleanupInterval
    var scheduledCategories: Set<CleanupCategory>
    var createBackupsByDefault: Bool
    var moveToTrashByDefault: Bool
    var oldFileThresholdDays: Int
    var largeFileSizeThresholdMB: Int
}

enum CleanupInterval {
    case daily
    case weekly
    case monthly
}

// Storage statistics
struct StorageStatistics {
    let totalCapacity: Int64
    let usedSpace: Int64
    let availableSpace: Int64
    let categoryBreakdown: [StorageCategory: Int64]
}

enum StorageCategory {
    case applications
    case documents
    case system
    case caches
    case other
}
```

### Error Types

```swift
enum ScanError: Error {
    case permissionDenied(path: String)
    case pathNotFound(path: String)
    case cancelled
    case unknown(Error)
}

enum CleanupError: Error {
    case fileProtected(path: String)
    case fileInUse(path: String)
    case permissionDenied(path: String)
    case fileNotFound(path: String)
    case cancelled
    case backupFailed(Error)
    case unknown(Error)
}

enum UninstallError: Error {
    case applicationRunning(name: String)
    case applicationNotFound(path: String)
    case permissionDenied
    case partialUninstall(removedFiles: Int, failedFiles: Int)
    case unknown(Error)
}

enum RestoreError: Error {
    case backupNotFound
    case backupCorrupted
    case destinationNotWritable
    case insufficientSpace
    case unknown(Error)
}
```


## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system—essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: File Categorization Completeness

*For any* file metadata with valid path and extension, the categorization function should assign it to at least one valid cleanup category based on its path patterns, extension, or attributes.

**Validates: Requirements 1.2**

### Property 2: Path-Based Category Detection

*For any* file in a known cache directory (~/Library/Caches/*, browser cache paths), temporary directory (/tmp, /var/tmp, */tmp), or log directory (/var/log, ~/Library/Logs/*), the scanner should correctly identify it as belonging to the corresponding category (cache, temporary, or log).

**Validates: Requirements 2.1, 2.2, 2.3, 3.1, 13.1**

### Property 3: Extension-Based Temporary File Detection

*For any* file with extension .tmp, .temp, or .cache, the scanner should categorize it as a temporary file regardless of its location.

**Validates: Requirements 3.2**

### Property 4: Permission Error Resilience

*For any* scan operation that encounters permission-denied errors on some directories, the scanner should continue processing remaining accessible directories and include the errors in the scan result.

**Validates: Requirements 1.3**

### Property 5: Category Size Aggregation

*For any* set of categorized files, the sum of file sizes within each category should equal the total size reported for that category by the storage analyzer.

**Validates: Requirements 1.4**

### Property 6: Selective Cache Deletion

*For any* subset of cache files selected for cleanup, after the cleanup operation completes, only the selected files should be removed and the parent cache directories should still exist.

**Validates: Requirements 2.5**

### Property 7: In-Use File Protection

*For any* file that is currently open by a running process, cleanup operations should skip that file and include it in the error report rather than attempting deletion.

**Validates: Requirements 2.6, 3.5**

### Property 8: Age-Based File Filtering

*For any* age threshold T (in days) and collection of files, the age filter should include only files where (current_date - last_access_date) > T days, and exclude all files accessed more recently.

**Validates: Requirements 3.3, 5.1, 14.2**

### Property 9: Size-Based File Filtering

*For any* size threshold S (in bytes) and collection of files, the size filter should include only files where file_size >= S and exclude all smaller files.

**Validates: Requirements 4.1, 12.5**

### Property 10: Sort Order Correctness

*For any* list of files sorted by size in descending order, each file should have size greater than or equal to the next file in the list.

**Validates: Requirements 4.3**

### Property 11: Filter Composition

*For any* collection of files and combination of filters (file type, age threshold), the filtered result should contain only files that satisfy all applied filter criteria.

**Validates: Requirements 4.4, 14.4**

### Property 12: Trash Movement vs Permanent Deletion

*For any* cleanup operation on large files, old files, or downloads with default settings, files should be moved to the system Trash rather than permanently deleted.

**Validates: Requirements 4.5, 5.5, 14.5**

### Property 13: System File Exclusion

*For any* file identified as a system file or application bundle, it should never appear in the old files cleanup candidates list regardless of its last access date.

**Validates: Requirements 5.2**

### Property 14: Age Threshold Bounds Enforcement

*For any* user-specified age threshold, the system should clamp the value to the range [30, 1095] days and use the clamped value for filtering.

**Validates: Requirements 5.4**

### Property 15: Application Bundle Discovery

*For any* .app bundle located in /Applications or ~/Applications directories, the application manager should discover and list it in the applications inventory.

**Validates: Requirements 6.1**

### Property 16: Associated Files Discovery

*For any* application with bundle identifier B, the application manager should identify associated files in all standard locations: ~/Library/Preferences/B.plist, ~/Library/Caches/B/*, ~/Library/Application Support/[app-name]/*, and ~/Library/Logs/[app-name]/*.

**Validates: Requirements 6.3**

### Property 17: Size Calculation Accuracy

*For any* collection of files selected for an operation (cleanup, uninstall, backup), the total size displayed should equal the sum of individual file sizes.

**Validates: Requirements 6.4, 9.2, 10.3**

### Property 18: Complete Application Removal

*For any* application uninstallation operation, after completion, neither the application bundle nor any of its identified associated files should exist on the file system.

**Validates: Requirements 6.5**

### Property 19: Safe List Enforcement

*For any* file whose path starts with a protected prefix (/System, /Library/Apple, /usr/bin, /usr/sbin) or matches a safe-list pattern, the file should never appear in cleanup candidates and deletion attempts should be blocked.

**Validates: Requirements 7.2, 7.3**

### Property 20: Cleanup Preview Completeness

*For any* set of files selected for cleanup, the preview should contain exactly the same files that will be affected by the cleanup operation.

**Validates: Requirements 9.1**

### Property 21: Backup Creation When Enabled

*For any* cleanup operation with backup enabled, a compressed backup archive should be created before any files are deleted, and the backup should contain all files that will be deleted.

**Validates: Requirements 10.1**

### Property 22: Backup Storage Location

*For any* backup created, it should be stored in the designated backup directory with a filename containing a timestamp, and the backup should be retrievable from that location.

**Validates: Requirements 10.2**

### Property 23: Backup and Restore Round Trip

*For any* set of files, backing them up and then restoring from the backup should produce files with identical content and relative paths to the originals.

**Validates: Requirements 10.5**

### Property 24: Scheduled Cleanup Category Restriction

*For any* scheduled cleanup operation, only files in safe categories (system caches, application caches, temporary files) should be included in the cleanup, and files in other categories (large files, old files, applications) should be excluded.

**Validates: Requirements 11.2**

### Property 25: Scheduled Cleanup Error Logging

*For any* scheduled cleanup operation that encounters errors, all errors should be logged with timestamps and file paths, and an error summary should be available to the user.

**Validates: Requirements 11.5**

### Property 26: Duplicate Detection by Content

*For any* two files with identical content (same hash value), the duplicate detector should identify them as duplicates and group them together regardless of their filenames or locations.

**Validates: Requirements 12.1**

### Property 27: Duplicate Wasted Space Calculation

*For any* duplicate group containing N files each of size S, the wasted space should be calculated as S × (N - 1).

**Validates: Requirements 12.2**

### Property 28: Duplicate Preservation Guarantee

*For any* duplicate group selected for cleanup, after the cleanup operation completes, at least one file from the group should remain on the file system.

**Validates: Requirements 12.4**

### Property 29: Recent Log Preservation

*For any* log file with modification date within the last 7 days, it should never be deleted during log cleanup operations regardless of user selection.

**Validates: Requirements 13.4**

### Property 30: Conditional Log Archiving

*For any* log file older than 30 days selected for removal when backup is enabled, the file should be compressed and archived before deletion.

**Validates: Requirements 13.5**

### Property 31: Downloads Categorization by Type

*For any* file in the Downloads folder, it should be categorized by its file type (document, image, archive, installer) based on its extension and MIME type.

**Validates: Requirements 14.1, 14.3**

### Property 32: Cancellation and Rollback

*For any* cleanup operation that is cancelled mid-execution, the operation should stop within 2 seconds and any partially completed changes should be rolled back, leaving the file system in a consistent state.

**Validates: Requirements 15.5**

## Error Handling

### Error Categories

The application handles errors in four main categories:

1. **Permission Errors**: When the application lacks permissions to read or delete files
2. **In-Use Errors**: When files are locked by running processes
3. **System Protection Errors**: When operations target protected system files
4. **Resource Errors**: When operations fail due to insufficient disk space or memory

### Error Handling Strategies

**Permission Errors**:
- Log the error with file path and continue operation
- Display summary of inaccessible files to user
- Suggest running with elevated privileges if appropriate
- Never fail entire operation due to single permission error

**In-Use Errors**:
- Detect in-use files before deletion attempts
- Skip in-use files and continue with remaining files
- Report skipped files to user with application names
- Suggest closing applications and retrying

**System Protection Errors**:
- Prevent operations before execution (fail fast)
- Display clear warning about protected files
- Remove protected files from selection
- Log attempted violations for security audit

**Resource Errors**:
- Check available disk space before backup operations
- Monitor memory usage during scanning
- Implement batch processing to limit memory footprint
- Gracefully degrade (skip backups if insufficient space)

### Error Recovery

**Atomic Operations**:
- Group related file operations into transactions
- Implement rollback for failed multi-file operations
- Use temporary markers to track operation progress
- Clean up markers on successful completion

**Backup-Based Recovery**:
- Create backups before destructive operations
- Provide restore function for recent operations
- Automatically suggest restore on operation failure
- Maintain backup integrity with checksums

**State Consistency**:
- Validate file system state before operations
- Re-scan affected areas after errors
- Update UI to reflect actual file system state
- Never cache stale file information

## Testing Strategy

### Dual Testing Approach

The application requires both unit testing and property-based testing for comprehensive coverage:

**Unit Tests**: Focus on specific examples, edge cases, and error conditions
- Specific file path patterns (e.g., Safari cache location)
- Edge cases (empty directories, single-file cleanup)
- Error conditions (permission denied, file not found)
- Integration points between components
- macOS-specific API interactions

**Property-Based Tests**: Verify universal properties across all inputs
- File categorization correctness across random file sets
- Size calculations with randomly generated file collections
- Filter behavior with random thresholds and file attributes
- Duplicate detection with various file content patterns
- Safe-list enforcement with random path combinations

Together, unit tests catch concrete bugs in specific scenarios while property tests verify general correctness across the input space.

### Property-Based Testing Configuration

**Framework**: Use Swift's built-in testing framework with a property-based testing library such as SwiftCheck or swift-check.

**Test Configuration**:
- Minimum 100 iterations per property test (due to randomization)
- Each property test must reference its design document property
- Tag format: `// Feature: mac-storage-cleanup, Property {number}: {property_text}`

**Example Property Test Structure**:
```swift
// Feature: mac-storage-cleanup, Property 5: Category Size Aggregation
func testCategorySizeAggregation() {
    property("Sum of file sizes equals category total") <- forAll { (files: [FileMetadata]) in
        let analyzer = StorageAnalyzer()
        let result = analyzer.analyze(scanResult: ScanResult(files: files))
        
        for category in CleanupCategory.allCases {
            let categoryFiles = result.categorizedFiles[category] ?? []
            let expectedSize = categoryFiles.reduce(0) { $0 + $1.size }
            let actualSize = result.categoryTotals[category] ?? 0
            
            return expectedSize == actualSize
        }
    }
}
```

### Test Coverage Requirements

**Component-Level Testing**:
- File Scanner: Path traversal, categorization, error handling
- Storage Analyzer: Size calculations, filtering, duplicate detection
- Cleanup Engine: Deletion operations, safe-list enforcement, rollback
- Application Manager: App discovery, associated file finding, uninstallation
- Cache Manager: Cache identification across all supported locations
- Backup Manager: Backup creation, compression, restoration
- Safe List Manager: Protection rule enforcement

**Integration Testing**:
- End-to-end scan → analyze → cleanup workflows
- Backup → cleanup → restore workflows
- Application uninstall with associated files
- Scheduled cleanup execution
- Error recovery scenarios

**Platform-Specific Testing**:
- Test on multiple macOS versions (minimum: last 3 major versions)
- Verify safe-list accuracy for each macOS version
- Test with various file system configurations (APFS, HFS+)
- Verify permissions handling on different macOS security settings

### Performance Testing

While not part of property-based testing, performance benchmarks should be established:
- Scan performance: 10,000 files per second minimum
- Memory usage: 500MB maximum during normal operations
- UI responsiveness: 60 FPS during background operations
- Cancellation response: 2 seconds maximum

### Manual Testing Requirements

Some requirements cannot be fully automated and require manual verification:
- UI layout and visual design
- User interaction flows and confirmations
- Notification display and timing
- Accessibility features
- Real-time progress updates
