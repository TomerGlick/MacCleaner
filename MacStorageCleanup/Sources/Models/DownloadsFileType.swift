import Foundation

/// Specific file type categorization for Downloads folder
public enum DownloadsFileType: String, Equatable, Hashable {
    case document
    case image
    case archive
    case installer
    case other
    
    /// Determine Downloads file type from file extension and MIME type
    /// - Parameters:
    ///   - url: The file URL
    ///   - mimeType: Optional MIME type (if available)
    /// - Returns: The Downloads file type
    public static func categorize(url: URL, mimeType: String? = nil) -> DownloadsFileType {
        let ext = url.pathExtension.lowercased()
        
        // Check MIME type first if available
        if let mime = mimeType {
            if mime.hasPrefix("image/") {
                return .image
            } else if mime.hasPrefix("application/") {
                if mime.contains("zip") || mime.contains("compressed") || mime.contains("archive") {
                    return .archive
                } else if mime.contains("pdf") || mime.contains("document") || mime.contains("text") {
                    return .document
                } else if mime.contains("x-apple-diskimage") || mime.contains("x-pkg") || mime.contains("octet-stream") {
                    return .installer
                }
            } else if mime.hasPrefix("text/") {
                return .document
            }
        }
        
        // Fall back to extension-based categorization
        return categorizeByExtension(ext)
    }
    
    /// Categorize file by extension
    private static func categorizeByExtension(_ ext: String) -> DownloadsFileType {
        // Documents
        if ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", 
            "rtf", "txt", "csv", "odt", "ods", "odp"].contains(ext) {
            return .document
        }
        
        // Images
        if ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "heic", "heif", "webp", 
            "svg", "ico", "raw", "cr2", "nef", "dng"].contains(ext) {
            return .image
        }
        
        // Archives
        if ["zip", "tar", "gz", "bz2", "7z", "rar", "xz", "tgz", "tbz2", "iso", 
            "sit", "sitx", "zipx"].contains(ext) {
            return .archive
        }
        
        // Installers
        if ["dmg", "pkg", "app", "mpkg", "exe", "msi", "deb", "rpm"].contains(ext) {
            return .installer
        }
        
        return .other
    }
}

/// Information about a file in the Downloads folder
public struct DownloadsFileInfo: Equatable, Hashable {
    public let metadata: FileMetadata
    public let downloadsType: DownloadsFileType
    public let isOldDownload: Bool // older than 90 days
    
    public init(metadata: FileMetadata, downloadsType: DownloadsFileType, isOldDownload: Bool) {
        self.metadata = metadata
        self.downloadsType = downloadsType
        self.isOldDownload = isOldDownload
    }
    
    /// Create DownloadsFileInfo from FileMetadata
    public static func from(fileMetadata: FileMetadata, mimeType: String? = nil) -> DownloadsFileInfo {
        let downloadsType = DownloadsFileType.categorize(url: fileMetadata.url, mimeType: mimeType)
        
        // Check if file is older than 90 days
        let ninetyDaysInSeconds: TimeInterval = 90 * 24 * 60 * 60
        let fileAge = Date().timeIntervalSince(fileMetadata.accessedDate)
        let isOldDownload = fileAge > ninetyDaysInSeconds
        
        return DownloadsFileInfo(
            metadata: fileMetadata,
            downloadsType: downloadsType,
            isOldDownload: isOldDownload
        )
    }
}
