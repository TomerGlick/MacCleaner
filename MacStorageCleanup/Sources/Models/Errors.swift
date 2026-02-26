import Foundation

/// Errors that can occur during file system scanning
public enum ScanError: Error, Equatable {
    case permissionDenied(path: String)
    case pathNotFound(path: String)
    case cancelled
    case unknown(String)
    
    public static func == (lhs: ScanError, rhs: ScanError) -> Bool {
        switch (lhs, rhs) {
        case (.permissionDenied(let lPath), .permissionDenied(let rPath)):
            return lPath == rPath
        case (.pathNotFound(let lPath), .pathNotFound(let rPath)):
            return lPath == rPath
        case (.cancelled, .cancelled):
            return true
        case (.unknown(let lMsg), .unknown(let rMsg)):
            return lMsg == rMsg
        default:
            return false
        }
    }
}

/// Errors that can occur during cleanup operations
public enum CleanupError: Error, Equatable {
    case fileProtected(path: String)
    case fileInUse(path: String)
    case permissionDenied(path: String)
    case fileNotFound(path: String)
    case cancelled
    case backupFailed(String)
    case unknown(String)
    
    public static func == (lhs: CleanupError, rhs: CleanupError) -> Bool {
        switch (lhs, rhs) {
        case (.fileProtected(let lPath), .fileProtected(let rPath)):
            return lPath == rPath
        case (.fileInUse(let lPath), .fileInUse(let rPath)):
            return lPath == rPath
        case (.permissionDenied(let lPath), .permissionDenied(let rPath)):
            return lPath == rPath
        case (.fileNotFound(let lPath), .fileNotFound(let rPath)):
            return lPath == rPath
        case (.cancelled, .cancelled):
            return true
        case (.backupFailed(let lMsg), .backupFailed(let rMsg)):
            return lMsg == rMsg
        case (.unknown(let lMsg), .unknown(let rMsg)):
            return lMsg == rMsg
        default:
            return false
        }
    }
}

/// Errors that can occur during application uninstallation
public enum UninstallError: Error, Equatable {
    case applicationRunning(name: String)
    case applicationNotFound(path: String)
    case permissionDenied
    case partialUninstall(removedFiles: Int, failedFiles: Int)
    case unknown(String)
    
    public static func == (lhs: UninstallError, rhs: UninstallError) -> Bool {
        switch (lhs, rhs) {
        case (.applicationRunning(let lName), .applicationRunning(let rName)):
            return lName == rName
        case (.applicationNotFound(let lPath), .applicationNotFound(let rPath)):
            return lPath == rPath
        case (.permissionDenied, .permissionDenied):
            return true
        case (.partialUninstall(let lRemoved, let lFailed), .partialUninstall(let rRemoved, let rFailed)):
            return lRemoved == rRemoved && lFailed == rFailed
        case (.unknown(let lMsg), .unknown(let rMsg)):
            return lMsg == rMsg
        default:
            return false
        }
    }
}

/// Errors that can occur during backup restoration
public enum RestoreError: Error, Equatable {
    case backupNotFound
    case backupCorrupted
    case destinationNotWritable
    case insufficientSpace
    case unknown(String)
    
    public static func == (lhs: RestoreError, rhs: RestoreError) -> Bool {
        switch (lhs, rhs) {
        case (.backupNotFound, .backupNotFound):
            return true
        case (.backupCorrupted, .backupCorrupted):
            return true
        case (.destinationNotWritable, .destinationNotWritable):
            return true
        case (.insufficientSpace, .insufficientSpace):
            return true
        case (.unknown(let lMsg), .unknown(let rMsg)):
            return lMsg == rMsg
        default:
            return false
        }
    }
}
