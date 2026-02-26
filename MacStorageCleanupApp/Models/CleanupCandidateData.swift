import Foundation

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
    var isSelected: Bool = false
    
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
            case .caches: return "Caches"
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
