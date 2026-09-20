# Developer Cache Scanning — v2 Gap Analysis

Spec for extending `CacheManager.swift` (`DeveloperTool` enum, `findDeveloperCaches()`).
Derived from a real audit of a 461 GB MacBook Air at 98% full (451 GB used).

## Headline finding

The current implementation covers the *well-known* cache paths but misses the *large* ones.
Of ~198 GB of developer cache on the audited machine, the existing scanner would have found
roughly 60 GB. The rest sits in five blind spots below.

**The dominant pattern is multi-version accumulation**: 10 NDK versions, 4 Gradle
distributions, 4 simulator runtimes, 16 loaded simulators, 2 Xcode.app installs. No single
path is "wrong" — the tool keeps every version it ever downloaded. A scanner that reports
one total per tool hides this. Report per-version rows and mark all but the newest as
candidates.

---

## Blind spot 1 — Xcode simulators (measured: 113 GB)

`CoreSimulator/Caches` is already scanned. On the audited machine it was **0 bytes**.
The real space is in three other places.

| Path | Measured | Scope | Notes |
|---|---|---|---|
| `~/Library/Developer/CoreSimulator/Devices/<UUID>` | **46 GB** | user | 76 devices; 16 held 1.3–6.3 GB, 60 held 18 MB |
| `/Library/Developer/CoreSimulator/Volumes/<runtime>` | **54 GB** | **system** | iOS 22F77 19 GB, iOS 23F77 17 GB, watchOS 22R581 9.9 GB, watchOS 23T570 8.3 GB |
| `~/Library/Developer/Xcode/iOS DeviceSupport/<device> <ver>` | **13 GB** | user | Symbol caches per physical device + OS build |

### Devices
Read `<UUID>/device.plist` for `name` and `runtime` — never show a bare UUID.
Flag as stale when the runtime is not in `xcrun simctl list runtimes` (orphaned), or when
`.../data/` has not been modified in N days.

Prefer `xcrun simctl delete <UUID>` over `rm -rf`, so CoreSimulator's index stays consistent.
`xcrun simctl delete unavailable` is the safe bulk action.

### Runtimes — needs a different measurement strategy
These are mounted APFS volumes. **`du` on them takes minutes and will hang a scan.**
Use `statfs` / `df` on the mount point instead — it returns the used-bytes instantly:

```
/Library/Developer/CoreSimulator/Volumes/iOS_23F77  →  17 GB used, returned in <50 ms
```

Or enumerate via `xcrun simctl runtime list -j`, which gives build, version, state and
whether any device uses it. Delete with `xcrun simctl runtime delete <build>` — never `rm`.

This is system-scope, so it needs admin rights. Worth it: it was the single largest
reclaimable block on the machine.

### iOS DeviceSupport
Plain directories, safe to delete. Xcode re-downloads symbols on next device connect.
Each entry is named `<model> <version> (<build>)` — group by model and keep only the newest
build per device.

---

## Blind spot 2 — Android SDK (measured: 67 GB)

Currently only `~/.gradle/caches` and the Android Studio cache are covered. The SDK itself
is untouched and was the second-largest consumer.

| Path | Measured | Pattern |
|---|---|---|
| `~/Library/Android/sdk/ndk/<version>` | **29 GB** | **10 versions × ~2.9 GB** |
| `~/Library/Android/sdk/system-images/<api>/<variant>` | **8.7 GB** | per API level × variant |
| `~/Library/Android/sdk/build-tools/<version>` | **2.0 GB** | 10+ versions × ~190 MB, incl. `-rc1`…`-rc5` |
| `~/Library/Android/sdk/platforms/<api>` | 833 MB | per API level |
| `~/Library/Android/sdk/sources/<api>` | 715 MB | optional, safe |
| `~/Library/Android/sdk/extras` | 780 MB | |
| `~/Library/Android/sdk/emulator` | 1.2 GB | keep |
| `~/.android/avd/<name>.avd` | **23 GB** | 2 AVDs: 13 GB + 9.5 GB |

The SDK path is not fixed. Resolve in order: `$ANDROID_HOME` → `$ANDROID_SDK_ROOT` →
`~/Library/Android/sdk`.

### NDK — needs reference detection, not a date heuristic
A stale-by-mtime rule is wrong here: a project can pin an old NDK. Before offering an NDK
version for deletion, grep the user's project roots for references:

- `ndkVersion` in `build.gradle` / `build.gradle.kts`
- `ndk.dir` in `local.properties`
- `ANDROID_NDK_VERSION` / `ANDROID_NDK_HOME` in CI configs and `.env`

Only offer versions with zero hits. Show the hits for the ones you keep — that is the
reassurance that makes the user click delete.

Same idea for `build-tools`: `buildToolsVersion` declarations. Release-candidate builds
(`36.0.0-rc1` … `-rc5`) are near-always safe once the matching final exists.

### AVDs
`<name>.avd/userdata-qcow2` and the snapshot files dominate. Offer two tiers:
**wipe data** (reclaims most of it, keeps the device definition) and **delete AVD**.
Use `avdmanager delete avd -n <name>`; parse `<name>.ini` for the display name.

---

## Blind spot 3 — Gradle, per version (measured: 32 GB)

`~/.gradle/caches` is scanned as one blob. Break it out — the composition is what matters:

| Subpath | Measured | Rule |
|---|---|---|
| `~/.gradle/caches/<gradle-version>/` | **19 GB** (9.7.1) + 2.2 (9.4.1) + 1.0 (9.7.0) + 692 MB (9.2.1) | Keep newest; older versions are dead weight once no wrapper references them |
| `~/.gradle/caches/modules-2` | 3.9 GB | Dependency jars; safe, re-downloads |
| `~/.gradle/caches/build-cache-1` | 1.9 GB | Safe; prunes itself but slowly |
| `~/.gradle/caches/jars-9` | 334 MB | Safe |
| `~/.gradle/.tmp` | 486 MB | **Always safe** |
| `~/.gradle/daemon` | — | Logs; safe |
| `~/.gradle/wrapper/dists/<version>` | — | Match against `gradle-wrapper.properties` across projects |
| `~/.gradle/jdks` | — | Toolchain JDKs; check against `foojay`/toolchain declarations |
| `~/.gradle/native`, `~/.gradle/nodejs`, `~/.gradle/yarn` | — | Safe |

Cross-reference `caches/<version>` and `wrapper/dists/<version>` against every
`gradle/wrapper/gradle-wrapper.properties` found in the user's project roots. A version
referenced by no wrapper is unambiguously deletable.

---

## Blind spot 4 — Kotlin / KMP toolchains (measured: 6 GB)

Absent from the current list entirely, and relevant to any Kotlin Multiplatform user:

| Path | Measured |
|---|---|
| `~/.konan/` (Kotlin/Native compilers + dependencies, per version) | **6.1 GB** |
| `~/.gradle/caches/.../kotlin-dsl` | — |
| `<project>/.kotlin`, `<project>/build` | see blind spot 6 |

Same multi-version rule: `~/.konan/kotlin-native-prebuilt-macos-*` accumulates one directory
per Kotlin version.

---

## Blind spot 5 — Electron / Chromium app data (measured: 31 GB)

`~/Library/Application Support` is treated as a lookup root for specific tools, but the
largest entries on the audited machine were not in the list:

| Path | Measured |
|---|---|
| `~/Library/Application Support/Google` | **14 GB** |
| `~/Library/Application Support/Claude` | **11 GB** |
| `~/Library/Caches/Google/AndroidStudio<ver>/DerivedData` | **14 GB** (inside the 17 GB AS cache) |
| `~/Library/Application Support/Garmin` | 2.1 GB |
| `~/Library/Application Support/Figma` | 1.6 GB |

Rather than enumerating apps, add a **generic Electron sweep**: for every
`~/Library/Application Support/<App>/`, sum these well-known subpaths and offer them as one
safe row per app —

```
Cache/  Code Cache/  GPUCache/  DawnCache/  ShaderCache/
Service Worker/CacheStorage/  CachedData/  logs/  Crashpad/
```

Never offer the app directory itself — `Local Storage`, `IndexedDB` and `*.json` config hold
real user state.

Note the Android Studio one specifically: `AndroidStudio*/DerivedData` is 82% of the AS cache
and is exactly as disposable as Xcode's DerivedData, but under a Google path the current
wildcard rule treats as one opaque blob.

---

## Blind spot 6 — Per-project build artifacts (measured: 32 GB)

The user's own source tree held 32 GB across 12 projects (7.2, 6.0, 5.1, 4.2, 3.8 GB …),
almost all of it regenerable. Worth a separate opt-in scan mode with a user-chosen root:

| Directory | Notes |
|---|---|
| `build/`, `*/build/` | Gradle output |
| `.gradle/` (project-local) | |
| `DerivedData/` (project-local) | |
| `node_modules/` | Offer only when `package.json` is present |
| `.build/` | SwiftPM |
| `Pods/` | Only when `Podfile.lock` is present |
| `.kotlin/`, `kotlin-js-store/` | |
| `xcuserdata/` | |

Guard hard: require a `.git`, `build.gradle*`, `Package.swift`, `*.xcodeproj` or
`package.json` sibling before offering a directory, and never follow symlinks out of the
chosen root.

---

## Smaller additions worth including

| Path | Measured | Note |
|---|---|---|
| `~/Library/Developer/Xcode/CodingAssistant` | 893 MB | New in Xcode 26; not in the current list |
| `~/Library/Developer/Xcode/Products` | 44 MB | Safe |
| `~/Library/Developer/Xcode/.derived-data-log-*` | — | Safe |
| `~/Library/Caches/org.swift.swiftpm` | 1.1 GB | Already listed — confirmed material |
| `~/Library/Developer/CoreSimulator/Devices/../Temp` | — | Always safe |
| `/opt/homebrew` + `~/Library/Caches/Homebrew` | 3.0 GB | `brew cleanup --prune=all` |
| `/Library/Developer/CommandLineTools` | 2.6 GB | Flag only if Xcode.app is also present |
| Duplicate app installs | — | `Xcode.app` 4.1 GB **and** `Xcode beta.app` 3.7 GB |

---

## Implementation notes from the audit

**1. `du` is the wrong tool for several of these.** Recursive sizing over
`CoreSimulator/Volumes` and `Application Support` exceeded 180 s per directory. Use
`statfs` for anything that is a mount point, and prefer `NSFileManager`'s
`enumerator(at:includingPropertiesForKeys: [.totalFileAllocatedSizeKey])` with
`.skipsHiddenFiles = false` over shelling out. Report incrementally so the UI can show
partial results.

**2. Report allocated size, not logical size.** APFS clones and sparse files (simulator
disk images especially) make logical sizes wildly overstate reclaimable space. Use
`.totalFileAllocatedSizeKey`.

**3. Some paths are unreadable and that is not an error.** `~/Library/Application Support`
subpaths, Mail, Messages, Safari and `~/.Trash` are TCC-protected and silently return 0 or
`EPERM` without Full Disk Access. Surface this as a distinct "needs Full Disk Access" state
in the UI rather than reporting 0 bytes — a cleaner that says "Mail: 0 B" is worse than one
that says "Mail: permission needed".

**4. Prefer the tool's own delete command over `rm -rf`** wherever one exists —
`simctl delete`, `simctl runtime delete`, `avdmanager delete avd`, `sdkmanager --uninstall`,
`brew cleanup`, `npm cache clean --force`. They keep the tool's internal index consistent;
`rm -rf` leaves phantom entries that the IDE then re-creates or errors on.

**5. Check APFS local snapshots and report them separately.** `tmutil listlocalsnapshots /`
is the standard explanation for "Finder says full but nothing adds up". It was empty on the
audited machine, but it is a two-line check that saves users an hour. Purge with
`tmutil thinlocalsnapshots / <bytes> 4`.

---

## Suggested API shape

Extend the existing `DeveloperCache` struct with what the audit showed is needed to make a
delete decision safely:

```swift
struct DeveloperCache {
    // existing: tool, path, size

    var displayName: String          // "iPhone 17 Pro · iOS 26.5", not a UUID
    var version: String?             // for multi-version grouping
    var isNewestVersion: Bool        // drives default selection
    var referencedBy: [URL]          // project files that pin this version
    var scope: Scope                 // .user | .system  (system needs admin)
    var reclaimMethod: ReclaimMethod // .removeItem | .command(String, [String])
    var safety: Safety               // .alwaysSafe | .regenerates | .needsConfirmation
    var measurement: Measurement     // .enumerated | .statfs | .toolReported
}
```

Default-select `safety == .alwaysSafe` plus `.regenerates` where `isNewestVersion == false`
and `referencedBy.isEmpty`. Leave everything else unchecked.

---

## Validation target

Running against the audited machine, a correct v2 implementation should surface roughly:

- ~113 GB simulators (46 devices + 54 runtimes + 13 device support)
- ~67 GB Android SDK and AVDs
- ~32 GB Gradle
- ~31 GB Electron/app-support caches
- ~6 GB Kotlin/Native
- ~32 GB project build artifacts (opt-in mode)

Use those as fixture expectations. The current implementation finds about a third of it.
