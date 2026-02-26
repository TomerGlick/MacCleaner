# Cleanup Results View

## Overview

The `CleanupResultsView` displays the results of a cleanup operation, including files removed, space freed, errors encountered, and backup information. It provides options to restore from backup if one was created.

## Requirements Validated

- **Requirement 10.1**: Display backup location if backup was created
- **Requirement 10.2**: Show backup storage location with timestamp
- **Requirement 10.5**: Provide option to restore from backup

## Components

### CleanupResultsView

The main view that displays cleanup results with the following sections:

1. **Header**: Status icon, title, and message
2. **Summary Section**: Statistics showing files removed, space freed, and error count
3. **Backup Section**: Backup location with options to reveal in Finder or copy path
4. **Error Section**: Summary of errors with option to view details
5. **Restore Progress**: Progress indicator when restoring from backup
6. **Footer**: Actions including "Restore from Backup" and "Done"

### CleanupResultsViewModel

View model that manages:
- Cleanup result data (files removed, space freed, errors, backup location)
- Restore operation state and progress
- Computed properties for formatting and status
- Actions for restore, reveal in Finder, and copy path

## Features

### Summary Display

Shows key statistics:
- Files removed count
- Space freed (formatted as GB/MB)
- Error count (if any)

### Backup Information

When a backup was created:
- Displays backup filename
- Shows full path (selectable)
- "Show in Finder" button to reveal backup location
- "Copy path" button to copy backup path to clipboard

### Error Handling

- Displays error count in summary
- Shows brief error description
- "View Details" button opens sheet with full error list
- Each error shows formatted message with file path

### Restore Functionality

- "Restore from Backup" button (only shown if backup exists)
- Confirmation dialog before restoring
- Progress indicator during restore
- Success/error messages after restore completes

## Status States

### Successful
- Green checkmark icon
- "Cleanup Completed Successfully" title
- Shows files removed and space freed

### Partial Success
- Orange warning icon
- "Cleanup Completed with Errors" title
- Shows files removed and error count

### Failed
- Red X icon
- "Cleanup Failed" title
- Shows error information

## Usage Example

```swift
// Create cleanup result
let result = CleanupResult(
    filesRemoved: 42,
    spaceFreed: 5_000_000_000,
    errors: [],
    backupLocation: URL(fileURLWithPath: "/path/to/backup.tar.gz")
)

// Display results view
CleanupResultsView(result: result)
```

## Testing

The view model is fully tested in `CleanupResultsViewModelTests.swift`:
- Initialization with various result states
- Computed properties (formatting, status, backup info)
- Error message formatting
- Restore operations
- Backup location actions

## Integration

The view integrates with:
- `CleanupProgressView`: Shown after cleanup completes
- `BackupManager`: For restore operations
- `CleanupEngine`: Receives cleanup results

## Future Enhancements

- Export error list to file
- Selective restore (choose specific files)
- Backup size display
- Backup expiration warnings
