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
- **uv (Python)** (`~/.cache/uv`, or `$UV_CACHE_DIR` / `$XDG_CACHE_HOME/uv`) — cleared with `uv cache clean` when the `uv` binary is installed, otherwise removed directly
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

---

# v2 — Multi-version scanning

Implements `DEVELOPER_CACHE_SCAN_V2.md`. The headline change: **one row per version**, not
one total per tool, plus the metadata needed to decide which of those rows is safe.

## Measurement

`DirectorySizer` replaces the old recursive `attributesOfItem` walk.

| Change | Why |
|---|---|
| `.totalFileAllocatedSizeKey` instead of `.size` | Logical size wildly overstates reclaimable space for APFS clones and sparse files |
| Hidden entries included | The old `.skipsHiddenFiles` made everything inside `~/.gradle` and every dotfile in a cache invisible |
| `statfs` for mount points | `du` over `CoreSimulator/Volumes` took minutes; `statfs` answers in under a millisecond |
| `EPERM` surfaces as `needsFullDiskAccess` | "Mail: permission needed" beats "Mail: 0 B" |
| Per-measurement time budget | Exceeding it yields a `.partial` size (shown as `≥`) instead of stalling the scan |

## Safety model

`DeveloperCache` carries `version`, `isNewestVersion`, `referencedBy`, `scope`,
`reclaimMethod`, `safety` and `measurement`. A row is checked by default only when it is
`.alwaysSafe`, or `.regenerates` **and** superseded **and** unreferenced. Everything else
is an explicit user decision, taken either per row or with the group checkbox in the
candidates list, which selects or clears a whole heading at once and shows a mixed state
when only part of the group is ticked.

`ProjectReferenceIndex` supplies `referencedBy` by indexing the user's project roots for
`gradle-wrapper.properties` distribution URLs, `ndkVersion`, `buildToolsVersion`,
`ndk.dir` / `ANDROID_NDK_HOME` / `ANDROID_NDK_VERSION`, and Java toolchain declarations.
A stale-by-date rule is wrong for these: a project can pin an old NDK and never touch it.

## New scan coverage

Produced by `DeveloperCacheScanner`, which owns every tool marked `isScannerOwned`:

- **Simulator runtimes** — `/Library/Developer/CoreSimulator/Volumes/<runtime>`, sized by
  `statfs`, reclaimed with `simctl runtime delete`. A volume is skipped when its build is
  already reported as a downloaded asset, since the mount is a view of those same bytes.
- **Device support** — per device model and OS build, newest build per model kept.
- **Android SDK** — `ndk`, `system-images`, `build-tools`, `platforms`, `sources`,
  `extras`, per version, reclaimed with `sdkmanager --uninstall`. SDK root resolves
  `$ANDROID_HOME` → `$ANDROID_SDK_ROOT` → `~/Library/Android/sdk`.
- **AVDs** — `~/.android/avd/<name>.avd`, display name from `<name>.ini`, reclaimed with
  `avdmanager delete avd`.
- **Gradle** — `caches/<version>` split per version, `modules-2` / `build-cache-1` /
  `jars-*` separately, `wrapper/dists/<version>` cross-referenced against every wrapper
  file found, `.tmp` / `daemon` / `native` / `nodejs` / `yarn` as always-safe scratch,
  and `jdks` toolchains.
- **Kotlin/Native** — `~/.konan`, one row per prebuilt compiler version.
- **Android Studio DerivedData** — called out separately from the opaque Google cache blob
  (82% of it on the audited machine).
- **Xcode extras** — `CodingAssistant`, `Products`, duplicate `Xcode*.app` installs, and
  `CommandLineTools` (flagged only when Xcode.app is also present).
- **APFS local snapshots** — reported via `tmutil listlocalsnapshots`, purged with
  `tmutil thinlocalsnapshots`.
- **Per-project build artifacts** — opt-in, see below.

## Risk indicator

Every row and every group heading carries a traffic-light dot, explained by a legend above
the list. The dot is derived from `CacheSafety`, so it cannot drift from the rule that
decides the checkbox:

| Dot | Tier | Meaning |
|---|---|---|
| green | `.alwaysSafe` | Scratch data. Nothing is lost and nothing is downloaded again. |
| amber | `.regenerates` | Your tools rebuild or re-download it. Costs time, not work. |
| red | `.needsConfirmation` | Could remove a device, a scheme or an install; or needs admin. |

A path that could not be read reports red rather than green — an unmeasurable directory is
its own reason to look. A group heading shows the **riskiest** item under it, not an
average: a heading reading green while hiding one row that deletes an emulator would be
the single misleading light in the UI. Dots carry a contrasting ring so amber and green
stay distinguishable without relying on hue alone.

`.alwaysSafe` is a promise, not a vibe, and `testOnlyScratchDirectoriesClaimAlwaysSafe`
pins the set of project directories allowed to claim it. `xcuserdata` was moved out of it:
it holds breakpoints and *user-scoped* schemes (`xcschemes/<name>.xcscheme`) carrying env
vars, launch arguments and test config, which do not regenerate and are gitignored, so
there is no second copy.

## Scan coverage toggles

`scanIncludeDeveloperCaches` and `scanIncludeAIAgentCaches` are persisted preferences,
honoured by both the scan page and the cleanup page. They are noise controls, not
performance controls: a machine without Gradle or an Android SDK pays 0.0007 s for the
whole set of existence checks, because scan cost is proportional to what exists.

**The Chromium/Electron sweep is deliberately outside both toggles.** It lives in
`findApplicationDataCaches()`, separate from `findDeveloperCaches()`, and always runs:
its rows are Chrome, Slack and Spotify as much as Claude or VS Code, and for a
non-developer it is most of their reclaimable space. It sweeps every app under
`Application Support` plus each Chromium profile, summed over the standard cache
subpaths — never the app directory itself, since `Local Storage`, `IndexedDB` and config
hold real user state.

A few paths are claimed by both sweeps (`Code/CachedData` is a VS Code tool path *and* a
Chromium cache subpath). The overlap is resolved where rows are merged, in favour of the
developer row; with developer scanning off nothing is claimed and the generic row
survives, so the bytes are never hidden either way.

`ProjectReferenceIndex.build()` is skipped entirely when no versioned toolchain
(`~/.gradle`, an Android SDK, `~/.konan`) is installed — otherwise it would walk
`~/Documents` to match against nothing.

## Reclaim method

`CleanupEngine.toolReclaimCommand(for:)` maps a path to the command that owns it —
`simctl delete`, `simctl runtime delete`, `avdmanager delete avd`,
`sdkmanager --uninstall`, `brew cleanup --prune=all` — falling back to direct removal
only where that is safe. A mounted runtime volume never falls back: unmounting is
`simctl`'s job.

## Per-project build artifacts (opt-in)

Off unless the user adds folders under **Preferences › Cleanup › Project Build Artifacts**.
Scans for `build/`, `.gradle/`, `DerivedData/`, `node_modules/`, `.build/`, `Pods/`,
`.kotlin/`, `kotlin-js-store/` and `xcuserdata/`. Two guards: a directory is offered only
when a matching project file sits beside it (`package.json` for `node_modules`,
`Podfile.lock` for `Pods`, a build script for `build/`), and symlinks are never followed
out of the chosen root. Rows are labelled by their path relative to that root, since
module names repeat across projects.

These rows are offered but never pre-ticked: deleting them costs a cold rebuild in every
project. The group checkbox is how a user takes all of them in one click.
