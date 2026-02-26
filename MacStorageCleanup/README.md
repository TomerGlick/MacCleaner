# Mac Storage Cleanup

A native macOS utility built with Swift and AppKit that helps users analyze disk usage and safely remove unnecessary files.

## Project Structure

```
MacStorageCleanup/
├── Sources/
│   ├── Models/           # Core data models
│   │   ├── FileMetadata.swift
│   │   ├── CleanupCategory.swift
│   │   ├── ScanResult.swift
│   │   ├── AnalysisResult.swift
│   │   └── Errors.swift
│   └── main.swift        # Application entry point
├── Tests/
│   └── MacStorageCleanupTests.swift
└── Package.swift         # Swift Package Manager configuration
```

## Core Types

### Data Models
- **FileMetadata**: Represents file metadata (URL, size, dates, type, permissions)
- **CleanupCategory**: Enum for file categorization (caches, logs, temporary files, etc.)
- **ScanResult**: Result of file system scan operations
- **AnalysisResult**: Result of storage analysis with categorized files and duplicates
- **DuplicateGroup**: Group of duplicate files with hash and wasted space calculation

### Error Types
- **ScanError**: Errors during file system scanning
- **CleanupError**: Errors during cleanup operations
- **UninstallError**: Errors during application uninstallation
- **RestoreError**: Errors during backup restoration

## Building and Testing

### Build the project
```bash
swift build
```

### Run tests
```bash
swift test
```

### Run the application
```bash
swift run
```

## Testing Framework

The project uses:
- **XCTest**: Standard Swift testing framework for unit tests
- **SwiftCheck**: Property-based testing library for verifying universal correctness properties

Property-based tests run with a minimum of 100 iterations to ensure comprehensive coverage across the input space.

## Requirements

- macOS 13.0 or later
- Swift 5.9 or later
- Xcode 15.0 or later (for development)

## Development Status

✅ Task 1: Project structure and core types - Complete
- Xcode project with Swift Package Manager
- Core data models defined
- Error types defined
- Testing framework configured with SwiftCheck
