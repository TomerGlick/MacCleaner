import Foundation
import Compression

/// Protocol for managing file backups
public protocol BackupManager {
    func createBackup(files: [FileMetadata], destination: URL) async throws -> BackupResult
    func listBackups() -> [Backup]
    func restoreBackup(backup: Backup, destination: URL) async throws -> RestoreResult
    func deleteBackup(backup: Backup) throws
}

/// Default implementation of BackupManager
public class DefaultBackupManager: BackupManager {
    private let fileManager = FileManager.default
    private let backupDirectory: URL
    
    public init() {
        // Store backups in ~/Library/Application Support/MacStorageCleanup/Backups
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.backupDirectory = appSupport
            .appendingPathComponent("MacStorageCleanup")
            .appendingPathComponent("Backups")
        
        // Create backup directory if it doesn't exist
        try? fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
    }
    
    /// Create a compressed backup of the specified files
    public func createBackup(files: [FileMetadata], destination: URL) async throws -> BackupResult {
        let startTime = Date()
        let backupId = UUID()
        let timestamp = ISO8601DateFormatter().string(from: startTime)
        let backupName = "backup_\(timestamp)_\(backupId.uuidString).tar.gz"
        let backupURL = destination.appendingPathComponent(backupName)
        
        // Create manifest
        let manifestEntries = try files.map { file in
            // Calculate checksum for integrity verification
            let checksum = try FileChecksum.sha256(for: file.url)
            
            return BackupManifestEntry(
                originalPath: file.url.path,
                size: file.size,
                modifiedDate: file.modifiedDate,
                fileType: fileTypeString(file.fileType),
                checksum: checksum
            )
        }
        
        let manifest = BackupManifest(
            backupId: backupId,
            createdDate: startTime,
            entries: manifestEntries
        )
        
        // Create temporary directory for staging
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(backupId.uuidString)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? fileManager.removeItem(at: tempDir)
        }
        
        // Write manifest
        let manifestURL = tempDir.appendingPathComponent("manifest.json")
        let manifestData = try JSONEncoder().encode(manifest)
        try manifestData.write(to: manifestURL)
        
        // Copy files to temp directory preserving structure
        var copiedFiles = 0
        for file in files {
            let relativePath = file.url.path.replacingOccurrences(of: "/", with: "_")
            let destURL = tempDir.appendingPathComponent(relativePath)
            
            do {
                try fileManager.copyItem(at: file.url, to: destURL)
                copiedFiles += 1
            } catch {
                // Continue with other files if one fails
                continue
            }
        }
        
        // Create compressed archive
        try await compressDirectory(tempDir, to: backupURL)
        
        // Get compressed size
        let attributes = try fileManager.attributesOfItem(atPath: backupURL.path)
        let compressedSize = attributes[.size] as? Int64 ?? 0
        
        let duration = Date().timeIntervalSince(startTime)
        
        return BackupResult(
            backupURL: backupURL,
            filesBackedUp: copiedFiles,
            compressedSize: compressedSize,
            duration: duration
        )
    }
    
    /// List all available backups
    public func listBackups() -> [Backup] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: backupDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey]
        ) else {
            return []
        }
        
        return contents.compactMap { url -> Backup? in
            guard url.pathExtension == "gz" else { return nil }
            
            let attributes = try? fileManager.attributesOfItem(atPath: url.path)
            let compressedSize = attributes?[.size] as? Int64 ?? 0
            let createdDate = attributes?[.creationDate] as? Date ?? Date()
            
            // Try to extract backup info from filename
            let filename = url.deletingPathExtension().deletingPathExtension().lastPathComponent
            let components = filename.components(separatedBy: "_")
            
            guard components.count >= 3,
                  let uuid = UUID(uuidString: components.last ?? "") else {
                return nil
            }
            
            // Try to read manifest to get file count and original size
            if let manifest = try? readManifest(from: url) {
                return Backup(
                    id: uuid,
                    createdDate: manifest.createdDate,
                    fileCount: manifest.entries.count,
                    originalSize: manifest.entries.reduce(0) { $0 + $1.size },
                    compressedSize: compressedSize,
                    location: url
                )
            }
            
            return Backup(
                id: uuid,
                createdDate: createdDate,
                fileCount: 0,
                originalSize: 0,
                compressedSize: compressedSize,
                location: url
            )
        }
    }
    
    /// Restore files from a backup
    public func restoreBackup(backup: Backup, destination: URL) async throws -> RestoreResult {
        // Read manifest
        let manifest = try readManifest(from: backup.location)
        
        // Create temporary directory for extraction
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(backup.id.uuidString)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? fileManager.removeItem(at: tempDir)
        }
        
        // Decompress archive
        try await decompressArchive(backup.location, to: tempDir)
        
        // Restore files to their original locations or destination
        var restoredCount = 0
        var errors: [RestoreError] = []
        
        for entry in manifest.entries {
            let relativePath = entry.originalPath.replacingOccurrences(of: "/", with: "_")
            let sourceURL = tempDir.appendingPathComponent(relativePath)
            let destURL = destination.appendingPathComponent(URL(fileURLWithPath: entry.originalPath).lastPathComponent)
            
            do {
                // Verify checksum of backed up file before restoring
                let backupChecksum = try FileChecksum.sha256(for: sourceURL)
                guard backupChecksum == entry.checksum else {
                    errors.append(.backupCorrupted)
                    continue
                }
                
                // Create parent directory if needed
                try fileManager.createDirectory(
                    at: destURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                
                // Copy file
                if fileManager.fileExists(atPath: destURL.path) {
                    try fileManager.removeItem(at: destURL)
                }
                try fileManager.copyItem(at: sourceURL, to: destURL)
                
                // Verify checksum of restored file
                let restoredChecksum = try FileChecksum.sha256(for: destURL)
                guard restoredChecksum == entry.checksum else {
                    // Restore failed, remove corrupted file
                    try? fileManager.removeItem(at: destURL)
                    errors.append(.backupCorrupted)
                    continue
                }
                
                restoredCount += 1
            } catch {
                errors.append(.unknown(error.localizedDescription))
            }
        }
        
        return RestoreResult(filesRestored: restoredCount, errors: errors)
    }
    
    /// Delete a backup
    public func deleteBackup(backup: Backup) throws {
        try fileManager.removeItem(at: backup.location)
    }
    
    /// Get backups older than the specified number of days
    public func getOldBackups(olderThanDays days: Int = 30) -> [Backup] {
        let allBackups = listBackups()
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        
        return allBackups.filter { backup in
            backup.createdDate < cutoffDate
        }
    }
    
    // MARK: - Private Helpers
    
    private func fileTypeString(_ fileType: FileType) -> String {
        switch fileType {
        case .cache: return "cache"
        case .log: return "log"
        case .temporary: return "temporary"
        case .document: return "document"
        case .application: return "application"
        case .archive: return "archive"
        case .media: return "media"
        case .other(let type): return type
        }
    }
    
    private func compressDirectory(_ source: URL, to destination: URL) async throws {
        // Create tar archive first
        let tarURL = destination.deletingPathExtension()
        try await createTarArchive(source, to: tarURL)
        
        // Compress the tar file
        let tarData = try Data(contentsOf: tarURL)
        let compressedData = try compress(tarData)
        try compressedData.write(to: destination)
        
        // Clean up tar file
        try fileManager.removeItem(at: tarURL)
    }
    
    private func createTarArchive(_ source: URL, to destination: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = [
            "-cf",
            destination.path,
            "-C",
            source.path,
            "."
        ]
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw CleanupError.backupFailed("Failed to create tar archive")
        }
    }
    
    private func compress(_ data: Data) throws -> Data {
        let bufferSize = 4096
        var compressedData = Data()
        
        try data.withUnsafeBytes { (rawBufferPointer: UnsafeRawBufferPointer) in
            guard let baseAddress = rawBufferPointer.baseAddress else {
                throw CleanupError.backupFailed("Failed to get data buffer")
            }
            
            let filter = try OutputFilter(.compress, using: .lzfse) { data in
                if let data = data {
                    compressedData.append(data)
                }
            }
            
            var offset = 0
            while offset < data.count {
                let chunkSize = min(bufferSize, data.count - offset)
                let chunk = Data(bytes: baseAddress.advanced(by: offset), count: chunkSize)
                try filter.write(chunk)
                offset += chunkSize
            }
            
            try filter.finalize()
        }
        
        return compressedData
    }
    
    private func decompressArchive(_ source: URL, to destination: URL) async throws {
        // Decompress gz file
        let compressedData = try Data(contentsOf: source)
        let decompressedData = try decompress(compressedData)
        
        // Write tar file
        let tarURL = destination.appendingPathComponent("archive.tar")
        try decompressedData.write(to: tarURL)
        
        // Extract tar
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = [
            "-xf",
            tarURL.path,
            "-C",
            destination.path
        ]
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw RestoreError.backupCorrupted
        }
        
        // Clean up tar file
        try fileManager.removeItem(at: tarURL)
    }
    
    private func decompress(_ data: Data) throws -> Data {
        var decompressedData = Data()
        
        try data.withUnsafeBytes { (rawBufferPointer: UnsafeRawBufferPointer) in
            guard let baseAddress = rawBufferPointer.baseAddress else {
                throw RestoreError.backupCorrupted
            }
            
            let filter = try InputFilter(.decompress, using: .lzfse) { length in
                return Data(bytes: baseAddress, count: min(length, data.count))
            }
            
            while let chunk = try filter.readData(ofLength: 4096) {
                decompressedData.append(chunk)
            }
        }
        
        return decompressedData
    }
    
    private func readManifest(from backupURL: URL) throws -> BackupManifest {
        // Create temporary directory for extraction
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? fileManager.removeItem(at: tempDir)
        }
        
        // Decompress archive
        try Task.synchronous {
            try await self.decompressArchive(backupURL, to: tempDir)
        }
        
        // Read manifest
        let manifestURL = tempDir.appendingPathComponent("manifest.json")
        let manifestData = try Data(contentsOf: manifestURL)
        return try JSONDecoder().decode(BackupManifest.self, from: manifestData)
    }
}

// Helper extension for synchronous async execution
extension Task where Failure == Error {
    static func synchronous(operation: @escaping () async throws -> Success) throws -> Success {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Success, Error>?
        
        Task<Void, Never> {
            do {
                let value = try await operation()
                result = .success(value)
            } catch {
                result = .failure(error)
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        
        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        case .none:
            fatalError("Task completed without result")
        }
    }
}
