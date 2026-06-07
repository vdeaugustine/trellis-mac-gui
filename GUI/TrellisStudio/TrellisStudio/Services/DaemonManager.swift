import Foundation

/// Classifies daemon errors so the UI can show actionable recovery.
///
/// Use `DaemonErrorKind` to determine if a daemon failure requires specific user intervention,
/// such as logging into Hugging Face or accepting a model repository's access agreement.
enum DaemonErrorKind: Equatable {
    case none
    case gatedAccess(repo: String)
    case authRequired
    case generic
}

/// Manages the lifecycle and state of the Python background daemon.
///
/// Use `DaemonManager` to start the backend, monitor its health, and dispatch generation
/// requests. The manager maintains a TCP connection to the daemon and parses stdout/stderr
/// for error recovery and pipeline loading progress.
final class DaemonManager: ObservableObject {
    static let shared = DaemonManager()

    // Process handle (only when we launched the daemon ourselves)
    private var process: Process?
    private var stderrPipe: Pipe?
    private var stderrBuffer = Data()
    private var stderrTail = DaemonStderrTail()

    // TCP connection (primary communication channel)
    private var tcpConnection = DaemonTCPConnection()
    private var healthCheckTimer: Timer?

    /// A Boolean value that indicates whether the daemon is fully ready to accept generation requests.
    @Published var isReady = false
    
    /// A Boolean value that indicates whether the daemon is currently starting up or loading its pipeline.
    @Published var isWarmingUp = false
    
    /// A Boolean value that indicates whether the daemon process is stopped or disconnected.
    @Published var isOffline = true
    
    /// A Boolean value that indicates whether the machine learning pipeline is loaded into GPU memory.
    @Published var isPipelineLoaded = false
    
    /// The current progress of the pipeline loading phase, if applicable.
    @Published var pipelineLoadProgress: DaemonPipelineLoadProgress?
    
    /// The most recent error message reported by the daemon.
    @Published var lastDaemonError: String?
    
    /// The classification of the most recent error.
    @Published var errorKind: DaemonErrorKind = .none
    
    /// A user-facing status message used during daemon startup and connection phases.
    @Published var connectionStatus: String?

    /// Recent stderr lines from the daemon process, surfaced for the UI console.
    @Published var consoleOutput: [String] = []

    /// A Boolean value that indicates whether the daemon is running in dry-run mode.
    var isDryRun = false

    private var progressCallbacks: [([String: Any]) -> Void] = []
    private var crashCallbacks: [(String) -> Void] = []
    private let log = AppLogger.shared

    /// Path to port and PID files written by daemon.
    private var appSupportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("com.vinware.trellis-studio")
    }
    private var portFilePath: String { appSupportDir.appendingPathComponent("daemon.port").path }
    private var pidFilePath: String { appSupportDir.appendingPathComponent("daemon.pid").path }

    private init() {}

    // MARK: - Lifecycle

    /// Starts the background Python daemon using the specified installation path.
    ///
    /// If an existing daemon is found and responsive, the manager will reconnect to it instead
    /// of launching a new process.
    ///
    /// - Parameters:
    ///   - trellisPath: The file path to the Trellis Python environment.
    ///   - dryRun: A Boolean value that indicates whether the daemon should skip actual GPU processing.
    func startDaemon(trellisPath: String, dryRun: Bool = false) {
        self.isDryRun = dryRun

        tryReconnectToExistingDaemon { [weak self] reconnected in
            guard let self else { return }
            if reconnected {
                self.log.success("Reconnected to existing daemon — skipping pipeline reload", context: "Daemon")
                return
            }

            self.resetState()
            self.launchNewDaemon(trellisPath: trellisPath, dryRun: dryRun)
        }
    }

    /// Shuts down the daemon gracefully.
    ///
    /// This method sends a shutdown request over the TCP connection and forcefully terminates
    /// the process if it does not exit within the timeout period.
    func stopDaemon() {
        log.info("Shutting down daemon", context: "Daemon")
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil

        sendRequest(command: ["command": "shutdown"])

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.tcpConnection.disconnect()
            if self?.process?.isRunning == true {
                self?.log.warning("Force-terminating daemon", context: "Daemon")
                self?.process?.terminate()
            }
            self?.cleanup()
        }
    }

    // MARK: - Reconnect to Existing Daemon

    private func tryReconnectToExistingDaemon(completion: @escaping (Bool) -> Void) {
        guard let port = readDaemonPort(),
              let pid = readDaemonPID(),
              isProcessAlive(pid: pid) else {
            completion(false)
            return
        }

        log.info("Found existing daemon (PID: \(pid), port: \(port)) — reconnecting…", context: "Daemon")

        tcpConnection.connect(port: port) { [weak self] connected in
            guard let self else { return }
            if connected {
                self.wireUpTCPCallbacks()
                self.startHealthCheck()
                completion(true)
                return
            }

            self.log.warning("TCP connect failed to existing daemon — will launch new one", context: "Daemon")
            completion(false)
        }
    }

    private func readDaemonPort() -> Int? {
        guard let content = try? String(contentsOfFile: portFilePath, encoding: .utf8) else { return nil }
        return Int(content.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func readDaemonPID() -> Int32? {
        guard let content = try? String(contentsOfFile: pidFilePath, encoding: .utf8) else { return nil }
        return Int32(content.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func isProcessAlive(pid: Int32) -> Bool {
        // kill(pid, 0) returns 0 if process exists
        return kill(pid, 0) == 0
    }

    // MARK: - Launch New Daemon

    private func launchNewDaemon(trellisPath: String, dryRun: Bool) {
        let pythonURL = URL(fileURLWithPath: trellisPath)
            .appendingPathComponent(".venv/bin/python")
        let scriptURL = URL(fileURLWithPath: trellisPath)
            .appendingPathComponent("trellis_daemon.py")

        guard FileManager.default.fileExists(atPath: pythonURL.path) else {
            failWithError("Python not found: \(pythonURL.path)")
            return
        }
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            failWithError("Daemon script not found: \(scriptURL.path)")
            return
        }

        let process = Process()
        let stderrPipe = Pipe()

        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice  // Daemon writes to TCP, not stdout
        process.standardError = stderrPipe
        process.executableURL = pythonURL

        var arguments = [scriptURL.path]
        if dryRun { arguments.append("--dry-run") }
        // Don't use --legacy; daemon will start TCP server
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: trellisPath)
        process.environment = DaemonRuntimeEnvironment.make()

        // Read stderr for error reporting
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            self?.handleStderrData(data)
        }

        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                self?.handleProcessTermination(exitCode: proc.terminationStatus)
            }
        }

        self.process = process
        self.stderrPipe = stderrPipe

        do {
            log.info("Launching daemon: \(scriptURL.lastPathComponent)", context: "Daemon")
            log.info("Working dir: \(trellisPath)", context: "Daemon")
            connectionStatus = "Launching Python backend…"
            try process.run()
            log.info("Daemon PID: \(process.processIdentifier)", context: "Daemon")

            // Wait for daemon to write port file, then connect via TCP
            connectionStatus = "Waiting for backend to start…"
            connectAfterLaunch()

        } catch {
            failWithError("Failed to launch: \(error.localizedDescription)")
        }
    }

    private func connectAfterLaunch() {
        // Poll for port file (daemon writes it shortly after starting)
        var attempts = 0
        let maxAttempts = 120  // ~30 seconds (daemon needs time for Python startup)

        func checkPortFile() {
            attempts += 1
            if attempts % 10 == 0 {
                let seconds = attempts / 4
                log.info("Waiting for daemon port file… (attempt \(attempts)/\(maxAttempts))", context: "Daemon")
                connectionStatus = "Starting Python environment… (\(seconds)s)"
            }
            if let port = readDaemonPort() {
                connectionStatus = "Connecting to backend on port \(port)…"
                log.info("Port file found: \(port). Connecting…", context: "Daemon")
                tcpConnection.connect(port: port) { [weak self] connected in
                    guard let self else { return }
                    if connected {
                        self.log.success("TCP connected to new daemon on port \(port)", context: "Daemon")
                        self.connectionStatus = nil
                        self.wireUpTCPCallbacks()
                        self.startHealthCheck()
                        return
                    }

                    self.log.warning("TCP connect to port \(port) failed, retrying…", context: "Daemon")
                    scheduleNextCheck()
                }
                return
            }

            scheduleNextCheck()
        }

        func scheduleNextCheck() {
            if attempts < maxAttempts {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    checkPortFile()
                }
            } else {
                failWithError("Daemon launched but never wrote port file after 30s. Check stderr.")
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            checkPortFile()
        }
    }

    // MARK: - TCP Callbacks

    private func wireUpTCPCallbacks() {
        tcpConnection.onResponse = { [weak self] response in
            self?.handleDaemonResponse(response)
        }
        tcpConnection.onDisconnect = { [weak self] in
            self?.handleTCPDisconnect()
        }
    }

    private func handleDaemonResponse(_ response: [String: Any]) {
        let stage = response["stage"] as? String ?? ""
        let status = response["status"] as? String ?? ""

        // Handle daemon lifecycle events first (don't forward to generation callbacks)
        if stage == "daemonStatus" {
            handleDaemonStatus(response)
            return
        }

        // Forward non-lifecycle responses to registered callbacks
        for cb in progressCallbacks { cb(response) }

        // Surface pipeline loading messages to console for user visibility
        if stage == "loadingPipeline", let message = response["message"] as? String {
            consoleOutput.append("[pipeline] \(message)")
            if consoleOutput.count > 200 {
                consoleOutput.removeFirst(consoleOutput.count - 200)
            }
        }

        if let stageEnum = GenerationStatus(rawValue: stage) {
            switch stageEnum {
            case .loadingPipeline:
                handlePipelineLoad(response, status: status)
            case .shutdown:
                isReady = false
                isOffline = true
            case .failed:
                let reason = response["reason"] as? String ?? "unknown"
                let message = response["message"] as? String ?? "No details"
                let failureMessage = "[\(reason)] \(message)"
                log.error(failureMessage, context: "Daemon")
                failWithError(failureMessage)
            default:
                break
            }
        }
    }

    private func handleTCPDisconnect() {
        log.warning("TCP disconnected from daemon", context: "Daemon")
        // Don't mark as offline immediately — daemon might still be alive
        // (client disconnect != daemon death). Try to reconnect.
        if readDaemonPort() != nil,
           let pid = readDaemonPID(),
           isProcessAlive(pid: pid) {
            log.info("Daemon still alive — will reconnect on next action", context: "Daemon")
        } else {
            isOffline = true
            isReady = false
            isPipelineLoaded = false
        }
    }

    // MARK: - Request Sending

    /// Sends a JSON command to the daemon over the active TCP connection.
    ///
    /// - Parameter command: A dictionary representing the command payload.
    func sendRequest(command: [String: Any]) {
        if tcpConnection.isConnected {
            tcpConnection.send(command: command)
        } else {
            log.error("Cannot send — no TCP connection to daemon", context: "Daemon")
        }
    }

    // MARK: - Callbacks

    /// Registers a closure to be called when the daemon sends a progress update.
    ///
    /// - Parameter callback: A closure that receives the raw JSON response payload.
    func registerCallback(_ callback: @escaping ([String: Any]) -> Void) {
        progressCallbacks.append(callback)
    }

    /// Removes all registered progress callbacks.
    func clearCallbacks() {
        progressCallbacks.removeAll()
    }

    /// Registers a closure to be called when the daemon process crashes unexpectedly.
    ///
    /// - Parameter callback: A closure that receives the crash error message.
    func registerCrashCallback(_ callback: @escaping (String) -> Void) {
        crashCallbacks.append(callback)
    }

    /// Removes all registered crash callbacks.
    func clearCrashCallbacks() {
        crashCallbacks.removeAll()
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

            stderrTail.append(line)
            let isError = line.contains("Error") || line.contains("Traceback")
                || line.contains("Exception") || line.contains("ModuleNotFoundError")
            if isError {
                log.error("stderr: \(line)", context: "Daemon")
            } else {
                log.warning("stderr: \(line)", context: "Daemon")
            }

            // Surface to UI console
            let captured = line
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.consoleOutput.append(captured)
                // Keep buffer bounded
                if self.consoleOutput.count > 200 {
                    self.consoleOutput.removeFirst(self.consoleOutput.count - 200)
                }
                // Update connection status with daemon step messages
                if captured.hasPrefix("[daemon]"), !self.isReady {
                    let cleaned = captured
                        .replacingOccurrences(of: "[daemon] ", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleaned.isEmpty {
                        self.connectionStatus = cleaned
                    }
                }
            }
        }
    }

    // MARK: - Health Check

    private func startHealthCheck() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            // Check TCP connection
            if !self.tcpConnection.isConnected {
                // Try reconnect
                if let port = self.readDaemonPort(),
                   let pid = self.readDaemonPID(),
                   self.isProcessAlive(pid: pid) {
                    self.tcpConnection.connect(port: port) { [weak self] connected in
                        if connected {
                            self?.wireUpTCPCallbacks()
                        }
                    }
                } else {
                    self.log.error("Health check: daemon is gone", context: "Daemon")
                    self.healthCheckTimer?.invalidate()
                    self.healthCheckTimer = nil
                    DispatchQueue.main.async {
                        self.isOffline = true
                        self.isReady = false
                        self.isPipelineLoaded = false
                        self.pipelineLoadProgress = nil
                    }
                }
            } else if !self.progressCallbacks.isEmpty {
                // Generation in progress — don't send status polls,
                // they interfere with pipeline loading responses
            } else if (!self.isReady && !self.isOffline) || self.isWarmingUp {
                self.sendRequest(command: ["command": "status"])
            }
        }
    }

    // MARK: - Process Termination

    private func handleProcessTermination(exitCode: Int32) {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil

        if exitCode == 0 {
            log.info("Daemon exited normally", context: "Daemon")
        } else if exitCode == 2 {
            let msg = stderrTail.crashMessage(
                fallback: "GPU watchdog killed the process."
            )
            log.error(msg, context: "Daemon")
            failWithError(msg)
            notifyCrashCallbacks(message: msg)
        } else {
            let msg = stderrTail.crashMessage(
                fallback: "Daemon crashed with exit code \(exitCode)."
            )
            log.error(msg, context: "Daemon")
            failWithError(msg)
            notifyCrashCallbacks(message: msg)
        }

        isOffline = true
        isWarmingUp = false
        isReady = false
        isPipelineLoaded = false
        pipelineLoadProgress = nil
    }

    // MARK: - Helpers

    private func resetState() {
        if process?.isRunning == true {
            log.warning("Killing existing daemon before restart", context: "Daemon")
            process?.terminate()
        }
        tcpConnection.disconnect()

        isOffline = false
        isWarmingUp = false
        isReady = false
        isPipelineLoaded = false
        pipelineLoadProgress = nil
        lastDaemonError = nil
        errorKind = .none
        stderrBuffer = Data()
        stderrTail.reset()

        // Remove stale port/pid files from previous sessions
        try? FileManager.default.removeItem(atPath: portFilePath)
        try? FileManager.default.removeItem(atPath: pidFilePath)
    }

    private func failWithError(_ message: String) {
        DispatchQueue.main.async {
            self.lastDaemonError = message
            self.errorKind = Self.classifyError(message)
            self.isOffline = true
            self.isWarmingUp = false
            self.isReady = false
            self.isPipelineLoaded = false
            self.pipelineLoadProgress = nil
        }
    }

    private func notifyCrashCallbacks(message: String) {
        let callbacks = crashCallbacks
        crashCallbacks.removeAll()
        for callback in callbacks { callback(message) }
    }

    private func handleDaemonStatus(_ response: [String: Any]) {
        let status = response["status"] as? String ?? ""
        let pipelineLoaded = response["pipeline_loaded"] as? Bool ?? false
        if status == "ready" || pipelineLoaded {
            markReady(pipelineLoaded: pipelineLoaded)
        } else if status == "loading" {
            isOffline = false
            isReady = false
            isWarmingUp = true
            pipelineLoadProgress = nil
        }
    }

    private func handlePipelineLoad(_ response: [String: Any], status: String) {
        if status == "done" {
            markReady(pipelineLoaded: true)
            return
        }
        guard status == "started" || status == "step" else { return }
        isOffline = false
        isReady = false
        isWarmingUp = true
        pipelineLoadProgress = DaemonPipelineLoadProgress(
            message: response["message"] as? String ?? "Preparing pipeline",
            current: response["current"] as? Int ?? 0,
            total: response["total"] as? Int ?? 0
        )
    }

    private func markReady(pipelineLoaded: Bool) {
        isOffline = false
        isWarmingUp = false
        isReady = true
        isPipelineLoaded = pipelineLoaded
        pipelineLoadProgress = nil
        connectionStatus = nil
        lastDaemonError = nil
        errorKind = .none
        let msg = pipelineLoaded ? "Pipeline loaded — ready" : "Backend ready — pipeline loads on first generation"
        log.success(msg, context: "Daemon")
    }

    /// Scans error text for gated-access or auth patterns.
    static func classifyError(_ message: String) -> DaemonErrorKind {
        let lower = message.lowercased()
        if lower.contains("gated repo") || lower.contains("is restricted") {
            if let range = message.range(of: "huggingface.co/", options: .caseInsensitive) {
                let after = message[range.upperBound...]
                let repo = after.prefix(while: { !$0.isWhitespace && $0 != "/" || $0 == "/" })
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
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        tcpConnection.disconnect()
        process = nil
        stderrPipe = nil

        DispatchQueue.main.async {
            self.isOffline = true
            self.isReady = false
            self.isWarmingUp = false
            self.isPipelineLoaded = false
            self.pipelineLoadProgress = nil
        }
    }
}
