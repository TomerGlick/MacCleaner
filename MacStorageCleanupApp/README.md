# Mac Storage Cleanup App

This is the macOS application UI for the Mac Storage Cleanup utility.

## Features

- **Storage Visualization**: Interactive pie chart showing storage breakdown by category
- **Real-time Statistics**: Display of total capacity, used space, and available space
- **Category Breakdown**: Detailed view of storage by category (Applications, Documents, System, Caches, Other)
- **Size and Percentage Display**: Shows both absolute sizes (GB) and percentages for each category

## Requirements

- macOS 13.0 or later
- Xcode 15.0 or later

## Building

Open `MacStorageCleanupApp.xcodeproj` in Xcode and build the project.

Alternatively, build from the command line:

```bash
xcodebuild -project MacStorageCleanupApp.xcodeproj -scheme MacStorageCleanupApp -configuration Debug
```

## Architecture

The app follows the MVVM (Model-View-ViewModel) pattern:

- **Views**: SwiftUI views for the UI components
  - `MainWindowView`: Main window container
  - `StorageHeaderView`: Header with storage statistics
  - `StorageVisualizationView`: Pie chart visualization
  - `CategoryBreakdownView`: List of categories with details

- **ViewModels**: Business logic and state management
  - `StorageViewModel`: Manages storage data and calculations

- **Models**: Data structures
  - `StorageCategoryData`: Represents a storage category with size and metadata

## Integration with Backend

The app is designed to integrate with the `MacStorageCleanupCore` library which provides:
- File scanning
- Storage analysis
- Cleanup operations
- Cache management
- Application management

Currently, the app calculates storage data directly for demonstration purposes. Full integration with the backend will be completed in subsequent tasks.
