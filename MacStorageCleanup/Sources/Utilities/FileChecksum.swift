import Foundation
import CryptoKit

/// Utility for calculating file checksums
enum FileChecksum {
    /// Calculate SHA-256 checksum for a file
    static func sha256(for url: URL) throws -> String {
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer {
            try? fileHandle.close()
        }
        
        var hasher = SHA256()
        
        // Read file in chunks to handle large files efficiently
        let bufferSize = 1024 * 1024 // 1MB chunks
        while autoreleasepool(invoking: {
            let data = fileHandle.readData(ofLength: bufferSize)
            if data.isEmpty {
                return false
            }
            hasher.update(data: data)
            return true
        }) {}
        
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
