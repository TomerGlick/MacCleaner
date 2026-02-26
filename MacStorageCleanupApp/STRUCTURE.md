# Mac Storage Cleanup App Structure

## Directory Layout

```
MacStorageCleanupApp/
├── MacStorageCleanupApp.swift          # App entry point
├── Info.plist                          # App configuration
├── MacStorageCleanupApp.entitlements   # Sandbox permissions
├── Views/
│   ├── MainWindowView.swift            # Main container
│   ├── StorageHeaderView.swift         # Statistics header
│   ├── StorageVisualizationView.swift  # Chart visualization
│   └── CategoryBreakdownView.swift     # Category list
├── ViewModels/
│   └── StorageViewModel.swift          # Business logic
├── Models/
│   └── StorageCategoryData.swift       # Category data model
├── Tests/
│   └── StorageViewModelTests.swift     # Unit tests
├── README.md                           # Documentation
├── IMPLEMENTATION.md                   # Implementation details
└── STRUCTURE.md                        # This file

MacStorageCleanupApp.xcodeproj/
└── project.pbxproj                     # Xcode project file
```

## UI Layout

```
┌─────────────────────────────────────────────────────────────────┐
│  Mac Storage Cleanup                                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Total Capacity    Used Space         Available Space          │
│  500 GB            350 GB (70%)       150 GB (30%)             │
│                                                                 │
├─────────────────────────────────────────┬───────────────────────┤
│                                         │  Categories           │
│   Storage Breakdown                     │                       │
│                                         │  ● Applications       │
│        ╭─────────────╮                  │    100 GB    20%     │
│       ╱               ╲                 │    ████░░░░░░░       │
│      │    Pie Chart    │                │                       │
│      │   Visualization │                │  ● Documents          │
│       ╲               ╱                 │    80 GB     16%     │
│        ╰─────────────╯                  │    ███░░░░░░░░       │
│                                         │                       │
│   ■ Applications  ■ Documents           │  ● System             │
│   ■ System        ■ Caches              │    120 GB    24%     │
│   ■ Other                               │    █████░░░░░░       │
│                                         │                       │
│                                         │  ● Caches             │
│                                         │    30 GB     6%      │
│                                         │    █░░░░░░░░░░       │
│                                         │                       │
│                                         │  ● Other              │
│                                         │    20 GB     4%      │
│                                         │    █░░░░░░░░░░       │
└─────────────────────────────────────────┴───────────────────────┘
```

## Data Flow

```
User Opens App
     │
     ▼
MainWindowView
     │
     ├─► StorageHeaderView ──► StorageViewModel
     │                              │
     ├─► StorageVisualizationView ──┤
     │                              │
     └─► CategoryBreakdownView ─────┘
                                    │
                                    ▼
                            loadStorageData()
                                    │
                                    ├─► FileManager (disk info)
                                    │
                                    └─► calculateCategoryBreakdown()
                                            │
                                            ├─► /Applications
                                            ├─► ~/Documents
                                            ├─► ~/Library/Caches
                                            └─► System (estimated)
```

## Component Responsibilities

### Views (SwiftUI)
- **MainWindowView**: Layout and composition
- **StorageHeaderView**: Display statistics
- **StorageVisualizationView**: Render charts
- **CategoryBreakdownView**: List categories

### ViewModel
- **StorageViewModel**: 
  - Fetch disk information
  - Calculate category sizes
  - Format display values
  - Manage loading state

### Models
- **StorageCategoryData**:
  - Category name
  - Size in bytes
  - Percentage calculation
  - Color assignment
  - Formatted display

## Integration Points

### Current
- FileManager for disk space
- Directory size calculation
- ByteCountFormatter for display

### Future (with MacStorageCleanupCore)
- FileScanner for comprehensive scanning
- StorageAnalyzer for categorization
- CleanupEngine for operations
- CacheManager for cache detection
- ApplicationManager for app info
