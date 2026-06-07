import Foundation

final class DaemonManager: ObservableObject {
    static let shared = DaemonManager()

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?

    @Published var isReady = false
    @Published var isWarmingUp = false
    @Published var isOffline = true
    @Published var lastDaemonError: String?

    var isDryRun = false

    private var progressCallbacks: [([String: Any]) -> Void] = []
    private let log = AppLogger.shared

    private init() {}

    func startDaemon(trellisPath: String, dryRun: Bool = false) {
        self.isDryRun = dryRun
        self.isOffline = false
        self.isWarmingUp = true
        self.lastDaemonError = nil

        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let pythonURL = URL(fileURLWithPath: trellisPath).appendingPathComponent(".venv/bin/python")
        let scriptURL = URL(fileURLWithPath: trellisPath).appendingPathComponent("trellis_daemon.py")

        // Validate paths before launch
        guard FileManager.default.fileExists(atPath: pythonURL.path) else {
            let msg = "Python not found: \(pythonURL.path)"
            log.error(msg, context: "Daemon")
            self.lastDaemonError = msg
            self.isOffline = true
            self.isWarmingUp = false
            return
        }

        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            let msg = "Daemon script not found: \(scriptURL.path)"
            log.error(msg, context: "Daemon")
            self.lastDaemonError = msg
            self.isOffline = true
            self.isWarmingUp = false
            return
        }

        process.executableURL = pythonURL
        var arguments = [scriptURL.path]
        if dryRun {
            arguments.append("--dry-run")
        }
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: trellisPath)

        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        env["PYTORCH_ENABLE_MPS_FALLBACK"] = "1"
        if !SettingsService.shared.hfToken.isEmpty {
            env["HF_TOKEN"] = SettingsService.shared.hfToken
        }
        process.environment = env

        // Crash handler
        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let code = proc.terminationStatus
                self.log.warning("Daemon exited with code \(code)", context: "Daemon")
                self.isOffline = true
                self.isWarmingUp = false
                self.isReady = false
                if code == 2 {
                    self.lastDaemonError = "GPU watchdog killed the process (exit code 2). Try running headless."
                    self.log.error("GPU watchdog crash detected (exit code 2)", context: "Daemon")
                } else if code != 0 {
                    self.lastDaemonError = "Daemon crashed (exit code \(code)). Check logs."
                    self.log.error("Unexpected daemon exit code: \(code)", context: "Daemon")
                }
            }
        }

        self.process = process
        self.stdinPipe = stdinPipe
        self.stdoutPipe = stdoutPipe

        do {
            log.info("Launching daemon: \(pythonURL.path) \(arguments.joined(separator: " "))", context: "Daemon")
            try process.run()
            log.info("Daemon PID: \(process.processIdentifier)", context: "Daemon")

            // Listen to stdout
            Task { await listenToStdout(pipe: stdoutPipe) }

            // Listen to stderr for error messages
            Task { await listenToStderr(pipe: stderrPipe) }

        } catch {
            let msg = "Failed to launch daemon: \(error.localizedDescription)"
            log.error(msg, context: "Daemon")
            self.lastDaemonError = msg
            DispatchQueue.main.async {
                self.isOffline = true
                self.isWarmingUp = false
                self.isReady = false
            }
        }
    }

    func stopDaemon() {
        log.info("Sending shutdown command", context: "Daemon")
        sendRequest(command: ["command": "shutdown"])
        process?.terminate()
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        DispatchQueue.main.async {
            self.isOffline = true
            self.isReady = false
            self.isWarmingUp = false
        }
    }

    func sendRequest(command: [String: Any]) {
        guard let stdinPipe = stdinPipe else {
            log.error("Cannot send request — stdin pipe is nil (daemon not running?)", context: "Daemon")
            return
        }
        let payload = ["command": command]
        do {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [])
            guard let jsonString = String(data: data, encoding: .utf8) else {
                log.error("Failed to serialize request to string", context: "Daemon")
                return
            }
            let line = jsonString + "\n"
            guard let lineData = line.data(using: .utf8) else {
                log.error("Failed to encode request line to UTF-8", context: "Daemon")
                return
            }
            log.info("Sending request: \(jsonString.prefix(200))", context: "Daemon")
            stdinPipe.fileHandleForWriting.write(lineData)
        } catch {
            log.error("JSON serialization failed: \(error.localizedDescription)", context: "Daemon")
        }
    }

    func registerCallback(_ callback: @escaping ([String: Any]) -> Void) {
        progressCallbacks.append(callback)
    }

    func clearCallbacks() {
        progressCallbacks.removeAll()
    }

    // MARK: - Stdout Listener

    private func listenToStdout(pipe: Pipe) async {
        let fileHandle = pipe.fileHandleForReading
        var buffer = Data()

        while true {
            do {
                guard let data = try fileHandle.read(upToCount: 4096), !data.isEmpty else {
                    log.warning("Daemon stdout EOF — process may have exited", context: "Daemon")
                    break
                }
                buffer.append(data)

                while let range = buffer.range(of: Data([10])) {
                    let lineData = buffer.subdata(in: 0..<range.lowerBound)
                    buffer.removeSubrange(0...range.lowerBound)

                    if let line = String(data: lineData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty {
                        await parseDaemonLine(line)
                    }
                }
            } catch {
                log.error("Stdout read error: \(error.localizedDescription)", context: "Daemon")
                break
            }
        }

        DispatchQueue.main.async {
            self.isOffline = true
            self.isWarmingUp = false
            self.isReady = false
        }
    }

    // MARK: - Stderr Listener

    private func listenToStderr(pipe: Pipe) async {
        let fileHandle = pipe.fileHandleForReading
        var buffer = Data()

        while true {
            do {
                guard let data = try fileHandle.read(upToCount: 4096), !data.isEmpty else { break }
                buffer.append(data)

                while let range = buffer.range(of: Data([10])) {
                    let lineData = buffer.subdata(in: 0..<range.lowerBound)
                    buffer.removeSubrange(0...range.lowerBound)

                    if let line = String(data: lineData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty {
                        // Filter noise — Python warnings, pip output, etc.
                        if line.contains("Error") || line.contains("error")
                            || line.contains("Traceback") || line.contains("Exception") {
                            log.error("stderr: \(line)", context: "Daemon")
                        } else {
                            log.warning("stderr: \(line)", context: "Daemon")
                        }
                    }
                }
            } catch {
                break
            }
        }
    }

    // MARK: - Parse Daemon Output

    private func parseDaemonLine(_ line: String) async {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let response = json["response"] as? [String: Any] else {
            log.warning("Non-JSON daemon output: \(line.prefix(200))", context: "Daemon")
            return
        }

        let stage = response["stage"] as? String ?? "unknown"
        let status = response["status"] as? String ?? ""
        log.info("Daemon event: stage=\(stage) status=\(status)", context: "Daemon")

        DispatchQueue.main.async {
            for cb in self.progressCallbacks {
                cb(response)
            }

            if let stageEnum = GenerationStatus(rawValue: stage) {
                if stageEnum == .loadingPipeline {
                    if status == "done" {
                        self.isWarmingUp = false
                        self.isReady = true
                        self.lastDaemonError = nil
                        self.log.success("Pipeline loaded — daemon ready", context: "Daemon")
                    }
                } else if stageEnum == .shutdown {
                    self.isReady = false
                    self.isOffline = true
                } else if stageEnum == .failed {
                    let reason = response["reason"] as? String ?? "unknown"
                    let message = response["message"] as? String ?? "No details"
                    self.lastDaemonError = "[\(reason)] \(message)"
                    self.log.error("Generation failed: \(reason) — \(message)", context: "Daemon")
                }
            }
        }
    }
}
