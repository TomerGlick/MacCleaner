import Foundation

struct CleanupCategorizationOptions {
    let largeFileThresholdBytes: Int64
    let oldFileThresholdSeconds: TimeInterval
    let excludeProtectedOldFiles: Bool

    init(
        largeFileThresholdBytes: Int64,
        oldFileThresholdSeconds: TimeInterval,
        excludeProtectedOldFiles: Bool = false
    ) {
        self.largeFileThresholdBytes = largeFileThresholdBytes
        self.oldFileThresholdSeconds = oldFileThresholdSeconds
        self.excludeProtectedOldFiles = excludeProtectedOldFiles
    }

    init(preferences: UserPreferences, excludeProtectedOldFiles: Bool = false) {
        self.init(
            largeFileThresholdBytes: Int64(preferences.largeFileSizeThresholdMB) * 1024 * 1024,
            oldFileThresholdSeconds: TimeInterval(preferences.oldFileThresholdDays) * 24 * 60 * 60,
            excludeProtectedOldFiles: excludeProtectedOldFiles
        )
    }
}

enum CleanupCategorizer {
    static func categorize(
        file: FileMetadata,
        options: CleanupCategorizationOptions,
        safeListManager: SafeListManager? = nil,
        now: Date = Date()
    ) -> Set<CleanupCategory> {
        var categories = Set<CleanupCategory>()

        let path = file.url.path
        let pathLower = path.lowercased()
        let ext = file.url.pathExtension.lowercased()

        if pathLower.contains("/library/caches/") {
            if pathLower.contains("/system/library/caches/") {
                categories.insert(.systemCaches)
            } else if pathLower.contains("/library/caches/com.apple.safari") ||
                        pathLower.contains("/library/caches/google/chrome") ||
                        pathLower.contains("/library/caches/firefox") ||
                        pathLower.contains("/library/caches/microsoft edge") {
                categories.insert(.browserCaches)
            } else {
                categories.insert(.applicationCaches)
            }
        }

        if pathLower.contains("/logs/") || pathLower.contains("/log/") ||
           pathLower.contains("/var/log/") {
            categories.insert(.logFiles)
        }

        if pathLower.contains("/tmp") || pathLower.contains("/temp") ||
           pathLower.hasPrefix("/tmp/") || pathLower.hasPrefix("/var/tmp/") ||
           pathLower.contains("/application support/") && pathLower.contains("/tmp") {
            categories.insert(.temporaryFiles)
        }

        if ["tmp", "temp", "cache"].contains(ext) {
            categories.insert(.temporaryFiles)
        }

        if pathLower.contains("/downloads/") {
            categories.insert(.downloads)
        }

        if file.size >= options.largeFileThresholdBytes {
            categories.insert(.largeFiles)
        }

        let fileAge = now.timeIntervalSince(file.accessedDate)
        if fileAge >= options.oldFileThresholdSeconds {
            let isProtectedOldFile = options.excludeProtectedOldFiles && (
                safeListManager?.isProtected(url: file.url) == true ||
                ext == "app" ||
                pathLower.contains(".app/")
            )

            if !isProtectedOldFile {
                categories.insert(.oldFiles)
            }
        }

        return categories
    }
}
