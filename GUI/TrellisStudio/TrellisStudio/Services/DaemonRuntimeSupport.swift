import Foundation

struct DaemonPipelineLoadProgress: Equatable {
    let message: String
    let current: Int
    let total: Int

    var statusText: String {
        let cleanMessage = message.isEmpty ? "Preparing pipeline" : message
        guard total > 0 else {
            return "Loading Pipeline… \(cleanMessage)"
        }
        let clampedCurrent = min(max(current, 0), total)
        let percent = Int((Double(clampedCurrent) / Double(total) * 100).rounded())
        return "Loading Pipeline… \(percent)% — \(cleanMessage) (\(clampedCurrent)/\(total))"
    }
}

struct DaemonRuntimeEnvironment {
    static func make(settings: SettingsService = .shared, logger: AppLogger = .shared) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        env["PYTORCH_ENABLE_MPS_FALLBACK"] = "1"
        let token = settings.hfToken
        if !token.isEmpty { env["HF_TOKEN"] = token }
        applyAdvancedEnvVars(settings.advancedEnvVars, to: &env, logger: logger)
        env["SPARSE_CONV_BACKEND"] = env["SPARSE_CONV_BACKEND"] ?? "none"

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
            if key == "SPARSE_CONV_BACKEND", value == "flex_gemm" {
                logger.warning(
                    "SPARSE_CONV_BACKEND=flex_gemm is unstable during pipeline load; using none",
                    context: "Daemon"
                )
                env[key] = "none"
                continue
            }
            env[key] = value
        }
    }
}

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

    func crashMessage(fallback: String) -> String {
        guard !lines.isEmpty else { return fallback }
        let tail = lines.suffix(4).joined(separator: " | ")
        if tail.contains("validateComputeFunctionArguments") {
            return "\(fallback) Metal API validation aborted the MPS kernel. Validation is now disabled for daemon restarts. stderr: \(tail)"
        }
        return "\(fallback) stderr: \(tail)"
    }
}
