import Foundation
import AppKit

/// Centralized logging utility for FlowMate
@MainActor
final class Logger {
    static let shared = Logger()
    
    private let fileManager = FileManager.default
    private let dateFormatter: DateFormatter
    private let logDirectory: URL
    private var currentLogFile: URL
    
    enum LogLevel: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
        
        var emoji: String {
            switch self {
            case .debug: return "🔍"
            case .info: return "ℹ️"
            case .warning: return "⚠️"
            case .error: return "❌"
            }
        }
    }
    
    private init() {
        // Set up date formatter for log file names
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        // Create logs directory in Application Support
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        logDirectory = appSupport.appendingPathComponent("FlowMate/logs")
        
        // Create directory if it doesn't exist
        try? fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        
        // Set current log file
        let today = dateFormatter.string(from: Date())
        currentLogFile = logDirectory.appendingPathComponent("flowmate-\(today).log")
        
        // Clean up old logs (keep last 7 days)
        cleanupOldLogs()
        
        // Log session start
        info("=== FlowMate Session Started ===")
    }
    
    // MARK: - Public Logging Methods
    
    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .debug, file: file, function: function, line: line)
    }
    
    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, file: file, function: function, line: line)
    }
    
    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .warning, file: file, function: function, line: line)
    }
    
    func error(_ message: String, error: Error? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        var fullMessage = message
        if let error = error {
            fullMessage += " | Error: \(error.localizedDescription)"
        }
        log(fullMessage, level: .error, file: file, function: function, line: line)
    }
    
    // MARK: - Core Logging
    
    private func log(_ message: String, level: LogLevel, file: String, function: String, line: Int) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let fileName = (file as NSString).lastPathComponent
        
        // Format: [TIMESTAMP] [LEVEL] [File:Line] Message
        let logMessage = "[\(timestamp)] [\(level.emoji) \(level.rawValue)] [\(fileName):\(line)] \(message)\n"
        
        // Print to console
        print(logMessage.trimmingCharacters(in: .newlines))
        
        // Write to file
        writeToFile(logMessage)
    }
    
    private func writeToFile(_ message: String) {
        guard let data = message.data(using: .utf8) else { return }
        
        // Create file if it doesn't exist
        if !fileManager.fileExists(atPath: currentLogFile.path) {
            fileManager.createFile(atPath: currentLogFile.path, contents: nil)
        }
        
        // Append to file
        if let fileHandle = try? FileHandle(forWritingTo: currentLogFile) {
            fileHandle.seekToEndOfFile()
            fileHandle.write(data)
            fileHandle.closeFile()
        }
    }
    
    // MARK: - File Management
    
    func getLogDirectory() -> URL {
        return logDirectory
    }
    
    func openLogsFolder() {
        NSWorkspace.shared.open(logDirectory)
    }
    
    func getLogFiles() -> [URL] {
        guard let files = try? fileManager.contentsOfDirectory(
            at: logDirectory,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }
        
        return files.filter { $0.pathExtension == "log" }
            .sorted { ($0.path) > ($1.path) } // Most recent first
    }
    
    func getTotalLogSize() -> Int64 {
        let logFiles = getLogFiles()
        var totalSize: Int64 = 0
        
        for file in logFiles {
            if let attrs = try? fileManager.attributesOfItem(atPath: file.path),
               let fileSize = attrs[.size] as? Int64 {
                totalSize += fileSize
            }
        }
        
        return totalSize
    }
    
    func clearAllLogs() {
        let logFiles = getLogFiles()
        
        for file in logFiles {
            try? fileManager.removeItem(at: file)
        }
        
        info("All logs cleared by user")
    }
    
    private func cleanupOldLogs() {
        let logFiles = getLogFiles()
        let maxAge: TimeInterval = 7 * 24 * 60 * 60 // 7 days
        let now = Date()
        
        for file in logFiles {
            if let attrs = try? fileManager.attributesOfItem(atPath: file.path),
               let creationDate = attrs[.creationDate] as? Date {
                if now.timeIntervalSince(creationDate) > maxAge {
                    try? fileManager.removeItem(at: file)
                }
            }
        }
    }
    
    func getRecentLogs(lineCount: Int = 100) -> String {
        guard let content = try? String(contentsOf: currentLogFile, encoding: .utf8) else {
            return "No logs available"
        }
        
        let lines = content.components(separatedBy: .newlines)
        let recentLines = lines.suffix(lineCount)
        
        return recentLines.joined(separator: "\n")
    }
}
