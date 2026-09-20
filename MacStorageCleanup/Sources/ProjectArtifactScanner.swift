import Foundation
import os.log

/// Finds regenerable build output inside the user's own source tree.
///
/// This is the one scan that walks personal files rather than a cache directory, so it is
/// opt-in and confined to roots the user picked. Two guards keep it honest:
///
/// - A directory is only offered when a **project marker** sits beside it, so a folder
///   called `build` full of a user's own work is never proposed for deletion.
/// - Symlinks are never followed, so a link inside the chosen root cannot walk the scan
///   out into the rest of the disk.
struct ProjectArtifactScanner {
    let sizer: DirectorySizer
    let fileManager: FileManager
    private let logger = Logger(subsystem: "com.macstoragecleanup.core", category: "projectscan")

    init(sizer: DirectorySizer, fileManager: FileManager = .default) {
        self.sizer = sizer
        self.fileManager = fileManager
    }

    /// An artifact directory and what must sit beside it before we believe it is one.
    struct Artifact {
        let directoryName: String
        /// Sibling files that identify the parent as a real project of the right kind.
        /// Empty means the generic marker set is enough.
        let requiredSiblings: [String]
        let safety: CacheSafety
        let label: String
    }

    static let artifacts: [Artifact] = [
        Artifact(directoryName: "build", requiredSiblings: ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"], safety: .regenerates, label: "Gradle build output"),
        Artifact(directoryName: ".gradle", requiredSiblings: ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"], safety: .alwaysSafe, label: "Project Gradle state"),
        Artifact(directoryName: "DerivedData", requiredSiblings: [], safety: .regenerates, label: "DerivedData"),
        Artifact(directoryName: "node_modules", requiredSiblings: ["package.json"], safety: .regenerates, label: "node_modules"),
        Artifact(directoryName: ".build", requiredSiblings: ["Package.swift"], safety: .regenerates, label: "SwiftPM build output"),
        Artifact(directoryName: "Pods", requiredSiblings: ["Podfile.lock"], safety: .regenerates, label: "CocoaPods"),
        Artifact(directoryName: ".kotlin", requiredSiblings: [], safety: .alwaysSafe, label: "Kotlin session data"),
        Artifact(directoryName: "kotlin-js-store", requiredSiblings: [], safety: .regenerates, label: "Kotlin/JS store"),
        // NOT alwaysSafe: this holds breakpoints and *user-scoped* schemes
        // (`xcschemes/<name>.xcscheme`), which carry env vars, launch arguments and test
        // config, do not regenerate, and are gitignored — so there is no second copy.
        Artifact(directoryName: "xcuserdata", requiredSiblings: [], safety: .needsConfirmation, label: "Xcode user state (schemes, breakpoints)")
    ]

    /// Files that mark a directory as a project root. Nothing is offered without one.
    static let projectMarkers: Set<String> = [
        ".git", "build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts",
        "Package.swift", "package.json", "Podfile", "Podfile.lock", "pom.xml", "Cargo.toml"
    ]

    /// Directories that are themselves artifacts — once matched, never descended into.
    private var artifactNames: Set<String> {
        Set(Self.artifacts.map(\.directoryName))
    }

    /// Bundle-like directories with nothing reclaimable inside. `.xcodeproj` and
    /// `.xcworkspace` are deliberately absent: `xcuserdata` lives inside them.
    private static let opaqueBundleExtensions: Set<String> = [
        "app", "framework", "bundle", "xcassets", "xcframework",
        "playground", "photoslibrary", "musiclibrary", "tvlibrary", "lproj", "dSYM"
    ]

    /// Directories that carry `xcuserdata` and count as project markers in their own right.
    private static let projectBundleExtensions: Set<String> = ["xcodeproj", "xcworkspace"]

    func scan(root: URL, maxDepth: Int = 6, budget: TimeInterval = 60) -> [DeveloperCache] {
        guard fileManager.fileExists(atPath: root.path) else { return [] }

        let rootPath = root.standardizedFileURL.path
        let deadline = Date().addingTimeInterval(budget)
        var results: [DeveloperCache] = []

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            // No `.skipsPackageDescendants`: `xcuserdata` sits inside an `.xcodeproj`,
            // which the system treats as a package. Opaque bundles are skipped by name below.
            options: [],
            errorHandler: { _, _ in true }
        ) else { return [] }

        while let entry = enumerator.nextObject() as? URL {
            if Date() > deadline {
                logger.debug("Project artifact scan budget exceeded under \(root.path, privacy: .public)")
                break
            }

            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values?.isDirectory == true else { continue }

            // Never follow a symlink out of the chosen root.
            if values?.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            guard entry.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(rootPath) else {
                enumerator.skipDescendants()
                continue
            }

            if enumerator.level > maxDepth {
                enumerator.skipDescendants()
                continue
            }

            let name = entry.lastPathComponent
            guard artifactNames.contains(name) else {
                // .git and friends hold no build output and are enormous to walk, and an
                // opaque bundle is one shipped artifact rather than a tree to inspect.
                if name == ".git" || name == ".svn" || name == ".hg"
                    || Self.opaqueBundleExtensions.contains(entry.pathExtension) {
                    enumerator.skipDescendants()
                }
                continue
            }

            enumerator.skipDescendants()

            guard let artifact = Self.artifacts.first(where: { $0.directoryName == name }) else { continue }
            let parent = entry.deletingLastPathComponent()
            guard isProjectDirectory(parent, requiring: artifact.requiredSiblings) else { continue }

            let measured = sizer.size(of: entry)
            guard measured.bytes > 0 else { continue }

            // Module names repeat across projects ("shared", "app"), so the label is the
            // path relative to the chosen root — the only form that identifies it.
            let relativeParent = parent.standardizedFileURL.path.hasPrefix(rootPath + "/")
                ? String(parent.standardizedFileURL.path.dropFirst(rootPath.count + 1))
                : parent.lastPathComponent

            results.append(DeveloperCache(
                tool: .projectBuildArtifacts,
                cacheLocation: entry,
                size: measured.bytes,
                description: "\(relativeParent)/\(name) — \(artifact.label)",
                displayName: "\(relativeParent) · \(artifact.label)",
                safety: artifact.safety,
                measurement: measured.measurement,
                needsFullDiskAccess: measured.needsFullDiskAccess,
                groupHint: "Project Build Artifacts"
            ))
        }

        logger.debug("Found \(results.count, privacy: .public) project artifacts under \(root.path, privacy: .public)")
        return results
    }

    /// True when `directory` looks like a real project root. When the artifact names
    /// specific siblings (a `package.json` for `node_modules`), one of those must be
    /// present; otherwise any generic marker will do.
    private func isProjectDirectory(_ directory: URL, requiring siblings: [String]) -> Bool {
        // An `.xcodeproj` or `.xcworkspace` is itself proof of a project, and is the only
        // place `xcuserdata` ever appears.
        if siblings.isEmpty, Self.projectBundleExtensions.contains(directory.pathExtension) {
            return true
        }

        let required = siblings.isEmpty ? Self.projectMarkers : Set(siblings)
        return required.contains {
            fileManager.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
    }
}
