import Foundation
import os.log

/// A centralized logging service for Trellis Studio.
///
/// Use `AppLogger` to record application events, warnings, and errors.
/// This service writes logs to both Apple's unified logging system (visible in Console.app)
/// and an in-memory buffer that is surfaced in the application's user interface.
final class AppLogger: ObservableObject {
    static let shared = AppLogger()

    /// The list of recent in-memory log entries for UI display.
    @Published var entries: [LogEntry] = []

    /// The most recent error message, which is shown as a banner in the UI.
    @Published var lastError: String?

    /// Whether the error banner is visible.
    @Published var showErrorBanner: Bool = false

    private let osLog = Logger(subsystem: "com.vinware.trellis-studio", category: "app")
    private let maxEntries = 500

    private init() {}

    // MARK: - Public API

    /// Logs an informational message.
    ///
    /// - Parameters:
    ///   - message: The message to log.
    ///   - context: The subsystem or component generating the log. Defaults to `"App"`.
    func info(_ message: String, context: String = "App") {
        log(.info, message, context: context)
    }

    /// Logs a warning message.
    ///
    /// - Parameters:
    ///   - message: The message to log.
    ///   - context: The subsystem or component generating the log. Defaults to `"App"`.
    func warning(_ message: String, context: String = "App") {
        log(.warning, message, context: context)
    }

    /// Logs an error message and displays it in the user interface as an error banner.
    ///
    /// - Parameters:
    ///   - message: The error message to log.
    ///   - context: The subsystem or component generating the log. Defaults to `"App"`.
    func error(_ message: String, context: String = "App") {
        log(.error, message, context: context)
        DispatchQueue.main.async {
            self.lastError = "[\(context)] \(message)"
            self.showErrorBanner = true
        }
    }

    /// Logs a success message.
    ///
    /// - Parameters:
    ///   - message: The success message to log.
    ///   - context: The subsystem or component generating the log. Defaults to `"App"`.
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
