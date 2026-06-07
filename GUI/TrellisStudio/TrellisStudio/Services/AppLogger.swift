import Foundation
import os.log

/// Centralized logging for Trellis Studio.
/// Writes to both Apple's unified logging system (visible in Console.app)
/// and an in-memory buffer surfaced in the UI for user debugging.
final class AppLogger: ObservableObject {
    static let shared = AppLogger()

    /// In-memory log entries for UI display.
    @Published var entries: [LogEntry] = []

    /// Most recent error message — shown as a banner in the UI.
    @Published var lastError: String?

    /// Whether the error banner is visible.
    @Published var showErrorBanner: Bool = false

    private let osLog = Logger(subsystem: "com.vinware.trellis-studio", category: "app")
    private let maxEntries = 500

    private init() {}

    // MARK: - Public API

    func info(_ message: String, context: String = "App") {
        log(.info, message, context: context)
    }

    func warning(_ message: String, context: String = "App") {
        log(.warning, message, context: context)
    }

    func error(_ message: String, context: String = "App") {
        log(.error, message, context: context)
        DispatchQueue.main.async {
            self.lastError = "[\(context)] \(message)"
            self.showErrorBanner = true
        }
    }

    func success(_ message: String, context: String = "App") {
        log(.success, message, context: context)
    }

    /// Clears the error banner.
    func dismissError() {
        DispatchQueue.main.async {
            self.showErrorBanner = false
            self.lastError = nil
        }
    }

    // MARK: - Internal

    private func log(_ level: LogLevel, _ message: String, context: String) {
        let entry = LogEntry(level: level, context: context, message: message)

        // OS unified log
        switch level {
        case .info:    osLog.info("[\(context)] \(message)")
        case .warning: osLog.warning("[\(context)] \(message)")
        case .error:   osLog.error("[\(context)] \(message)")
        case .success: osLog.info("[\(context)] ✓ \(message)")
        }

        // Print to Xcode console
        print("[\(level.symbol)] [\(context)] \(message)")

        DispatchQueue.main.async {
            self.entries.append(entry)
            if self.entries.count > self.maxEntries {
                self.entries.removeFirst(self.entries.count - self.maxEntries)
            }
        }
    }
}

// MARK: - Supporting Types

enum LogLevel: String {
    case info, warning, error, success

    var symbol: String {
        switch self {
        case .info:    return "ℹ️"
        case .warning: return "⚠️"
        case .error:   return "❌"
        case .success: return "✅"
        }
    }
}

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let level: LogLevel
    let context: String
    let message: String
}
