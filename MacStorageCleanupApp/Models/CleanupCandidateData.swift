import Foundation
import SwiftUI
import MacStorageCleanupCore

/// Represents a file that is a candidate for cleanup with all required metadata
struct CleanupCandidateData: Identifiable {
    let id = UUID()
    let path: String
    let name: String
    let size: Int64
    let modifiedDate: Date
    let accessedDate: Date
    let fileType: FileType
    let category: CleanupCategoryType
    /// Display grouping label for this candidate (e.g. "Xcode Simulators", "Google", "Other Caches").
    /// Defaults to the item's own name when no specific grouping applies.
    var groupLabel: String? = nil
    var isSelected: Bool = false

    // MARK: - Developer cache metadata
    //
    // Multi-version caches cannot be judged by size and date alone: a 3 GB NDK that a
    // project pins is not the same decision as an identical one nothing references.
    // These fields carry that context from the scanner to the row.

    /// How risky deleting this is. Drives the default selection.
    var safety: CacheSafety? = nil
    /// Version this entry belongs to, when its tool keeps one directory per version.
    var version: String? = nil
    /// False marks a superseded version.
    var isNewestVersion: Bool = true
    /// Project files that pin this version. Non-empty means "keep".
    var referencedBy: [URL] = []
    /// Reclaiming this needs administrator rights.
    var requiresAdmin: Bool = false
    /// The size is understated because the path is TCC-protected.
    var needsFullDiskAccess: Bool = false
    /// The size is a lower bound because measurement hit its time budget.
    var isPartialSize: Bool = false

    /// Traffic-light risk of deleting this row.
    ///
    /// Three tiers, and the boundary that matters is between green and amber: green
    /// promises nothing is lost *and* nothing is fetched again, amber costs time only,
    /// red can cost work or configuration.
    enum RiskLevel: Int, Comparable, CaseIterable {
        case safe       // scratch data — delete freely
        case moderate   // regenerates: a rebuild or a re-download
        case risky      // could lose a device, a scheme, or need admin rights

        static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool { lhs.rawValue < rhs.rawValue }

        var color: Color {
            switch self {
            case .safe: return .green
            case .moderate: return .yellow
            case .risky: return .red
            }
        }

        var label: String {
            switch self {
            case .safe: return "Safe"
            case .moderate: return "Regenerates"
            case .risky: return "Review first"
            }
        }

        var explanation: String {
            switch self {
            case .safe: return "Scratch data. Nothing is lost and nothing is downloaded again."
            case .moderate: return "Your tools rebuild or re-download this. Costs time, not work."
            case .risky: return "Could remove a device, a scheme or an install. Check before deleting."
            }
        }
    }

    var riskLevel: RiskLevel {
        // Unreadable means we cannot even judge it, which is its own reason to look.
        if needsFullDiskAccess { return .risky }

        switch safety {
        case .alwaysSafe: return .safe
        case .needsConfirmation: return .risky
        // Generic system, browser and app caches arrive without a safety tier. They are
        // caches: the app refills them on next use.
        case .regenerates, nil: return .moderate
        }
    }

    /// Short explanation of why this row is (or is not) checked by default.
    var safetyNote: String? {
        if needsFullDiskAccess {
            return "Permission needed — grant Full Disk Access to measure this"
        }
        if !referencedBy.isEmpty {
            let names = referencedBy.prefix(2).map { $0.lastPathComponent }.joined(separator: ", ")
            return referencedBy.count > 2
                ? "Pinned by \(names) and \(referencedBy.count - 2) more"
                : "Pinned by \(names)"
        }
        switch safety {
        case .alwaysSafe: return "Scratch data — safe to remove"
        case .regenerates: return isNewestVersion ? "Newest version — in active use" : "Superseded version, nothing references it"
        case .needsConfirmation: return requiresAdmin ? "Needs administrator rights" : "Review before removing"
        case nil: return nil
        }
    }

    enum FileType: String {
        case cache
        case temporary
        case log
        case download
        case largeFile
        case oldFile
        case duplicate
        case document
        case image
        case archive
        case installer
        case other
        
        var displayName: String {
            switch self {
            case .cache: return "Cache"
            case .temporary: return "Temporary"
            case .log: return "Log"
            case .download: return "Download"
            case .largeFile: return "Large File"
            case .oldFile: return "Old File"
            case .duplicate: return "Duplicate"
            case .document: return "Document"
            case .image: return "Image"
            case .archive: return "Archive"
            case .installer: return "Installer"
            case .other: return "Other"
            }
        }
        
        var iconName: String {
            switch self {
            case .cache: return "folder.fill"
            case .temporary: return "clock.fill"
            case .log: return "doc.text.fill"
            case .download: return "arrow.down.circle.fill"
            case .largeFile: return "doc.fill.badge.ellipsis"
            case .oldFile: return "calendar.badge.clock"
            case .duplicate: return "doc.on.doc.fill"
            case .document: return "doc.fill"
            case .image: return "photo.fill"
            case .archive: return "archivebox.fill"
            case .installer: return "shippingbox.fill"
            case .other: return "questionmark.circle.fill"
            }
        }
    }
    
    enum CleanupCategoryType: String, CaseIterable {
        case caches
        case temporaryFiles
        case largeFiles
        case oldFiles
        case logs
        case downloads
        case duplicates
        
        var displayName: String {
            switch self {
            case .caches: return "Cleanup Candidates"
            case .temporaryFiles: return "Temporary Files"
            case .largeFiles: return "Large Files"
            case .oldFiles: return "Old Files"
            case .logs: return "Logs"
            case .downloads: return "Downloads"
            case .duplicates: return "Duplicates"
            }
        }
        
        var description: String {
            switch self {
            case .caches: return "System and application cache files"
            case .temporaryFiles: return "Temporary files that can be safely removed"
            case .largeFiles: return "Files larger than 100MB"
            case .oldFiles: return "Files not accessed in over a year"
            case .logs: return "System and application log files"
            case .downloads: return "Files in your Downloads folder"
            case .duplicates: return "Duplicate files wasting space"
            }
        }
    }
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    var formattedModifiedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: modifiedDate)
    }
    
    var formattedAccessedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: accessedDate)
    }
    
    var relativeAccessedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: accessedDate, relativeTo: Date())
    }
}
