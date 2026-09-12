import Foundation

/// Describes the progress of the machine learning pipeline loading phase.
///
/// Use `DaemonPipelineLoadProgress` to display structured loading updates to the user.
struct DaemonPipelineLoadProgress: Equatable {
    /// A short description of the current loading step.
    let message: String

    /// Stable machine-readable loading phase sent by the daemon.
    let phase: String

    /// Optional detailed context for the current step.
    let detail: String?
    
    /// The number of completed steps.
    let current: Int
    
    /// The total number of steps in the loading process.
    let total: Int

    /// When the whole pipeline load began.
    let startedAt: Date

    /// When the current loading phase began.
    let stepStartedAt: Date

    /// When the daemon last sent a progress update.
    let lastUpdatedAt: Date

    /// The normalized progress fraction, from `0.0` to `1.0`.
    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(current) / Double(total)))
    }

    /// Integer percent, clamped to 0...100.
    var percent: Int {
        Int((fraction * 100).rounded())
    }

    /// Current step label suitable for compact UI.
    var stepText: String {
        guard total > 0 else { return "Waiting" }
        return "\(min(max(current, 0), total))/\(total)"
    }

    /// A formatted, human-readable status text representing the loading progress.
    var statusText: String {
        let cleanMessage = message.isEmpty ? "Preparing pipeline" : message
        guard total > 0 else {
            return "Loading Pipeline… \(cleanMessage)"
        }
        return "Loading Pipeline… \(percent)% — \(cleanMessage) (\(stepText))"
    }

    /// Returns total pipeline-load elapsed time at a given display instant.
    func totalElapsed(at date: Date = Date()) -> TimeInterval {
        max(0, date.timeIntervalSince(startedAt))
    }

    /// Returns current step elapsed time at a given display instant.
    func stepElapsed(at date: Date = Date()) -> TimeInterval {
        max(0, date.timeIntervalSince(stepStartedAt))
    }

    /// Returns age of the latest daemon update at a given display instant.
    func lastUpdateAge(at date: Date = Date()) -> TimeInterval {
        max(0, date.timeIntervalSince(lastUpdatedAt))
    }
}

extension TimeInterval {
    /// Compact duration text for pipeline status displays.
    var pipelineDurationText: String {
        let seconds = max(0, Int(self.rounded()))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        let remainder = seconds % 60
        return "\(minutes)m \(remainder)s"
    }
}

/// Provides environment variables necessary for launching the Python daemon.
struct DaemonRuntimeEnvironment {
    /// Creates the standard environment variable dictionary required by the PyTorch and MPS backends.
    ///
    /// - Parameters:
    ///   - settings: The settings service used to retrieve configuration, such as the Hugging Face token.
    ///   - logger: The logger used to record validation warnings.
    /// - Returns: A dictionary of environment variables ready for `Process.environment`.
    static func make(settings: SettingsService = .shared, logger: AppLogger = .shared) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        env["PYTORCH_ENABLE_MPS_FALLBACK"] = "1"
        let token = settings.hfToken
        if !token.isEmpty { env["HF_TOKEN"] = token }
        applyAdvancedEnvVars(settings.advancedEnvVars, to: &env, logger: logger)
        // Do NOT force SPARSE_CONV_BACKEND here.
        // The Python daemon auto-detects flex_gemm at import time and falls
        // back to conv_none only when the Metal backend is unavailable.

        // Xcode Metal validation can abort PyTorch/MPS kernels with exit code 6.
        env["MTL_DEBUG_LAYER"] = "0"
        env["MTL_SHADER_VALIDATION"] = "0"
        env["METAL_DEVICE_WRAPPER_TYPE"] = "0"
        return env
    }

    private static func applyAdvancedEnvVars(
        _ rawEnvVars: String,
        to env: inout [String: String],
        logger: AppLogger
    ) {
        for rawLine in rawEnvVars.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                logger.warning("Ignoring malformed env override: \(line)", context: "Daemon")
                continue
            }
            let key = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            env[key] = value
        }
    }
}

/// A buffer that retains the most recent stderr output from the daemon process.
///
/// Use `DaemonStderrTail` to provide contextual error messages when the daemon crashes unexpectedly.
struct DaemonStderrTail {
    private var lines: [String] = []

    mutating func reset() {
        lines = []
    }

    mutating func append(_ line: String) {
        lines.append(line)
        if lines.count > 12 {
            lines.removeFirst(lines.count - 12)
        }
    }

    /// Constructs a crash message combining the fallback text with the recent stderr tail.
    func crashMessage(fallback: String) -> String {
        guard !lines.isEmpty else { return fallback }
        let tail = lines.suffix(4).joined(separator: " | ")
        if tail.contains("validateComputeFunctionArguments") {
            return "\(fallback) Metal API validation aborted the MPS kernel. Validation is now disabled for daemon restarts. stderr: \(tail)"
        }
        return "\(fallback) stderr: \(tail)"
    }
}
