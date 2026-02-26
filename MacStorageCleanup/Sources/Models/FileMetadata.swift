import Foundation

/// Represents metadata for a file in the file system
public struct FileMetadata: Equatable, Hashable {
    public let url: URL
    public let size: Int64
    public let createdDate: Date
    public let modifiedDate: Date
    public let accessedDate: Date
    public let fileType: FileType
    public let isInUse: Bool
    public let permissions: FilePermissions
    
    public init(
        url: URL,
        size: Int64,
        createdDate: Date,
        modifiedDate: Date,
        accessedDate: Date,
        fileType: FileType,
        isInUse: Bool = false,
        permissions: FilePermissions = FilePermissions(isReadable: true, isWritable: true, isDeletable: true)
    ) {
        self.url = url
        self.size = size
        self.createdDate = createdDate
        self.modifiedDate = modifiedDate
        self.accessedDate = accessedDate
        self.fileType = fileType
        self.isInUse = isInUse
        self.permissions = permissions
    }
}

/// File type classification
public enum FileType: Equatable, Hashable {
    case cache
    case log
    case temporary
    case document
    case application
    case archive
    case media
    case other(String)
}

/// File permission information
public struct FilePermissions: Equatable, Hashable {
    public let isReadable: Bool
    public let isWritable: Bool
    public let isDeletable: Bool
    
    public init(isReadable: Bool, isWritable: Bool, isDeletable: Bool) {
        self.isReadable = isReadable
        self.isWritable = isWritable
        self.isDeletable = isDeletable
    }
}
