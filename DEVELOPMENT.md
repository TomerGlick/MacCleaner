# Development Setup

## Prerequisites

- macOS 13.0 (Ventura) or later
- Xcode 15.0 or later
- Apple Developer account (for code signing)

## Building from Source

1. **Clone the repository**
   ```bash
   git clone https://github.com/TomerGlick/MacCleaner.git
   cd MacCleaner
   ```

2. **Open the project in Xcode**
   ```bash
   open MacStorageCleanupApp.xcodeproj
   ```

3. **Configure Code Signing**

   The project is set up for its own signing team, so a fork needs its own:

   - Select the `MacStorageCleanupApp` target in Xcode
   - Go to "Signing & Capabilities" and pick your Team
   - Change the **Bundle Identifier** to something you own, e.g.
     `com.yourname.MacStorageCleanup` — it must be unique, and macOS ties Full Disk
     Access to it, so changing it means granting that permission again

4. **Build and Run**
   - Select the `MacStorageCleanupApp` scheme
   - Press `Cmd + R` to build and run
   - Grant Full Disk Access when prompted

## Project Structure

```
MacCleaner/
├── MacStorageCleanup/              # Core library (Swift Package)
│   ├── Sources/
│   │   ├── CacheManager.swift
│   │   ├── CleanupEngine.swift
│   │   ├── SafeListManager.swift
│   │   └── Models/
│   └── Tests/
└── MacStorageCleanupApp/           # SwiftUI application
    ├── Views/
    ├── ViewModels/
    └── Services/
```

## Granting Full Disk Access

The app requires Full Disk Access to scan and clean cache directories:

1. Open **System Settings** > **Privacy & Security** > **Full Disk Access**
2. Click the **+** button
3. Navigate to your built app (usually in `~/Library/Developer/Xcode/DerivedData/...`)
4. Add the app to the list
5. Restart the app

## Debug Mode

To test cleanup operations without actually deleting files:

1. Open Preferences (gear icon)
2. Go to the "Cleanup" tab
3. Enable "Debug Mode (simulate deletions)"

## Running Tests

```bash
# Core library (the bulk of the suite)
cd MacStorageCleanup && swift test

# App layer: view models, risk mapping, group selection
xcodebuild test -project MacStorageCleanupApp.xcodeproj -scheme MacStorageCleanupApp
```

## Cutting a Release

`./notarize_release.sh <version>` builds, signs with a Developer ID certificate,
packages the DMG, submits it to Apple for notarization and staples the ticket, so the
download opens without a Gatekeeper warning. It preflights the certificate and the
stored notarization credentials and explains anything missing before it starts building.
The setup steps are documented at the top of that script.

## Common Issues

### "App is damaged and can't be opened"

This happens with unsigned debug builds. Either:
- Build with your own signing certificate
- Right-click the app and select "Open" (first time only)
- Or remove the quarantine attribute:
  ```bash
  xattr -cr /path/to/MacStorageCleanupApp.app
  ```

### "No permission to access files"

Make sure you've granted Full Disk Access in System Settings.

### Build errors about missing team

You need to set your own development team in Xcode project settings.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on contributing to this project.
