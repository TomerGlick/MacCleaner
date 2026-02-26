# UI Integration Fix for Developer and AI Agent Caches

## Problem
Developer tool caches and AI agent caches were being scanned but not displayed in the cleanup candidates UI.

## Root Cause
The `CleanupCandidatesViewModel` was using sample/mock data instead of loading real cache data from the `CacheManager`.

## Solution

### Changes Made

1. **CleanupCandidatesViewModel.swift**
   - Added `import MacStorageCleanupCore` to access cache manager types
   - Replaced `loadCandidates()` to call async `loadRealCandidates()`
   - Implemented `loadRealCandidates()` method that:
     - Accesses `ApplicationCoordinator.shared.cacheManager`
     - Calls `findSystemCaches()`, `findApplicationCaches()`, `findBrowserCaches()`
     - Calls `findDeveloperCaches()` to load Xcode, Android Studio, npm, etc.
     - Calls `findAIAgentCaches()` to load Cursor, Copilot, Kiro, etc.
     - Converts all cache results to `CleanupCandidateData` objects
     - Updates the UI with real cache data

### How It Works

When a user navigates to the "Cleanup Candidates" view with the "Caches" category:

1. The view model loads real cache data asynchronously
2. System caches, app caches, browser caches are loaded
3. **Developer tool caches** are loaded (Xcode DerivedData, npm cache, etc.)
4. **AI agent caches** are loaded (Cursor, Copilot, Kiro, etc.)
5. All caches are displayed in the list with:
   - Descriptive names (e.g., "Xcode - DerivedData", "Cursor - Cache")
   - Actual file paths
   - Real size calculations
   - Ability to select and clean up

### User Experience

Users will now see:
- All developer tool caches with their actual sizes
- All AI agent caches with their actual sizes
- Ability to select specific caches to clean
- Total space that can be freed by cleaning selected caches

### Example Cache Entries Displayed

- "Xcode - DerivedData" - 15.2 GB
- "Xcode - Archives" - 8.5 GB
- "npm" - 2.3 GB
- "Homebrew" - 1.8 GB
- "Cursor - Cache" - 850 MB
- "GitHub Copilot" - 320 MB
- "Kiro - cache" - 150 MB

## Testing

To verify the fix:
1. Build and run the app
2. Navigate to "Cleanup Candidates" tab
3. Select "Caches" category
4. You should now see real cache entries including developer tools and AI agents
5. Select caches and verify the total size calculation
6. Clean up selected caches to free space
