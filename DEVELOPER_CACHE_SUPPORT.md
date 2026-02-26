# Developer and AI Agent Cache Support

## Overview
Added comprehensive support for scanning and cleaning developer tool caches and AI agent caches in the MacStorageCleanup application.

## Developer Tools Supported

### IDEs and Build Tools
- **Xcode**
  - Xcode Caches (`~/Library/Caches/com.apple.dt.Xcode`)
  - DerivedData (`~/Library/Developer/Xcode/DerivedData`)
  - Archives (`~/Library/Developer/Xcode/Archives`)
  - Simulators (`~/Library/Developer/CoreSimulator/Caches`)

- **Android Studio**
  - Caches (`~/Library/Caches/Google/AndroidStudio*`)
  - Application Support caches

- **IntelliJ IDEA**
  - Caches (`~/Library/Caches/JetBrains/IntelliJIdea*`)
  - Application Support caches

- **Visual Studio Code**
  - Caches (`~/Library/Caches/com.microsoft.VSCode`)
  - CachedData (`~/Library/Application Support/Code/CachedData`)

- **JetBrains Toolbox**
  - Caches (`~/Library/Caches/JetBrains/Toolbox`)

### Package Managers
- **CocoaPods** (`~/Library/Caches/CocoaPods`)
- **Carthage** (`~/Library/Caches/org.carthage.CarthageKit`)
- **Swift Package Manager** (`~/Library/Caches/org.swift.swiftpm`)
- **Gradle** (`~/.gradle/caches`)
- **Maven** (`~/.m2/repository`)
- **npm** (`~/.npm`)
- **Yarn** (`~/Library/Caches/Yarn`)
- **pip** (`~/Library/Caches/pip`)
- **Homebrew** (`~/Library/Caches/Homebrew`)

## AI Agents Supported

- **Cursor**
  - Cache (`~/Library/Application Support/Cursor/Cache`)
  - CachedData (`~/Library/Application Support/Cursor/CachedData`)
  - App cache (`~/Library/Caches/com.todesktop.230313mzl4w4u92`)

- **GitHub Copilot**
  - Application Support (`~/Library/Application Support/GitHub Copilot`)
  - VS Code extensions

- **Codeium**
  - Application Support (`~/Library/Application Support/Codeium`)
  - Home directory cache (`~/.codeium`)

- **Tabnine**
  - Application Support (`~/Library/Application Support/TabNine`)
  - Home directory cache (`~/.tabnine`)

- **Kiro**
  - Cache directory (`~/.kiro/cache`)
  - Library cache (`~/Library/Caches/Kiro`)

- **Continue.dev** (`~/.continue`)
- **Aider** (`~/.aider`)
- **OpenAI CLI** (`~/.openai`)

## Implementation Details

### Core Changes

1. **CacheManager.swift**
   - Added `DeveloperTool` enum with 17 developer tools
   - Added `AIAgent` enum with 8 AI agents
   - Added `DeveloperCache` struct for developer tool cache metadata
   - Added `AIAgentCache` struct for AI agent cache metadata
   - Implemented `findDeveloperCaches()` method
   - Implemented `findAIAgentCaches()` method
   - Added wildcard path expansion for dynamic version directories

2. **StorageViewModel.swift**
   - Added `scanIncludeDeveloperCaches` property (default: true)
   - Added `scanIncludeAIAgentCaches` property (default: true)
   - Updated `startScan()` to include developer and AI agent cache paths

3. **ScanView.swift**
   - Added toggle for "Include developer tool caches"
   - Added toggle for "Include AI agent caches"

## Features

### Wildcard Path Support
The implementation supports wildcard patterns in paths (e.g., `AndroidStudio*`) to handle multiple versions of tools installed on the system.

### Size Calculation
Each cache location is scanned and its total size is calculated, allowing users to see exactly how much space each tool's cache is consuming.

### Safe Scanning
All cache locations are checked against the safe-list manager to ensure system-critical files are not flagged for deletion.

## User Experience

Users can now:
1. Enable/disable developer cache scanning in the scan configuration
2. Enable/disable AI agent cache scanning in the scan configuration
3. See detailed breakdown of cache sizes by tool/agent
4. Clean up specific developer tool or AI agent caches

## Performance Considerations

- Cache scanning runs on background threads to avoid blocking the UI
- Parallel scanning of multiple cache locations for faster results
- Wildcard path expansion is optimized to minimize file system operations
