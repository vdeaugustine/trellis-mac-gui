import Foundation

/// Classifies daemon errors so the UI can show actionable recovery.
enum DaemonErrorKind: Equatable {
    case none
    case gatedAccess(repo: String)
    case authRequired
    case generic
}

final class DaemonManager: ObservableObject {
    static let shared = DaemonManager()

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()
    private var healthCheckTimer: Timer?

    @Published var isReady = false
    @Published var isWarmingUp = false
    @Published var isOffline = true
    @Published var lastDaemonError: String?
    /// Structured error classification for actionable UI messages.
    @Published var errorKind: DaemonErrorKind = .none

    var isDryRun = false

    private var progressCallbacks: [([String: Any]) -> Void] = []
    private let log = AppLogger.shared

    private init() {}

    // MARK: - Lifecycle

    func startDaemon(trellisPath: String, dryRun: Bool = false) {
        // Kill any existing daemon first
        if process?.isRunning == true {
            log.warning("Killing existing daemon before restart", context: "Daemon")
            process?.terminate()
        }

        self.isDryRun = dryRun
        self.isOffline = false
        self.isWarmingUp = true
        self.lastDaemonError = nil
        self.errorKind = .none
        self.stdoutBuffer = Data()
        self.stderrBuffer = Data()

        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let pythonURL = URL(fileURLWithPath: trellisPath)
            .appendingPathComponent(".venv/bin/python")
        let scriptURL = URL(fileURLWithPath: trellisPath)
            .appendingPathComponent("trellis_daemon.py")

        // Validate paths
        guard FileManager.default.fileExists(atPath: pythonURL.path) else {
            let msg = "Python not found: \(pythonURL.path)"
            log.error(msg, context: "Daemon")
            failWithError(msg)
            return
        }
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            let msg = "Daemon script not found: \(scriptURL.path)"
            log.error(msg, context: "Daemon")
            failWithError(msg)
            return
        }

        process.executableURL = pythonURL
        var arguments = [scriptURL.path]
        if dryRun { arguments.append("--dry-run") }
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: trellisPath)

        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        env["PYTORCH_ENABLE_MPS_FALLBACK"] = "1"
        let token = SettingsService.shared.hfToken
        if !token.isEmpty { env["HF_TOKEN"] = token }
        process.environment = env

        // Set up readability handlers BEFORE launching (no race condition)
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                // EOF — process closed stdout
                handle.readabilityHandler = nil
                return
            }
            self?.handleStdoutData(data)
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            self?.handleStderrData(data)
        }

        // Termination handler
        process.terminationHandler = { [weak self] proc in
            let code = proc.terminationStatus
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.healthCheckTimer?.invalidate()
                self.healthCheckTimer = nil

                if code == 0 {
                    self.log.info("Daemon exited normally", context: "Daemon")
                } else if code == 2 {
                    let msg = "GPU watchdog killed the process. Try running headless (close lid, use SSH)."
                    self.log.error(msg, context: "Daemon")
                    self.failWithError(msg)
                } else {
                    let msg = "Daemon crashed with exit code \(code). Check stderr output above."
                    self.log.error(msg, context: "Daemon")
                    self.failWithError(msg)
                }
                self.isOffline = true
                self.isWarmingUp = false
                self.isReady = false
            }
        }

        self.process = process
        self.stdinPipe = stdinPipe
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe

        do {
            log.info("Launching: \(pythonURL.lastPathComponent) \(scriptURL.lastPathComponent)\(dryRun ? " --dry-run" : "")", context: "Daemon")
            log.info("Working dir: \(trellisPath)", context: "Daemon")
            try process.run()
            log.info("Daemon PID: \(process.processIdentifier)", context: "Daemon")

            // Health check — poll process liveness every 5s
            startHealthCheck()

        } catch {
            let msg = "Failed to launch: \(error.localizedDescription)"
            log.error(msg, context: "Daemon")
            failWithError(msg)
        }
    }

    func stopDaemon() {
        log.info("Shutting down daemon", context: "Daemon")
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil

        sendRequest(command: ["command": "shutdown"])

        // Give it a moment then force-kill
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            if self?.process?.isRunning == true {
                self?.log.warning("Force-terminating daemon", context: "Daemon")
                self?.process?.terminate()
            }
            self?.cleanup()
        }
    }

    // MARK: - Request Sending

    func sendRequest(command: [String: Any]) {
        guard let stdinPipe = stdinPipe else {
            log.error("Cannot send — daemon not running", context: "Daemon")
            return
        }
        guard process?.isRunning == true else {
            log.error("Cannot send — daemon process is dead", context: "Daemon")
            failWithError("Daemon process died. Restart the app.")
            return
        }

        let payload = ["command": command]
        do {
            let data = try JSONSerialization.data(withJSONObject: payload)
            guard let jsonStr = String(data: data, encoding: .utf8) else {
                log.error("Failed to serialize request", context: "Daemon")
                return
            }
            let line = jsonStr + "\n"
            guard let lineData = line.data(using: .utf8) else { return }
            log.info("→ \(jsonStr.prefix(200))", context: "Daemon")
            stdinPipe.fileHandleForWriting.write(lineData)
        } catch {
            log.error("JSON error: \(error.localizedDescription)", context: "Daemon")
        }
    }

    // MARK: - Callbacks

    func registerCallback(_ callback: @escaping ([String: Any]) -> Void) {
        progressCallbacks.append(callback)
    }

    func clearCallbacks() {
        progressCallbacks.removeAll()
    }

    // MARK: - Stdout Handling (readabilityHandler callback — no race)

    private func handleStdoutData(_ data: Data) {
        stdoutBuffer.append(data)

        // Split on newlines
        while let range = stdoutBuffer.range(of: Data([10])) {
            let lineData = stdoutBuffer.subdata(in: 0..<range.lowerBound)
            stdoutBuffer.removeSubrange(0...range.lowerBound)

            guard let line = String(data: lineData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !line.isEmpty else { continue }

            parseDaemonLine(line)
        }
    }

    private func parseDaemonLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = json["response"] as? [String: Any] else {
            // Non-JSON output — log it
            log.info("stdout (raw): \(line.prefix(300))", context: "Daemon")
            return
        }

        let stage = response["stage"] as? String ?? "?"
        let status = response["status"] as? String ?? "?"
        log.info("← stage=\(stage) status=\(status)", context: "Daemon")

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Forward to registered callbacks
            for cb in self.progressCallbacks { cb(response) }

            // Handle daemon lifecycle events
            if let stageEnum = GenerationStatus(rawValue: stage) {
                switch stageEnum {
                case .loadingPipeline:
                    if status == "done" {
                        self.isWarmingUp = false
                        self.isReady = true
                        self.lastDaemonError = nil
                        self.log.success("Pipeline loaded — ready", context: "Daemon")
                    }
                case .shutdown:
                    self.isReady = false
                    self.isOffline = true
                case .failed:
                    let reason = response["reason"] as? String ?? "unknown"
                    let message = response["message"] as? String ?? "No details"
                    self.failWithError("[\(reason)] \(message)")
                default:
                    break
                }
            }
        }
    }

    // MARK: - Stderr Handling

    private func handleStderrData(_ data: Data) {
        stderrBuffer.append(data)

        while let range = stderrBuffer.range(of: Data([10])) {
            let lineData = stderrBuffer.subdata(in: 0..<range.lowerBound)
            stderrBuffer.removeSubrange(0...range.lowerBound)

            guard let line = String(data: lineData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !line.isEmpty else { continue }

            // Classify severity
            let isError = line.contains("Error") || line.contains("Traceback")
                || line.contains("Exception") || line.contains("ModuleNotFoundError")
            if isError {
                log.error("stderr: \(line)", context: "Daemon")
            } else {
                log.warning("stderr: \(line)", context: "Daemon")
            }
        }
    }

    // MARK: - Health Check

    private func startHealthCheck() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            guard let proc = self.process else { return }

            if !proc.isRunning {
                self.log.error("Health check: daemon process is no longer running", context: "Daemon")
                self.healthCheckTimer?.invalidate()
                self.healthCheckTimer = nil

                DispatchQueue.main.async {
                    if self.isWarmingUp || self.isReady {
                        self.failWithError("Daemon died unexpectedly. Check console for Python errors.")
                    }
                    self.isOffline = true
                    self.isWarmingUp = false
                    self.isReady = false
                }
            }
        }
    }

    // MARK: - Helpers

    private func failWithError(_ message: String) {
        DispatchQueue.main.async {
            self.lastDaemonError = message
            self.errorKind = Self.classifyError(message)
            self.isOffline = true
            self.isWarmingUp = false
            self.isReady = false
        }
    }

    /// Scans error text for gated-access or auth patterns.
    private static func classifyError(_ message: String) -> DaemonErrorKind {
        let lower = message.lowercased()

        // Gated repo pattern: "Access to model <repo> is restricted"
        if lower.contains("gated repo") || lower.contains("is restricted") {
            // Try to extract repo id from the message
            if let range = message.range(of: "huggingface.co/", options: .caseInsensitive) {
                let after = message[range.upperBound...]
                let repo = after.prefix(while: { !$0.isWhitespace && $0 != "/" || $0 == "/" })
                // Extract "org/model" (two path segments)
                let parts = repo.split(separator: "/", maxSplits: 2)
                if parts.count >= 2 {
                    return .gatedAccess(repo: "\(parts[0])/\(parts[1])")
                }
            }
            return .gatedAccess(repo: "unknown")
        }

        if lower.contains("401") || lower.contains("unauthorized") || lower.contains("not logged in") {
            return .authRequired
        }

        return .generic
    }

    private func cleanup() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil

        DispatchQueue.main.async {
            self.isOffline = true
            self.isReady = false
            self.isWarmingUp = false
        }
    }
}
