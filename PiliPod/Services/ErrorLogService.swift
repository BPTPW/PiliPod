import Combine
import Foundation
import SwiftUI

struct ErrorLogEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let context: String
    let message: String
    let details: String?
    let domain: String?
    let code: Int?
    let source: String

    init(timestamp: Date = .now, context: String, message: String, details: String? = nil, domain: String? = nil, code: Int? = nil, source: String) {
        id = UUID()
        self.timestamp = timestamp
        self.context = context
        self.message = message
        self.details = details
        self.domain = domain
        self.code = code
        self.source = source
    }
}

/// Stores a capped, privacy-conscious history of diagnostically useful runtime errors.
final class ErrorLogService: ObservableObject {
    static let shared = ErrorLogService()

    @Published private(set) var entries: [ErrorLogEntry]
    @Published private(set) var maximumEntryCount: Int

    private static let maximumEntryCountKey = "errorLog.maximumEntryCount"
    private static let duplicateSuppressionInterval: TimeInterval = 5 * 60
    private let storageQueue = DispatchQueue(label: "com.pilipod.error-log-storage")
    private let storageURL: URL

    private init() {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        storageURL = directory.appendingPathComponent("PiliPod-error-log.json")
        let savedLimit = UserDefaults.standard.object(forKey: Self.maximumEntryCountKey) as? Int
        maximumEntryCount = savedLimit.flatMap { [10, 20, 50, 0].contains($0) ? $0 : nil } ?? 20
        entries = Self.loadEntries(from: storageURL)
        let originalEntryCount = entries.count
        trimEntriesIfNeeded()
        if entries.count != originalEntryCount {
            persist(entries)
        }
    }

    static func installUncaughtExceptionHandler() {
        NSSetUncaughtExceptionHandler(piliPodUncaughtExceptionHandler)
    }

    static func record(_ error: Error, context: String, file: String = #fileID, line: Int = #line) {
        let nsError = error as NSError
        guard shouldRecord(error) else { return }
        let failureReason = nsError.localizedFailureReason
        let recoverySuggestion = nsError.localizedRecoverySuggestion
        let debugDescription = String(reflecting: error)
        let details = [
            "描述：\(error.localizedDescription)",
            failureReason.map { "失败原因：\($0)" },
            recoverySuggestion.map { "恢复建议：\($0)" },
            "调试描述：\(debugDescription)"
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
        record(
            message: error.localizedDescription,
            context: context,
            details: details,
            domain: nsError.domain,
            code: nsError.code,
            source: "\(file):\(line)"
        )
    }

    static func record(
        message: String,
        context: String,
        details: String? = nil,
        domain: String? = nil,
        code: Int? = nil,
        source: String = #fileID
    ) {
        shared.append(
            ErrorLogEntry(
                context: context,
                message: redactSensitiveData(in: message),
                details: details.map(redactSensitiveData),
                domain: domain,
                code: code,
                source: source
            )
        )
    }

    static func recordUncaughtException(_ exception: NSException) {
        let entry = ErrorLogEntry(
            context: "未捕获异常",
            message: redactSensitiveData(in: exception.reason ?? exception.description),
            details: exception.callStackSymbols.joined(separator: "\n"),
            domain: exception.name.rawValue,
            source: exception.callStackSymbols.prefix(12).joined(separator: "\\n")
        )
        // The process is about to exit, so bypass the main queue and write directly.
        shared.persistUncaughtException(entry)
    }

    func clear() {
        entries = []
        persist(entries)
    }

    func setMaximumEntryCount(_ count: Int) {
        guard [10, 20, 50, 0].contains(count) else { return }
        maximumEntryCount = count
        UserDefaults.standard.set(count, forKey: Self.maximumEntryCountKey)
        trimEntriesIfNeeded()
        persist(entries)
    }

    private func append(_ entry: ErrorLogEntry) {
        let update = {
            guard !self.shouldSuppressDuplicate(entry) else { return }
            self.entries.insert(entry, at: 0)
            self.trimEntriesIfNeeded()
            self.persist(self.entries)
        }
        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async(execute: update)
        }
    }

    private func persist(_ entries: [ErrorLogEntry]) {
        storageQueue.async { [storageURL] in
            guard let data = try? JSONEncoder().encode(entries) else { return }
            try? data.write(to: storageURL, options: .atomic)
        }
    }

    private func persistUncaughtException(_ entry: ErrorLogEntry) {
        storageQueue.sync { [storageURL] in
            var storedEntries = Self.loadEntries(from: storageURL)
            storedEntries.insert(entry, at: 0)
            if maximumEntryCount > 0, storedEntries.count > maximumEntryCount {
                storedEntries.removeLast(storedEntries.count - maximumEntryCount)
            }
            guard let data = try? JSONEncoder().encode(storedEntries) else { return }
            try? data.write(to: storageURL, options: .atomic)
        }
    }

    private func trimEntriesIfNeeded() {
        guard maximumEntryCount > 0, entries.count > maximumEntryCount else { return }
        entries.removeLast(entries.count - maximumEntryCount)
    }

    private func shouldSuppressDuplicate(_ entry: ErrorLogEntry) -> Bool {
        guard let newest = entries.first,
              newest.context == entry.context,
              newest.message == entry.message,
              newest.domain == entry.domain,
              newest.code == entry.code
        else { return false }
        return entry.timestamp.timeIntervalSince(newest.timestamp) < Self.duplicateSuppressionInterval
    }

    private static func shouldRecord(_ error: Error) -> Bool {
        if error is CancellationError { return false }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return false }
        return true
    }

    private static func loadEntries(from url: URL) -> [ErrorLogEntry] {
        guard let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([ErrorLogEntry].self, from: data)
        else { return [] }
        return entries.sorted { $0.timestamp > $1.timestamp }
    }

    private static func redactSensitiveData(in text: String) -> String {
        let patterns = [
            "(?i)(SESSDATA|bili_jct|access_key|authorization|cookie)\\s*[=:]\\s*[^,\\s;]+",
            "(?i)(SESSDATA|bili_jct|access_key)=([^&\\s]+)"
        ]
        return patterns.reduce(text) { result, pattern in
            result.replacingOccurrences(of: pattern, with: "$1=<redacted>", options: .regularExpression)
        }
    }
}

private func piliPodUncaughtExceptionHandler(_ exception: NSException) {
    ErrorLogService.recordUncaughtException(exception)
}
