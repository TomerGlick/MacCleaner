import Foundation
import os.log

/// Produces the developer cache entries that the generic path loop in `DefaultCacheManager`
/// cannot express.
///
/// Three things force a dedicated scanner:
///
/// - **Multi-version accumulation.** Ten NDK versions, four Gradle distributions and four
///   simulator runtimes each look like one path but are really N rows. Reporting one total
///   per tool hides exactly the thing the user needs to see.
/// - **Measurement strategy varies.** Simulator runtimes are mounted APFS volumes; walking
///   them takes minutes, `statfs` answers instantly. Local snapshots have no directory at all.
/// - **Reclaim method varies.** `simctl`, `avdmanager`, `sdkmanager` and `brew` keep their own
///   indexes; `rm -rf` leaves entries the tool then trips over.
struct DeveloperCacheScanner {
    let sizer: DirectorySizer
    let homeDir: String
    /// Roots for the opt-in per-project build artifact scan. Empty disables it.
    let projectScanRoots: [URL]
    let fileManager: FileManager
    private let logger = Logger(subsystem: "com.macstoragecleanup.core", category: "devscan")

    init(
        sizer: DirectorySizer,
        homeDir: String = NSHomeDirectory(),
        projectScanRoots: [URL] = [],
        fileManager: FileManager = .default
    ) {
        self.sizer = sizer
        self.homeDir = homeDir
        self.projectScanRoots = projectScanRoots
        self.fileManager = fileManager
    }

    /// Times each phase, so a slow scan can be attributed to a section rather than
    /// guessed at. Sizing cost is dominated by what actually exists on the machine.
    private func timed(_ name: String, _ work: () -> [DeveloperCache]) -> [DeveloperCache] {
        let start = Date()
        let rows = work()
        let elapsed = Date().timeIntervalSince(start)
        logger.debug("\(name, privacy: .public): \(rows.count, privacy: .public) rows in \(String(format: "%.2f", elapsed), privacy: .public)s")
        return rows
    }

    func scan() async -> [DeveloperCache] {
        var results: [DeveloperCache] = []

        // Indexing the user's source tree only pays for itself when there is a versioned
        // toolchain to match against. On a machine with no Gradle, SDK or Kotlin/Native
        // it is a pure walk of ~/Documents for nothing.
        let references: ProjectReferenceIndex
        if hasVersionedToolchains {
            let start = Date()
            references = ProjectReferenceIndex.build()
            logger.debug("references: \(references.totalReferenceCount, privacy: .public) in \(String(format: "%.2f", Date().timeIntervalSince(start)), privacy: .public)s")
        } else {
            references = ProjectReferenceIndex()
            logger.debug("references: skipped, no versioned toolchains installed")
        }

        results += timed("simulatorRuntimeVolumes", scanSimulatorRuntimeVolumes)
        results += timed("deviceSupport", scanDeviceSupport)
        results += timed("xcodeExtras", scanXcodeExtras)
        results += timed("androidSDK") { scanAndroidSDK(references: references) }
        results += timed("androidVirtualDevices", scanAndroidVirtualDevices)
        results += timed("gradle") { scanGradle(references: references) }
        results += timed("kotlinNative", scanKotlinNative)
        results += timed("androidStudioDerivedData", scanAndroidStudioDerivedData)
        results += timed("toolchainInstalls", scanToolchainInstalls)
        results += timed("localSnapshots", scanLocalSnapshots)
        results += timed("projectArtifacts", scanProjectArtifacts)

        logger.debug("Developer cache scanner produced \(results.count, privacy: .public) entries")
        return results
    }

    /// The Chromium/Electron cache sweep, deliberately **not** part of `scan()`.
    ///
    /// It lives in this file because that is where the sizing and safety machinery is,
    /// but its rows are Chrome, Slack, Spotify and Claude — the bulk of a non-developer's
    /// reclaimable space. Gating it behind a "developer caches" toggle would hide it from
    /// exactly the people it helps most, so it runs unconditionally.
    func scanApplicationData() async -> [DeveloperCache] {
        timed("electronAppData", scanElectronAppData)
    }

    /// Whether any tool that keeps one directory per version is installed. Decides
    /// whether a project reference index is worth building.
    private var hasVersionedToolchains: Bool {
        var roots = DeveloperTool.androidSDKRoots(homeDir: homeDir)
        roots += ["\(homeDir)/.gradle", "\(homeDir)/.konan"]
        return roots.contains { fileManager.fileExists(atPath: $0) }
    }

    // MARK: - Xcode simulators

    /// Simulator runtimes live on mounted APFS volumes. `du` over them exceeded 180 s per
    /// directory in the audit; `statfs` on the mount point returns used bytes immediately.
    private func scanSimulatorRuntimeVolumes() -> [DeveloperCache] {
        let root = URL(fileURLWithPath: "/Library/Developer/CoreSimulator/Volumes")
        guard let children = directoryChildren(of: root) else { return [] }

        let inUseBuilds = simctlRuntimeBuildsInUse()
        // A mounted volume is a *view* of its downloaded asset, not extra bytes on disk.
        // Where the asset is already reported, counting the volume too would double-count
        // the runtime — and statfs on the expanded volume overstates it besides.
        let assetBackedBuilds = downloadedRuntimeBuilds()

        return children.compactMap { child in
            // Directory names look like "iOS_23F77" or "watchOS_22R581".
            let name = child.lastPathComponent
            let parts = name.split(separator: "_", maxSplits: 1).map(String.init)
            let platform = parts.first ?? name
            let build = parts.count > 1 ? parts[1] : name
            guard !assetBackedBuilds.contains(build) else { return nil }

            let measured = sizer.size(of: child)
            guard measured.bytes > 0 else { return nil }

            let isInUse = inUseBuilds.contains(build)

            return DeveloperCache(
                tool: .simulatorRuntimeVolumes,
                cacheLocation: child,
                size: measured.bytes,
                description: "\(platform) runtime \(build)",
                displayName: "\(platform) \(build)",
                version: build,
                // A runtime no device references is the safe one to drop first.
                isNewestVersion: isInUse,
                scope: .system,
                reclaimMethod: .command("/usr/bin/xcrun", ["simctl", "runtime", "delete", build]),
                safety: .needsConfirmation,
                measurement: measured.measurement,
                needsFullDiskAccess: measured.needsFullDiskAccess,
                groupHint: "Simulator Runtimes"
            )
        }
    }

    /// Symbol caches per physical device and OS build. Xcode re-downloads them on the next
    /// device connect, so only the newest build per device model is worth keeping.
    private func scanDeviceSupport() -> [DeveloperCache] {
        var results: [DeveloperCache] = []

        for platform in ["iOS", "watchOS", "tvOS", "visionOS"] {
            let root = URL(fileURLWithPath: "\(homeDir)/Library/Developer/Xcode/\(platform) DeviceSupport")
            guard let children = directoryChildren(of: root) else { continue }

            // "iPhone14,5 18.2 (22C152)" -> model "iPhone14,5", version "18.2 (22C152)".
            // Entries without a model prefix group under the platform itself.
            var byModel: [String: [(url: URL, version: String)]] = [:]
            for child in children {
                let name = child.lastPathComponent
                let tokens = name.split(separator: " ").map(String.init)
                let versionTokenCount = tokens.last?.hasPrefix("(") == true ? 2 : 1
                let model = tokens.count > versionTokenCount
                    ? tokens.dropLast(versionTokenCount).joined(separator: " ")
                    : platform
                let version = tokens.suffix(versionTokenCount).joined(separator: " ")
                byModel[model, default: []].append((child, version))
            }

            for (model, entries) in byModel {
                let sorted = entries.sorted { $0.version.compare($1.version, options: .numeric) == .orderedDescending }
                for (index, entry) in sorted.enumerated() {
                    let measured = sizer.size(of: entry.url)
                    guard measured.bytes > 0 else { continue }

                    results.append(DeveloperCache(
                        tool: .xcodeDeviceSupport,
                        cacheLocation: entry.url,
                        size: measured.bytes,
                        description: "\(platform) DeviceSupport - \(entry.url.lastPathComponent)",
                        displayName: "\(model) · \(entry.version)",
                        version: entry.version,
                        isNewestVersion: index == 0,
                        safety: .regenerates,
                        measurement: measured.measurement,
                        needsFullDiskAccess: measured.needsFullDiskAccess,
                        groupHint: "\(platform) Device Support"
                    ))
                }
            }
        }

        return results
    }

    /// Xcode directories that accumulate quietly and are absent from the classic path list.
    private func scanXcodeExtras() -> [DeveloperCache] {
        let candidates: [(DeveloperTool, String, CacheSafety)] = [
            (.xcodeCodingAssistant, "Library/Developer/Xcode/CodingAssistant", .regenerates),
            (.xcodeProducts, "Library/Developer/Xcode/Products", .alwaysSafe)
        ]

        return candidates.compactMap { tool, relativePath, safety in
            let url = URL(fileURLWithPath: "\(homeDir)/\(relativePath)")
            let measured = sizer.size(of: url)
            guard measured.bytes > 0 else { return nil }

            return DeveloperCache(
                tool: tool,
                cacheLocation: url,
                size: measured.bytes,
                description: "\(tool.displayName) - \(url.lastPathComponent)",
                displayName: tool.displayName,
                safety: safety,
                measurement: measured.measurement,
                needsFullDiskAccess: measured.needsFullDiskAccess,
                groupHint: "Xcode"
            )
        }
    }

    // MARK: - Android SDK

    private func scanAndroidSDK(references: ProjectReferenceIndex) -> [DeveloperCache] {
        var results: [DeveloperCache] = []

        for root in DeveloperTool.androidSDKRoots(homeDir: homeDir).map({ URL(fileURLWithPath: $0) }) {
            let sdkManager = sdkManagerPath(sdkRoot: root)

            // NDK is the single largest Android consumer and the one where a
            // stale-by-date rule is outright wrong: a project can pin an old NDK and
            // never touch it. Reference hits decide, not mtime.
            results += versionedRows(
                in: root.appendingPathComponent("ndk"),
                tool: .androidNDK,
                safety: .regenerates,
                referenceKind: .androidNDK,
                references: references,
                groupHint: "Android SDK",
                packageID: { "ndk;\($0)" },
                sdkManager: sdkManager
            )

            results += versionedRows(
                in: root.appendingPathComponent("build-tools"),
                tool: .androidBuildTools,
                safety: .regenerates,
                referenceKind: .androidBuildTools,
                references: references,
                groupHint: "Android SDK",
                packageID: { "build-tools;\($0)" },
                sdkManager: sdkManager
            )

            results += versionedRows(
                in: root.appendingPathComponent("platforms"),
                tool: .androidPlatforms,
                safety: .regenerates,
                referenceKind: nil,
                references: references,
                groupHint: "Android SDK",
                packageID: { "platforms;\($0)" },
                sdkManager: sdkManager
            )

            results += versionedRows(
                in: root.appendingPathComponent("sources"),
                tool: .androidSources,
                // Re-downloaded by sdkmanager, so it costs time — not alwaysSafe, which
                // promises nothing is fetched again.
                safety: .regenerates,
                referenceKind: nil,
                references: references,
                groupHint: "Android SDK",
                packageID: { "sources;\($0)" },
                sdkManager: sdkManager
            )

            results += scanAndroidSystemImages(sdkRoot: root, sdkManager: sdkManager)

            let extras = root.appendingPathComponent("extras")
            let extrasSize = sizer.size(of: extras)
            if extrasSize.bytes > 0 {
                results.append(DeveloperCache(
                    tool: .androidExtras,
                    cacheLocation: extras,
                    size: extrasSize.bytes,
                    description: "Android SDK extras",
                    displayName: "SDK Extras",
                    safety: .regenerates,
                    measurement: extrasSize.measurement,
                    needsFullDiskAccess: extrasSize.needsFullDiskAccess,
                    groupHint: "Android SDK"
                ))
            }
        }

        return results
    }

    /// System images nest one level deeper than the other SDK components:
    /// `system-images/<api>/<vendor>/<abi>`.
    private func scanAndroidSystemImages(sdkRoot: URL, sdkManager: URL?) -> [DeveloperCache] {
        let root = sdkRoot.appendingPathComponent("system-images")
        guard let apiLevels = directoryChildren(of: root) else { return [] }

        var results: [DeveloperCache] = []
        let sortedAPIs = apiLevels.sorted {
            $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending
        }

        for (apiIndex, apiLevel) in sortedAPIs.enumerated() {
            guard let vendors = directoryChildren(of: apiLevel) else { continue }
            for vendor in vendors {
                guard let abis = directoryChildren(of: vendor) else { continue }
                for abi in abis {
                    let measured = sizer.size(of: abi)
                    guard measured.bytes > 0 else { continue }

                    let api = apiLevel.lastPathComponent
                    let packageID = "system-images;\(api);\(vendor.lastPathComponent);\(abi.lastPathComponent)"

                    results.append(DeveloperCache(
                        tool: .androidSystemImages,
                        cacheLocation: abi,
                        size: measured.bytes,
                        description: packageID,
                        displayName: "\(api) · \(vendor.lastPathComponent) · \(abi.lastPathComponent)",
                        version: api,
                        isNewestVersion: apiIndex == 0,
                        reclaimMethod: uninstallMethod(sdkManager: sdkManager, packageID: packageID),
                        safety: .regenerates,
                        measurement: measured.measurement,
                        needsFullDiskAccess: measured.needsFullDiskAccess,
                        groupHint: "Android SDK"
                    ))
                }
            }
        }

        return results
    }

    /// Emulator images. Deleting one loses a device definition, so these are never
    /// selected by default — `needsConfirmation` covers both the AVD and its snapshots.
    private func scanAndroidVirtualDevices() -> [DeveloperCache] {
        let root = URL(fileURLWithPath: "\(homeDir)/.android/avd")
        guard let children = directoryChildren(of: root) else { return [] }

        let avdManager = DeveloperTool.androidSDKRoots(homeDir: homeDir)
            .lazy
            .map { URL(fileURLWithPath: $0) }
            .compactMap { commandLineTool(named: "avdmanager", sdkRoot: $0) }
            .first

        return children.compactMap { child in
            guard child.pathExtension == "avd" else { return nil }
            let measured = sizer.size(of: child)
            guard measured.bytes > 0 else { return nil }

            let name = child.deletingPathExtension().lastPathComponent
            let label = avdDisplayName(forAVDNamed: name, in: root) ?? name

            return DeveloperCache(
                tool: .androidAVD,
                cacheLocation: child,
                size: measured.bytes,
                description: "Android emulator - \(name)",
                displayName: label,
                reclaimMethod: avdManager.map { .command($0.path, ["delete", "avd", "-n", name]) } ?? .removeItem,
                safety: .needsConfirmation,
                measurement: measured.measurement,
                needsFullDiskAccess: measured.needsFullDiskAccess,
                groupHint: "Android Emulators"
            )
        }
    }

    /// `<name>.ini` sits next to `<name>.avd` and carries the user-facing display name.
    private func avdDisplayName(forAVDNamed name: String, in root: URL) -> String? {
        let iniURL = root.appendingPathComponent("\(name).ini")
        guard let contents = try? String(contentsOf: iniURL, encoding: .utf8) else { return nil }

        for line in contents.split(separator: "\n") where line.hasPrefix("avd.ini.displayname=") {
            let value = line.dropFirst("avd.ini.displayname=".count).trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }
        return nil
    }

    // MARK: - Gradle

    /// `~/.gradle/caches` as one blob hides its composition. The per-version
    /// subdirectories are the dead weight; `modules-2` and `build-cache-1` regenerate.
    private func scanGradle(references: ProjectReferenceIndex) -> [DeveloperCache] {
        let gradleHome = URL(fileURLWithPath: "\(homeDir)/.gradle")
        guard fileManager.fileExists(atPath: gradleHome.path) else { return [] }

        var results: [DeveloperCache] = []
        let caches = gradleHome.appendingPathComponent("caches")

        if let children = directoryChildren(of: caches) {
            // A `caches/<n.n.n>` directory belongs to one Gradle version; everything else
            // in there (modules-2, build-cache-1, jars-N) is shared and version-agnostic.
            let versionDirs = children.filter { isVersionLike($0.lastPathComponent) }
            let sharedDirs = children.filter { !isVersionLike($0.lastPathComponent) }

            let sortedVersions = versionDirs.sorted {
                $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending
            }

            for (index, dir) in sortedVersions.enumerated() {
                let measured = sizer.size(of: dir)
                guard measured.bytes > 0 else { continue }

                let version = dir.lastPathComponent
                let referencedBy = references.references(kind: .gradleDistribution, version: version)

                results.append(DeveloperCache(
                    tool: .gradle,
                    cacheLocation: dir,
                    size: measured.bytes,
                    description: "Gradle \(version) cache",
                    displayName: "Gradle \(version) cache",
                    version: version,
                    isNewestVersion: index == 0,
                    referencedBy: referencedBy,
                    safety: .regenerates,
                    measurement: measured.measurement,
                    needsFullDiskAccess: measured.needsFullDiskAccess,
                    groupHint: "Gradle"
                ))
            }

            for dir in sharedDirs {
                let measured = sizer.size(of: dir)
                guard measured.bytes > 0 else { continue }

                results.append(DeveloperCache(
                    tool: .gradle,
                    cacheLocation: dir,
                    size: measured.bytes,
                    description: "Gradle \(dir.lastPathComponent)",
                    displayName: gradleSharedCacheLabel(dir.lastPathComponent),
                    safety: .regenerates,
                    measurement: measured.measurement,
                    needsFullDiskAccess: measured.needsFullDiskAccess,
                    groupHint: "Gradle"
                ))
            }
        }

        // Wrapper distributions: `dists/gradle-9.7.1-bin/<hash>/`.
        if let dists = directoryChildren(of: gradleHome.appendingPathComponent("wrapper/dists")) {
            let sorted = dists.sorted {
                $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending
            }
            for (index, dist) in sorted.enumerated() {
                let measured = sizer.size(of: dist)
                guard measured.bytes > 0 else { continue }

                let version = gradleVersion(fromDistributionName: dist.lastPathComponent)
                let referencedBy = version.map { references.references(kind: .gradleDistribution, version: $0) } ?? []

                results.append(DeveloperCache(
                    tool: .gradleWrapperDists,
                    cacheLocation: dist,
                    size: measured.bytes,
                    description: "Gradle distribution \(dist.lastPathComponent)",
                    displayName: version.map { "Gradle \($0) distribution" } ?? dist.lastPathComponent,
                    version: version,
                    isNewestVersion: index == 0,
                    referencedBy: referencedBy,
                    safety: .regenerates,
                    measurement: measured.measurement,
                    needsFullDiskAccess: measured.needsFullDiskAccess,
                    groupHint: "Gradle"
                ))
            }
        }

        // Scratch: always safe, no reference check needed.
        for relative in [".tmp", "daemon", "native", "nodejs", "yarn"] {
            let url = gradleHome.appendingPathComponent(relative)
            let measured = sizer.size(of: url)
            guard measured.bytes > 0 else { continue }

            results.append(DeveloperCache(
                tool: .gradleScratch,
                cacheLocation: url,
                size: measured.bytes,
                description: "Gradle \(relative)",
                displayName: "Gradle \(relative)",
                safety: .alwaysSafe,
                measurement: measured.measurement,
                needsFullDiskAccess: measured.needsFullDiskAccess,
                groupHint: "Gradle"
            ))
        }

        // Toolchain JDKs downloaded by Gradle's auto-provisioning.
        if let jdks = directoryChildren(of: gradleHome.appendingPathComponent("jdks")) {
            for jdk in jdks {
                let measured = sizer.size(of: jdk)
                guard measured.bytes > 0 else { continue }

                let major = javaMajorVersion(fromToolchainName: jdk.lastPathComponent)
                let referencedBy = major.map { references.references(kind: .javaToolchain, version: $0) } ?? []

                results.append(DeveloperCache(
                    tool: .gradleToolchains,
                    cacheLocation: jdk,
                    size: measured.bytes,
                    description: "Gradle toolchain JDK \(jdk.lastPathComponent)",
                    displayName: major.map { "Toolchain JDK \($0)" } ?? jdk.lastPathComponent,
                    version: major,
                    // A referenced toolchain is re-downloaded on next build; an
                    // unreferenced one is dead weight. Never default-selected either way.
                    referencedBy: referencedBy,
                    safety: .needsConfirmation,
                    measurement: measured.measurement,
                    needsFullDiskAccess: measured.needsFullDiskAccess,
                    groupHint: "Gradle"
                ))
            }
        }

        return results
    }

    private func gradleSharedCacheLabel(_ name: String) -> String {
        switch name {
        case "modules-2": return "Dependency jars (modules-2)"
        case "build-cache-1": return "Build cache"
        default: return name
        }
    }

    // MARK: - Kotlin / Native

    /// `~/.konan` accumulates one prebuilt compiler directory per Kotlin version, plus a
    /// shared `dependencies` tree. Relevant to every Kotlin Multiplatform user.
    private func scanKotlinNative() -> [DeveloperCache] {
        let root = URL(fileURLWithPath: "\(homeDir)/.konan")
        guard let children = directoryChildren(of: root) else { return [] }

        let compilers = children.filter { $0.lastPathComponent.hasPrefix("kotlin-native") }
        let sortedCompilers = compilers.sorted {
            $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending
        }

        var results: [DeveloperCache] = []

        for (index, child) in sortedCompilers.enumerated() {
            let measured = sizer.size(of: child)
            guard measured.bytes > 0 else { continue }

            results.append(DeveloperCache(
                tool: .kotlinNative,
                cacheLocation: child,
                size: measured.bytes,
                description: "Kotlin/Native \(child.lastPathComponent)",
                displayName: child.lastPathComponent,
                version: child.lastPathComponent,
                isNewestVersion: index == 0,
                safety: .regenerates,
                measurement: measured.measurement,
                needsFullDiskAccess: measured.needsFullDiskAccess,
                groupHint: "Kotlin/Native"
            ))
        }

        for child in children where !child.lastPathComponent.hasPrefix("kotlin-native") {
            let measured = sizer.size(of: child)
            guard measured.bytes > 0 else { continue }

            results.append(DeveloperCache(
                tool: .kotlinNative,
                cacheLocation: child,
                size: measured.bytes,
                description: "Kotlin/Native \(child.lastPathComponent)",
                displayName: "Kotlin/Native \(child.lastPathComponent)",
                safety: .regenerates,
                measurement: measured.measurement,
                needsFullDiskAccess: measured.needsFullDiskAccess,
                groupHint: "Kotlin/Native"
            ))
        }

        return results
    }

    // MARK: - Electron / Chromium app data

    /// Well-known Chromium cache subdirectories. Everything here is rebuilt on demand.
    /// Deliberately excludes `Local Storage`, `IndexedDB`, `Session Storage` and config
    /// files, which hold real user state.
    static let electronCacheSubpaths = [
        "Cache",
        "Code Cache",
        "GPUCache",
        "DawnCache",
        "DawnGraphiteCache",
        "DawnWebGPUCache",
        "ShaderCache",
        "GrShaderCache",
        "Service Worker/CacheStorage",
        "CachedData",
        "CachedExtensions",
        "CachedProfilesData",
        "logs",
        "Crashpad"
    ]

    /// Rather than enumerating known apps, sweep every app under Application Support for
    /// the standard Chromium cache subpaths. The audited machine's largest entries —
    /// Google at 14 GB, Claude at 11 GB — were not on any hand-written list.
    ///
    /// One row per (app, subpath), never the app directory itself.
    private func scanElectronAppData() -> [DeveloperCache] {
        let root = URL(fileURLWithPath: "\(homeDir)/Library/Application Support")
        guard let apps = directoryChildren(of: root) else { return [] }

        // Below this, a row costs the user more attention than it saves space.
        let minimumRowSize: Int64 = 10_000_000
        var results: [DeveloperCache] = []

        for app in apps {
            let appName = app.lastPathComponent

            for subpath in Self.electronCacheSubpaths {
                // A profile-based app nests these under Default/, Profile 1/, etc.
                for candidate in electronCandidates(in: app, subpath: subpath) {
                    let measured = sizer.size(of: candidate)
                    guard measured.bytes >= minimumRowSize || measured.needsFullDiskAccess else { continue }

                    let relative = candidate.path.replacingOccurrences(of: app.path + "/", with: "")

                    results.append(DeveloperCache(
                        tool: .electronAppData,
                        cacheLocation: candidate,
                        size: measured.bytes,
                        description: "\(appName) - \(relative)",
                        displayName: "\(appName) · \(relative)",
                        safety: .alwaysSafe,
                        measurement: measured.measurement,
                        needsFullDiskAccess: measured.needsFullDiskAccess,
                        groupHint: appName
                    ))
                }
            }
        }

        return results
    }

    /// The cache subpath at the app root, plus the same subpath inside each Chromium profile.
    private func electronCandidates(in app: URL, subpath: String) -> [URL] {
        var candidates: [URL] = []

        let direct = app.appendingPathComponent(subpath)
        if fileManager.fileExists(atPath: direct.path) {
            candidates.append(direct)
        }

        for profile in directoryChildren(of: app) ?? [] {
            let name = profile.lastPathComponent
            guard name == "Default" || name.hasPrefix("Profile ") else { continue }
            let nested = profile.appendingPathComponent(subpath)
            if fileManager.fileExists(atPath: nested.path) {
                candidates.append(nested)
            }
        }

        return candidates
    }

    /// Android Studio's DerivedData is exactly as disposable as Xcode's, but it sits
    /// under `~/Library/Caches/Google/AndroidStudio*`, which the generic wildcard rule
    /// reports as one opaque blob — on the audited machine it was 82% of that blob.
    private func scanAndroidStudioDerivedData() -> [DeveloperCache] {
        let cachesRoot = URL(fileURLWithPath: "\(homeDir)/Library/Caches/Google")
        guard let versions = directoryChildren(of: cachesRoot) else { return [] }

        return versions.compactMap { version in
            guard version.lastPathComponent.hasPrefix("AndroidStudio") else { return nil }
            let derived = version.appendingPathComponent("DerivedData")
            let measured = sizer.size(of: derived)
            guard measured.bytes > 0 else { return nil }

            return DeveloperCache(
                tool: .androidStudio,
                cacheLocation: derived,
                size: measured.bytes,
                description: "\(version.lastPathComponent) DerivedData",
                displayName: "\(version.lastPathComponent) DerivedData",
                safety: .regenerates,
                measurement: measured.measurement,
                needsFullDiskAccess: measured.needsFullDiskAccess,
                groupHint: "Android Studio"
            )
        }
    }

    // MARK: - Toolchain installs

    /// Command Line Tools duplicate what Xcode.app already ships, and duplicate Xcode
    /// installs sit side by side for years. Both are flagged, never auto-selected.
    private func scanToolchainInstalls() -> [DeveloperCache] {
        var results: [DeveloperCache] = []

        let xcodeApps = (directoryChildren(of: URL(fileURLWithPath: "/Applications")) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("Xcode") && $0.pathExtension == "app" }

        let commandLineTools = URL(fileURLWithPath: "/Library/Developer/CommandLineTools")
        if !xcodeApps.isEmpty {
            let measured = sizer.size(of: commandLineTools)
            if measured.bytes > 0 {
                results.append(DeveloperCache(
                    tool: .commandLineTools,
                    cacheLocation: commandLineTools,
                    size: measured.bytes,
                    description: "Command Line Tools (Xcode.app is also installed)",
                    displayName: "Command Line Tools",
                    scope: .system,
                    safety: .needsConfirmation,
                    measurement: measured.measurement,
                    needsFullDiskAccess: measured.needsFullDiskAccess,
                    groupHint: "Xcode"
                ))
            }
        }

        if xcodeApps.count > 1 {
            let sorted = xcodeApps.sorted {
                (xcodeVersion(of: $0) ?? "").compare(xcodeVersion(of: $1) ?? "", options: .numeric) == .orderedDescending
            }
            for (index, app) in sorted.enumerated() {
                let measured = sizer.size(of: app)
                guard measured.bytes > 0 else { continue }
                let version = xcodeVersion(of: app)

                results.append(DeveloperCache(
                    tool: .xcode,
                    cacheLocation: app,
                    size: measured.bytes,
                    description: "Duplicate Xcode install - \(app.lastPathComponent)",
                    displayName: version.map { "\(app.lastPathComponent) (\($0))" } ?? app.lastPathComponent,
                    version: version,
                    isNewestVersion: index == 0,
                    scope: .system,
                    safety: .needsConfirmation,
                    measurement: measured.measurement,
                    needsFullDiskAccess: measured.needsFullDiskAccess,
                    groupHint: "Xcode Installs"
                ))
            }
        }

        return results
    }

    private func xcodeVersion(of app: URL) -> String? {
        let plistURL = app.appendingPathComponent("Contents/Info.plist")
        guard let data = fileManager.contents(atPath: plistURL.path),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        return plist["CFBundleShortVersionString"] as? String
    }

    // MARK: - APFS local snapshots

    /// The standard explanation for "Finder says the disk is full but nothing adds up".
    /// Two lines of check that save the user an hour of confusion.
    private func scanLocalSnapshots() -> [DeveloperCache] {
        guard let output = runCommand("/usr/bin/tmutil", ["listlocalsnapshots", "/"]) else { return [] }

        let snapshots = output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("com.apple.TimeMachine.") }

        guard !snapshots.isEmpty else { return [] }

        // tmutil does not report per-snapshot bytes; purged space is only known after the
        // fact. Reported as tool-sourced with an unknown size rather than a fake number.
        return [DeveloperCache(
            tool: .localSnapshots,
            cacheLocation: URL(fileURLWithPath: "/"),
            size: 0,
            description: "\(snapshots.count) APFS local snapshot(s) — size reported by tmutil only after thinning",
            displayName: "\(snapshots.count) local snapshot(s)",
            scope: .system,
            reclaimMethod: .command("/usr/bin/tmutil", ["thinlocalsnapshots", "/", "21474836480", "4"]),
            safety: .needsConfirmation,
            measurement: .toolReported,
            groupHint: "APFS Snapshots"
        )]
    }

    // MARK: - Per-project build artifacts

    /// Regenerable output inside the user's own source tree. Opt-in only, and only under
    /// roots the user chose — this walks personal files, unlike everything else here.
    private func scanProjectArtifacts() -> [DeveloperCache] {
        guard !projectScanRoots.isEmpty else { return [] }

        var results: [DeveloperCache] = []
        for root in projectScanRoots {
            results += ProjectArtifactScanner(sizer: sizer, fileManager: fileManager).scan(root: root)
        }
        return results
    }

    // MARK: - Shared helpers

    /// Immediate subdirectories, or nil when the directory does not exist or is unreadable.
    private func directoryChildren(of url: URL) -> [URL]? {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { return nil }

        return contents.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }
    }

    /// One row per version directory under `root`, newest first.
    private func versionedRows(
        in root: URL,
        tool: DeveloperTool,
        safety: CacheSafety,
        referenceKind: ProjectReferenceKind?,
        references: ProjectReferenceIndex,
        groupHint: String,
        packageID: (String) -> String,
        sdkManager: URL?
    ) -> [DeveloperCache] {
        guard let children = directoryChildren(of: root) else { return [] }

        let sorted = children.sorted {
            $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending
        }

        return sorted.enumerated().compactMap { index, child in
            let measured = sizer.size(of: child)
            guard measured.bytes > 0 else { return nil }

            let version = child.lastPathComponent
            let referencedBy = referenceKind.map { references.references(kind: $0, version: version) } ?? []

            return DeveloperCache(
                tool: tool,
                cacheLocation: child,
                size: measured.bytes,
                description: "\(tool.displayName) \(version)",
                displayName: "\(tool.displayName) \(version)",
                version: version,
                isNewestVersion: index == 0,
                referencedBy: referencedBy,
                reclaimMethod: uninstallMethod(sdkManager: sdkManager, packageID: packageID(version)),
                safety: safety,
                measurement: measured.measurement,
                needsFullDiskAccess: measured.needsFullDiskAccess,
                groupHint: groupHint
            )
        }
    }

    /// Prefer `sdkmanager --uninstall` so the SDK's package index stays consistent.
    private func uninstallMethod(sdkManager: URL?, packageID: String) -> ReclaimMethod {
        guard let sdkManager else { return .removeItem }
        return .command(sdkManager.path, ["--uninstall", packageID])
    }

    private func sdkManagerPath(sdkRoot: URL) -> URL? {
        commandLineTool(named: "sdkmanager", sdkRoot: sdkRoot)
    }

    private func commandLineTool(named name: String, sdkRoot: URL) -> URL? {
        let candidates = [
            sdkRoot.appendingPathComponent("cmdline-tools/latest/bin/\(name)"),
            sdkRoot.appendingPathComponent("tools/bin/\(name)")
        ]

        if let versioned = directoryChildren(of: sdkRoot.appendingPathComponent("cmdline-tools")) {
            let extra = versioned.map { $0.appendingPathComponent("bin/\(name)") }
            return (candidates + extra).first { fileManager.isExecutableFile(atPath: $0.path) }
        }

        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    /// Builds of every downloaded simulator runtime asset. These are reported by the
    /// generic path loop, so anything listed here must not be reported again as a volume.
    func downloadedRuntimeBuilds() -> Set<String> {
        let roots = [
            "/System/Library/AssetsV2/com_apple_MobileAsset_iOSSimulatorRuntime",
            "/Library/Developer/CoreSimulator/Profiles/Runtimes"
        ]

        var builds: Set<String> = []
        for root in roots {
            guard let contents = try? fileManager.contentsOfDirectory(atPath: root) else { continue }
            for item in contents where item.hasSuffix(".asset") || item.hasSuffix(".simruntime") {
                let plistPath = "\(root)/\(item)/Info.plist"
                guard let data = fileManager.contents(atPath: plistPath),
                      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                    continue
                }

                if let properties = plist["MobileAssetProperties"] as? [String: Any],
                   let build = properties["Build"] as? String {
                    builds.insert(build)
                }
                if let build = plist["CFBundleVersion"] as? String {
                    builds.insert(build)
                }
            }
        }

        return builds
    }

    /// Simulator runtime builds that `simctl` still knows about.
    private func simctlRuntimeBuildsInUse() -> Set<String> {
        guard let output = runCommand("/usr/bin/xcrun", ["simctl", "runtime", "list"]) else { return [] }

        var builds: Set<String> = []
        // Lines look like: "iOS 26.5 (23F77) - <uuid> (Ready)"
        for match in output.split(separator: "\n") {
            guard let open = match.firstIndex(of: "("), let close = match.firstIndex(of: ")"), open < close else { continue }
            let build = match[match.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
            if !build.isEmpty { builds.insert(build) }
        }
        return builds
    }

    private func isVersionLike(_ name: String) -> Bool {
        guard let first = name.first else { return false }
        return first.isNumber && name.contains(".")
    }

    /// "gradle-9.7.1-bin" -> "9.7.1"
    private func gradleVersion(fromDistributionName name: String) -> String? {
        let parts = name.split(separator: "-")
        guard parts.count >= 2, let version = parts.dropFirst().first(where: { $0.first?.isNumber == true }) else {
            return nil
        }
        return String(version)
    }

    /// "azul_systems__inc_-21.0.3-aarch64-os_x" -> "21"
    private func javaMajorVersion(fromToolchainName name: String) -> String? {
        for part in name.split(separator: "-") where part.first?.isNumber == true {
            return String(part.split(separator: ".").first ?? part)
        }
        return nil
    }

    /// Run a short-lived tool and capture stdout. Returns nil when it cannot be run.
    private func runCommand(_ executable: String, _ arguments: [String]) -> String? {
        guard fileManager.isExecutableFile(atPath: executable) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            logger.debug("Could not run \(executable, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
