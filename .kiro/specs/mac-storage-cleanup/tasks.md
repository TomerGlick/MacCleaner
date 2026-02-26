# Implementation Plan: Mac Storage Cleanup Application

## Overview

This implementation plan breaks down the Mac storage cleanup application into discrete coding tasks. The application will be built using Swift and AppKit, following the modular architecture defined in the design document. Tasks are organized to build core functionality first, then add features incrementally, with testing integrated throughout.

## Tasks

- [x] 1. Set up project structure and core types
  - Create Xcode project with Swift and AppKit
  - Define core data models: `FileMetadata`, `CleanupCategory`, `FileType`, `ScanResult`, `AnalysisResult`
  - Define error types: `ScanError`, `CleanupError`, `UninstallError`, `RestoreError`
  - Set up testing framework and configure property-based testing library (SwiftCheck)
  - _Requirements: All requirements (foundation)_

- [ ] 2. Implement Safe List Manager
  - [x] 2.1 Create SafeListManager with protected paths and patterns
    - Implement `SafeListManager` protocol with `isProtected(url:)` and `isProtected(path:)` methods
    - Define protected system directories: /System, /Library/Apple, /usr/bin, /usr/sbin, /private/var/db
    - Define protected user directories: ~/Library/Keychains, ~/Library/Mail, ~/Library/Messages, ~/Library/Photos
    - Add macOS version detection and version-specific safe-list updates
    - _Requirements: 7.1, 7.2, 7.3, 7.5_
  
  - [ ]* 2.2 Write property test for safe-list enforcement
    - **Property 19: Safe List Enforcement**
    - **Validates: Requirements 7.2, 7.3**
    - Generate random file paths including protected and non-protected paths
    - Verify protected paths are correctly identified
    - Verify non-protected paths are not blocked
    - Run with minimum 100 iterations

- [ ] 3. Implement File Scanner
  - [x] 3.1 Create FileScanner with directory traversal
    - Implement `FileScanner` protocol with `scan(paths:categories:progressHandler:)` async method
    - Use `FileManager` to enumerate directories recursively
    - Collect file metadata: URL, size, dates (created, modified, accessed), type
    - Implement batch processing (1000 files per batch) for memory management
    - Check safe-list before adding files to results
    - Handle permission errors gracefully and continue scanning
    - _Requirements: 1.1, 1.2, 1.3, 1.5_
  
  - [x] 3.2 Add file categorization logic
    - Implement path-based categorization for caches, logs, temporary files
    - Implement extension-based categorization (.tmp, .temp, .cache)
    - Implement size-based categorization for large files (>100MB)
    - Implement age-based categorization for old files (>365 days)
    - _Requirements: 1.2, 2.1, 2.2, 2.3, 3.1, 3.2, 4.1, 5.1_
  
  - [ ]* 3.3 Write property test for file categorization
    - **Property 1: File Categorization Completeness**
    - **Validates: Requirements 1.2**
    - Generate random file metadata with various paths and extensions
    - Verify each file is assigned to at least one valid category
    - Run with minimum 100 iterations
  
  - [ ]* 3.4 Write property test for path-based category detection
    - **Property 2: Path-Based Category Detection**
    - **Validates: Requirements 2.1, 2.2, 2.3, 3.1, 13.1**
    - Generate files in known cache, temporary, and log directories
    - Verify correct category assignment based on path
    - Run with minimum 100 iterations
  
  - [ ]* 3.5 Write property test for extension-based detection
    - **Property 3: Extension-Based Temporary File Detection**
    - **Validates: Requirements 3.2**
    - Generate files with .tmp, .temp, .cache extensions in various locations
    - Verify all are categorized as temporary files
    - Run with minimum 100 iterations
  
  - [ ]* 3.6 Write property test for permission error resilience
    - **Property 4: Permission Error Resilience**
    - **Validates: Requirements 1.3**
    - Simulate permission-denied errors during scanning
    - Verify scanning continues and errors are reported
    - Run with minimum 100 iterations

- [ ] 4. Implement Storage Analyzer
  - [x] 4.1 Create StorageAnalyzer with analysis logic
    - Implement `StorageAnalyzer` protocol with `analyze(scanResult:)` method
    - Implement `categorize(file:)` to assign files to categories
    - Implement `calculateSavings(files:)` for size aggregation
    - Implement duplicate detection using SHA-256 hashing (files >1MB only)
    - Group duplicate files and calculate wasted space
    - _Requirements: 1.4, 12.1, 12.2, 12.5_
  
  - [x] 4.2 Add filtering and sorting capabilities
    - Implement age-based filtering with configurable thresholds
    - Implement size-based filtering with configurable thresholds
    - Implement file type filtering
    - Implement sorting by size (descending order)
    - Implement filter composition (multiple filters applied together)
    - _Requirements: 3.3, 4.1, 4.3, 4.4, 5.1, 5.4, 14.2, 14.4_
  
  - [ ]* 4.3 Write property test for category size aggregation
    - **Property 5: Category Size Aggregation**
    - **Validates: Requirements 1.4**
    - Generate random file collections with various sizes
    - Verify sum of file sizes per category equals reported total
    - Run with minimum 100 iterations
  
  - [ ]* 4.4 Write property test for age-based filtering
    - **Property 8: Age-Based File Filtering**
    - **Validates: Requirements 3.3, 5.1, 14.2**
    - Generate files with random access dates
    - Test various age thresholds
    - Verify only files older than threshold are included
    - Run with minimum 100 iterations
  
  - [ ]* 4.5 Write property test for size-based filtering
    - **Property 9: Size-Based File Filtering**
    - **Validates: Requirements 4.1, 12.5**
    - Generate files with random sizes
    - Test various size thresholds
    - Verify only files meeting size criteria are included
    - Run with minimum 100 iterations
  
  - [ ]* 4.6 Write property test for sort order correctness
    - **Property 10: Sort Order Correctness**
    - **Validates: Requirements 4.3**
    - Generate random file collections
    - Sort by size descending
    - Verify each file size >= next file size
    - Run with minimum 100 iterations
  
  - [ ]* 4.7 Write property test for filter composition
    - **Property 11: Filter Composition**
    - **Validates: Requirements 4.4, 14.4**
    - Generate random file collections
    - Apply multiple filters (type + age)
    - Verify results satisfy all filter criteria
    - Run with minimum 100 iterations
  
  - [ ]* 4.8 Write property test for duplicate detection
    - **Property 26: Duplicate Detection by Content**
    - **Validates: Requirements 12.1**
    - Generate files with identical and different content
    - Verify files with same content are grouped as duplicates
    - Run with minimum 100 iterations
  
  - [ ]* 4.9 Write property test for duplicate wasted space calculation
    - **Property 27: Duplicate Wasted Space Calculation**
    - **Validates: Requirements 12.2**
    - Generate duplicate groups with various sizes and counts
    - Verify wasted space = size × (count - 1)
    - Run with minimum 100 iterations

- [x] 5. Checkpoint - Core scanning and analysis complete
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 6. Implement Cache Manager
  - [x] 6.1 Create CacheManager for cache identification
    - Implement `CacheManager` protocol with cache finding methods
    - Implement `findSystemCaches()` for ~/Library/Caches
    - Implement `findApplicationCaches()` for app-specific caches
    - Implement `findBrowserCaches()` for Safari, Chrome, Firefox, Edge
    - Map browser enum to specific cache paths
    - _Requirements: 2.1, 2.2, 2.3_
  
  - [x] 6.2 Add cache clearing functionality
    - Implement `clearCaches(caches:)` method
    - Delete only selected cache files
    - Preserve cache directory structure
    - Check if files are in use before deletion
    - _Requirements: 2.5, 2.6_
  
  - [ ]* 6.3 Write property test for selective cache deletion
    - **Property 6: Selective Cache Deletion**
    - **Validates: Requirements 2.5**
    - Generate cache directory structures with files
    - Select subset of files for deletion
    - Verify only selected files removed and directories remain
    - Run with minimum 100 iterations

- [ ] 7. Implement Backup Manager
  - [x] 7.1 Create BackupManager with backup creation
    - Implement `BackupManager` protocol with `createBackup(files:destination:)` async method
    - Use Compression framework to create compressed archives
    - Store backups in ~/Library/Application Support/MacStorageCleanup/Backups
    - Include manifest file with original paths and metadata
    - Generate UUID and timestamp for each backup
    - _Requirements: 10.1, 10.2_
  
  - [x] 7.2 Add backup restoration functionality
    - Implement `restoreBackup(backup:destination:)` async method
    - Extract compressed archives
    - Restore files to original or specified locations
    - Verify file integrity using checksums
    - _Requirements: 10.5_
  
  - [x] 7.3 Add backup management features
    - Implement `listBackups()` to enumerate existing backups
    - Implement `deleteBackup(backup:)` to remove old backups
    - Calculate backup sizes and display to user
    - _Requirements: 10.3, 10.4_
  
  - [ ]* 7.4 Write property test for backup creation when enabled
    - **Property 21: Backup Creation When Enabled**
    - **Validates: Requirements 10.1**
    - Generate random file sets
    - Create backups with backup option enabled
    - Verify backup archive is created and contains all files
    - Run with minimum 100 iterations
  
  - [ ]* 7.5 Write property test for backup storage location
    - **Property 22: Backup Storage Location**
    - **Validates: Requirements 10.2**
    - Create backups with timestamps
    - Verify backups stored in correct directory with timestamp in filename
    - Verify backups are retrievable
    - Run with minimum 100 iterations
  
  - [ ]* 7.6 Write property test for backup and restore round trip
    - **Property 23: Backup and Restore Round Trip**
    - **Validates: Requirements 10.5**
    - Generate random file sets
    - Backup then restore files
    - Verify restored files have identical content and paths
    - Run with minimum 100 iterations

- [ ] 8. Implement Cleanup Engine
  - [x] 8.1 Create CleanupEngine with validation
    - Implement `CleanupEngine` protocol with `cleanup(files:options:progressHandler:)` async method
    - Implement `validateCleanup(files:)` to check against safe-list
    - Check if files are in use using file handle attempts
    - Implement cancellation support
    - _Requirements: 2.6, 3.4, 3.5, 7.2, 7.3, 9.4_
  
  - [x] 8.2 Add deletion operations with safety checks
    - Implement trash movement using `NSFileManager.trashItem`
    - Implement permanent deletion for specific cases
    - Integrate with BackupManager for pre-deletion backups
    - Implement atomic operations with rollback on failure
    - Track progress and report to progress handler
    - _Requirements: 4.5, 5.5, 9.5, 14.5_
  
  - [x] 8.3 Add system file exclusion logic
    - Filter out system files and application bundles from old files
    - Enforce safe-list rules before any deletion
    - Block deletion attempts on protected files
    - _Requirements: 5.2, 7.2, 7.3_
  
  - [ ]* 8.4 Write property test for in-use file protection
    - **Property 7: In-Use File Protection**
    - **Validates: Requirements 2.6, 3.5**
    - Simulate files in use by processes
    - Attempt cleanup operations
    - Verify in-use files are skipped and reported
    - Run with minimum 100 iterations
  
  - [ ]* 8.5 Write property test for trash movement
    - **Property 12: Trash Movement vs Permanent Deletion**
    - **Validates: Requirements 4.5, 5.5, 14.5**
    - Perform cleanup on large/old/download files
    - Verify files moved to Trash, not permanently deleted
    - Run with minimum 100 iterations
  
  - [ ]* 8.6 Write property test for system file exclusion
    - **Property 13: System File Exclusion**
    - **Validates: Requirements 5.2**
    - Generate file sets including system files and app bundles
    - Apply old file filtering
    - Verify system files never appear in results
    - Run with minimum 100 iterations
  
  - [ ]* 8.7 Write property test for size calculation accuracy
    - **Property 17: Size Calculation Accuracy**
    - **Validates: Requirements 6.4, 9.2, 10.3**
    - Generate random file collections
    - Calculate total size for operations
    - Verify displayed total equals sum of individual sizes
    - Run with minimum 100 iterations
  
  - [ ]* 8.8 Write property test for cleanup preview completeness
    - **Property 20: Cleanup Preview Completeness**
    - **Validates: Requirements 9.1**
    - Select files for cleanup
    - Generate preview
    - Verify preview contains exactly the files that will be affected
    - Run with minimum 100 iterations
  
  - [ ]* 8.9 Write property test for cancellation and rollback
    - **Property 32: Cancellation and Rollback**
    - **Validates: Requirements 15.5**
    - Start cleanup operation
    - Cancel mid-execution
    - Verify operation stops within 2 seconds and partial changes are rolled back
    - Run with minimum 100 iterations

- [ ] 9. Implement Application Manager
  - [x] 9.1 Create ApplicationManager for app discovery
    - Implement `ApplicationManager` protocol with `discoverApplications()` async method
    - Search /Applications and ~/Applications for .app bundles
    - Use `NSWorkspace` to get application metadata (name, version, bundle ID)
    - Calculate application bundle sizes
    - Get last used date from launch services
    - Check if application is running using `NSRunningApplication`
    - _Requirements: 6.1, 6.2, 6.6_
  
  - [x] 9.2 Add associated files discovery
    - Implement `findAssociatedFiles(for:)` async method
    - Search for preferences: ~/Library/Preferences/[bundle-id].plist
    - Search for caches: ~/Library/Caches/[bundle-id]
    - Search for support files: ~/Library/Application Support/[app-name]
    - Search for logs: ~/Library/Logs/[app-name]
    - _Requirements: 6.3, 6.4_
  
  - [x] 9.3 Add uninstallation functionality
    - Implement `uninstall(application:removeAssociatedFiles:)` async method
    - Check if application is running and prompt to quit
    - Remove application bundle
    - Remove associated files if requested
    - Calculate and report total space freed
    - _Requirements: 6.5, 6.6_
  
  - [ ]* 9.4 Write property test for application bundle discovery
    - **Property 15: Application Bundle Discovery**
    - **Validates: Requirements 6.1**
    - Create mock .app bundles in test directories
    - Run discovery
    - Verify all bundles are found
    - Run with minimum 100 iterations
  
  - [ ]* 9.5 Write property test for associated files discovery
    - **Property 16: Associated Files Discovery**
    - **Validates: Requirements 6.3**
    - Create mock applications with bundle identifiers
    - Create associated files in standard locations
    - Verify all associated files are found
    - Run with minimum 100 iterations
  
  - [ ]* 9.6 Write property test for complete application removal
    - **Property 18: Complete Application Removal**
    - **Validates: Requirements 6.5**
    - Create mock application with associated files
    - Perform uninstallation
    - Verify no application or associated files remain
    - Run with minimum 100 iterations

- [x] 10. Checkpoint - Core cleanup functionality complete
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 11. Implement log file management
  - [x] 11.1 Add log file scanning and categorization
    - Extend FileScanner to identify log files in /var/log, ~/Library/Logs
    - Categorize logs by application and age
    - Calculate log sizes and ages
    - _Requirements: 13.1, 13.2, 13.3_
  
  - [x] 11.2 Add log cleanup with preservation rules
    - Implement log cleanup that preserves logs from last 7 days
    - Implement conditional archiving for logs older than 30 days when backup enabled
    - Integrate with BackupManager for log archiving
    - _Requirements: 13.4, 13.5_
  
  - [ ]* 11.3 Write property test for recent log preservation
    - **Property 29: Recent Log Preservation**
    - **Validates: Requirements 13.4**
    - Generate log files with various ages
    - Attempt cleanup
    - Verify logs newer than 7 days are never deleted
    - Run with minimum 100 iterations
  
  - [ ]* 11.4 Write property test for conditional log archiving
    - **Property 30: Conditional Log Archiving**
    - **Validates: Requirements 13.5**
    - Generate old log files (>30 days)
    - Perform cleanup with backup enabled
    - Verify logs are archived before deletion
    - Run with minimum 100 iterations

- [ ] 12. Implement duplicate file management
  - [x] 12.1 Add duplicate preservation logic to CleanupEngine
    - Implement duplicate cleanup that preserves at least one copy
    - Allow user to select which copy to keep
    - Integrate with existing cleanup operations
    - _Requirements: 12.3, 12.4_
  
  - [ ]* 12.2 Write property test for duplicate preservation guarantee
    - **Property 28: Duplicate Preservation Guarantee**
    - **Validates: Requirements 12.4**
    - Generate duplicate file groups
    - Perform duplicate cleanup
    - Verify at least one file from each group remains
    - Run with minimum 100 iterations

- [ ] 13. Implement Downloads folder management
  - [x] 13.1 Add Downloads-specific scanning and categorization
    - Extend FileScanner to scan ~/Downloads
    - Categorize files by type: documents, images, archives, installers
    - Use file extensions and MIME types for categorization
    - Flag files older than 90 days as cleanup candidates
    - _Requirements: 14.1, 14.2, 14.3_
  
  - [ ]* 13.2 Write property test for Downloads categorization
    - **Property 31: Downloads Categorization by Type**
    - **Validates: Requirements 14.1, 14.3**
    - Generate files with various extensions in Downloads
    - Verify correct type categorization
    - Run with minimum 100 iterations

- [ ] 14. Implement scheduled cleanup
  - [x] 14.1 Create scheduled cleanup coordinator
    - Implement scheduling using `NSBackgroundActivityScheduler` or Launch Agents
    - Support daily, weekly, monthly intervals
    - Store user preferences for scheduled cleanup
    - Restrict scheduled cleanup to safe categories only
    - _Requirements: 11.1, 11.2, 11.4_
  
  - [x] 14.2 Add scheduled cleanup execution and error handling
    - Execute cleanup operations in background
    - Log all operations and errors
    - Display notifications on completion
    - Handle errors gracefully and notify user
    - _Requirements: 11.3, 11.5_
  
  - [ ]* 14.3 Write property test for scheduled cleanup category restriction
    - **Property 24: Scheduled Cleanup Category Restriction**
    - **Validates: Requirements 11.2**
    - Generate file sets across all categories
    - Perform scheduled cleanup
    - Verify only safe categories are cleaned
    - Run with minimum 100 iterations
  
  - [ ]* 14.4 Write property test for scheduled cleanup error logging
    - **Property 25: Scheduled Cleanup Error Logging**
    - **Validates: Requirements 11.5**
    - Simulate errors during scheduled cleanup
    - Verify all errors are logged with details
    - Verify error summary is available
    - Run with minimum 100 iterations

- [ ] 15. Implement age threshold bounds enforcement
  - [x] 15.1 Add threshold validation to StorageAnalyzer
    - Implement threshold clamping to [30, 1095] days range
    - Apply clamped values to filtering operations
    - Update UI to reflect clamped values
    - _Requirements: 5.4_
  
  - [ ]* 15.2 Write property test for age threshold bounds enforcement
    - **Property 14: Age Threshold Bounds Enforcement**
    - **Validates: Requirements 5.4**
    - Test with thresholds below 30 and above 1095
    - Verify values are clamped to valid range
    - Run with minimum 100 iterations

- [x] 16. Checkpoint - All core features implemented
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 17. Implement User Interface - Main Window
  - [x] 17.1 Create main window with storage visualization
    - Create AppKit window with SwiftUI views
    - Implement storage breakdown visualization (pie chart or bar chart)
    - Display total capacity, used space, available space
    - Show storage by category: Applications, Documents, System, Caches, Other
    - Display both absolute sizes (GB) and percentages
    - _Requirements: 8.1, 8.2, 8.5_
  
  - [x] 17.2 Add drill-down navigation
    - Implement category selection and drill-down views
    - Show subcategories and individual large items
    - Update visualization in real-time as cleanup completes
    - _Requirements: 8.3, 8.4_

- [ ] 18. Implement User Interface - Scan and Analysis Views
  - [x] 18.1 Create scan initiation and progress view
    - Add scan button and configuration options
    - Display real-time progress: percentage, current directory, files scanned
    - Show scan results summary after completion
    - _Requirements: 1.1, 1.5_
  
  - [x] 18.2 Create category views for cleanup candidates
    - Create views for each category: caches, temporary files, large files, old files, logs, downloads, duplicates
    - Display file lists with required metadata (path, size, date, type)
    - Implement sorting and filtering controls
    - Allow selection of files/categories for cleanup
    - _Requirements: 2.4, 4.2, 4.4, 5.3, 13.3, 14.3_

- [ ] 19. Implement User Interface - Cleanup and Confirmation
  - [x] 19.1 Create cleanup preview and confirmation dialog
    - Display preview of all files that will be affected
    - Show total space that will be freed
    - Allow deselection of individual items or categories
    - Require explicit confirmation before proceeding
    - _Requirements: 9.1, 9.2, 9.3, 9.4_
  
  - [x] 19.2 Create cleanup progress view
    - Display real-time progress: current file, files processed, space freed
    - Show progress bar and percentage
    - Provide cancel button with confirmation
    - _Requirements: 9.5_
  
  - [x] 19.3 Create cleanup results view
    - Display summary: files removed, space freed, errors encountered
    - Show backup location if backup was created
    - Provide option to restore from backup
    - _Requirements: 10.1, 10.2, 10.5_

- [ ] 20. Implement User Interface - Application Management
  - [x] 20.1 Create applications list view
    - Display all discovered applications
    - Show application name, version, size, last used date
    - Implement sorting by size or last used date
    - _Requirements: 6.1, 6.2_
  
  - [x] 20.2 Create application uninstall view
    - Show application details and associated files
    - Display total space that will be freed
    - Show warning if application is running
    - Provide uninstall confirmation dialog
    - _Requirements: 6.3, 6.4, 6.5, 6.6_

- [ ] 21. Implement User Interface - Preferences and Settings
  - [x] 21.1 Create preferences window
    - Add backup preferences: enable/disable, backup location
    - Add cleanup preferences: move to trash vs permanent delete
    - Add threshold preferences: old file age, large file size
    - Add scheduled cleanup configuration: enable/disable, interval, categories
    - _Requirements: 5.4, 10.1, 11.1, 11.4_
  
  - [x] 21.2 Create backup management view
    - List all existing backups with dates and sizes
    - Provide restore functionality
    - Provide delete functionality for old backups
    - Show prompt for backups older than 30 days
    - _Requirements: 10.3, 10.4, 10.5_

- [ ] 22. Implement User Interface - Notifications
  - [x] 22.1 Add notification support
    - Implement macOS notification center integration
    - Display notifications for scheduled cleanup completion
    - Display notifications for errors and warnings
    - _Requirements: 11.3_

- [ ] 23. Implement application services and coordination
  - [x] 23.1 Create application coordinator
    - Implement main application service that coordinates between components
    - Manage application state and user preferences
    - Handle component lifecycle and dependencies
    - Implement error aggregation and reporting
    - _Requirements: All requirements (coordination)_
  
  - [x] 23.2 Add user preferences persistence
    - Implement UserDefaults storage for preferences
    - Load preferences on application launch
    - Save preferences on changes
    - Provide default values for all preferences
    - _Requirements: 5.4, 10.1, 11.1, 11.4_

- [ ] 24. Final integration and polish
  - [x] 24.1 Wire all components together
    - Connect UI to application services
    - Connect application services to core components
    - Ensure all data flows correctly through the system
    - Test end-to-end workflows
    - _Requirements: All requirements_
  
  - [x] 24.2 Add error handling and user feedback
    - Implement comprehensive error handling throughout UI
    - Display user-friendly error messages
    - Add logging for debugging
    - Implement crash reporting
    - _Requirements: All requirements (error handling)_
  
  - [x] 24.3 Performance optimization
    - Verify background thread usage for file operations
    - Verify batch processing for memory management
    - Test with large file sets (>100,000 files)
    - Optimize UI responsiveness during operations
    - _Requirements: 15.1, 15.2, 15.3, 15.4, 15.5_

- [x] 25. Final checkpoint - Complete application
  - Ensure all tests pass, ask the user if questions arise.
  - Verify all requirements are implemented
  - Test on multiple macOS versions
  - Perform manual testing of UI flows

## Notes

- Tasks marked with `*` are optional property-based tests that can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation throughout development
- Property tests validate universal correctness properties with minimum 100 iterations each
- Unit tests should be added for specific examples and edge cases not covered by property tests
- The implementation follows a bottom-up approach: core components first, then integration, then UI
- All file operations should run on background threads to maintain UI responsiveness
- Safe-list enforcement is critical and should be tested thoroughly before any cleanup operations
