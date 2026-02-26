import Foundation
import os.log

/// Service for application logging and debugging
class LoggingService {
    static let shared = LoggingService()
    
    private let logger = Logger(subsystem: "com.macstorageCleanup", category: "general")
    private let fileLogger: FileLogger
    
    private init() {
        self.fileLogger = FileLogger()
    }
    
    // MARK: - Logging Methods
    
    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let logMessage = formatMessage(message, level: "DEBUG", file: file, function: function, line: line)
        logger.debug("\(logMessage)")
        fileLogger.write(logMessage)
    }
    
    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let logMessage = formatMessage(message, level: "INFO", file: file, function: function, line: line)
        logger.info("\(logMessage)")
        fileLogger.write(logMessage)
    }
    
    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let logMessage = formatMessage(message, level: "WARNING", file: file, function: function, line: line)
        logger.warning("\(logMessage)")
        fileLogger.write(logMessage)
    }
    
    func error(_ message: String, error: Error? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        var logMessage = formatMessage(message, level: "ERROR", file: file, function: function, line: line)
        if let error = error {
            logMessage += " | Error: \(error.localizedDescription)"
        }
        logger.error("\(logMessage)")
        fileLogger.write(logMessage)
    }
    
    func critical(_ message: String, error: Error? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        var logMessage = formatMessage(message, level: "CRITICAL", file: file, function: function, line: line)
        if let error = error {
            logMessage += " | Error: \(error.localizedDescription)"
        }
        logger.critical("\(logMessage)")
        fileLogger.write(logMessage)
    }
    
    // MARK: - Helper Methods
    
    private func formatMessage(_ message: String, level: String, file: String, function: String, line: Int) -> String {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let filename = (file as NSString).lastPathComponent
        return "[\(timestamp)] [\(level)] [\(filename):\(line)] \(function) - \(message)"
    }
    
    func getLogFileURL() -> URL {
        fileLogger.logFileURL
    }
    
    func clearLogs() {
        fileLogger.clearLogs()
    }
}

// MARK: - File Logger

private class FileLogger {
    let logFileURL: URL
    private let fileHandle: FileHandle?
    private let queue = DispatchQueue(label: "com.macStorageCleanup.fileLogger", qos: .utility)
    
    init() {
        // Create logs directory
        let logsDirectory = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Logs")
            .appendingPathComponent("MacStorageCleanup")
        
        try? FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        
        // Create log file with date
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())
        
        logFileURL = logsDirectory.appendingPathComponent("app-\(dateString).log")
        
        // Create file if it doesn't exist
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }
        
        // Open file handle
        fileHandle = try? FileHandle(forWritingTo: logFileURL)
        fileHandle?.seekToEndOfFile()
    }
    
    func write(_ message: String) {
        queue.async { [weak self] in
            guard let self = self, let fileHandle = self.fileHandle else { return }
            
            let logLine = message + "\n"
            if let data = logLine.data(using: .utf8) {
                fileHandle.write(data)
            }
        }
    }
    
    func clearLogs() {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            try? FileManager.default.removeItem(at: self.logFileURL)
            FileManager.default.createFile(atPath: self.logFileURL.path, contents: nil)
        }
    }
    
    deinit {
        try? fileHandle?.close()
    }
}
