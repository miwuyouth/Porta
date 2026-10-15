import Foundation
import SwiftUI
import Combine

public final class LogManager: ObservableObject {
    public static let shared = LogManager()

    @Published public var entries: [FRPLogEntry] = []
    @Published public var isPaused: Bool = false
    @Published public var autoScroll: Bool = true
    @Published public var selectedProxyFilter: String = "全部代理"
    @Published public var selectedLevelFilter: FRPLogLevel = .all

    private let logFileURL: URL
    private let maxEntries: Int = 1000

    private init() {
        self.logFileURL = StorageService.shared.logFilePath
        // Start with clean log entries
        self.entries = []
    }

    public var filteredEntries: [FRPLogEntry] {
        entries.filter { entry in
            // Filter by level
            if selectedLevelFilter != .all && entry.level != selectedLevelFilter {
                return false
            }
            // Filter by proxy
            if selectedProxyFilter != "全部代理" {
                if let tag = entry.proxyTag {
                    let matchesTag = selectedProxyFilter.lowercased().contains(tag.lowercased()) || tag.lowercased().contains(selectedProxyFilter.lowercased())
                    if !matchesTag { return false }
                } else {
                    return false
                }
            }
            return true
        }
    }

    public func add(level: FRPLogLevel, proxyTag: String? = nil, message: String) {
        guard !isPaused else { return }

        let entry = FRPLogEntry(
            timestamp: Date(),
            level: level,
            proxyTag: proxyTag,
            message: message
        )

        DispatchQueue.main.async {
            self.entries.append(entry)
            if self.entries.count > self.maxEntries {
                self.entries.removeFirst(self.entries.count - self.maxEntries)
            }
        }

        // Write to log file asynchronously
        appendToFile(entry: entry)
    }

    public func clear() {
        entries.removeAll()
        try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
    }

    public func copyAllLogsToClipboard() {
        let text = filteredEntries.map { "\($0.timeString)  \($0.level.rawValue)  \($0.fullDisplayMessage)" }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func appendToFile(entry: FRPLogEntry) {
        let line = "\(entry.timeString) [\(entry.level.rawValue)] \(entry.fullDisplayMessage)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    try? fileHandle.close()
                }
            } else {
                try? data.write(to: logFileURL)
            }
        }
    }

    private func loadInitialMockLogs() {
        let calendar = Calendar.current
        let now = Date()

        func dateAt(minuteOffset: Int, secondOffset: Int) -> Date {
            return calendar.date(byAdding: .second, value: -(60 - secondOffset), to: now) ?? now
        }

        self.entries = [
            FRPLogEntry(timestamp: dateAt(minuteOffset: 1, secondOffset: 1), level: .info, proxyTag: nil, message: "正在连接服务器..."),
            FRPLogEntry(timestamp: dateAt(minuteOffset: 1, secondOffset: 1), level: .info, proxyTag: nil, message: "登录成功"),
            FRPLogEntry(timestamp: dateAt(minuteOffset: 1, secondOffset: 2), level: .info, proxyTag: "web", message: "代理启动成功"),
            FRPLogEntry(timestamp: dateAt(minuteOffset: 1, secondOffset: 2), level: .info, proxyTag: "ssh", message: "代理启动成功"),
            FRPLogEntry(timestamp: dateAt(minuteOffset: 1, secondOffset: 2), level: .info, proxyTag: "dev", message: "代理启动成功"),
            FRPLogEntry(timestamp: dateAt(minuteOffset: 1, secondOffset: 15), level: .info, proxyTag: "web", message: "新连接已建立"),
            FRPLogEntry(timestamp: dateAt(minuteOffset: 1, secondOffset: 18), level: .info, proxyTag: "ssh", message: "新连接已建立"),
            FRPLogEntry(timestamp: dateAt(minuteOffset: 1, secondOffset: 42), level: .warn, proxyTag: "web", message: "连接超时，正在重试"),
            FRPLogEntry(timestamp: dateAt(minuteOffset: 1, secondOffset: 43), level: .info, proxyTag: "web", message: "连接已恢复"),
            FRPLogEntry(timestamp: dateAt(minuteOffset: 0, secondOffset: 2), level: .info, proxyTag: nil, message: "心跳正常")
        ]
    }
}
