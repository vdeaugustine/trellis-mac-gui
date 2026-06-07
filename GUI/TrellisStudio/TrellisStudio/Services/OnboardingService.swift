import Foundation

/// Represents the result status of a single installation log line.
enum InstallLogLevel: String {
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
    case success = "OK"
}

/// A single log entry from the installation process.
struct InstallLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: InstallLogLevel
    let message: String
    
    init(_ level: InstallLogLevel, _ message: String) {
        self.timestamp = Date()
        self.level = level
        self.message = message
    }
}

/// Overall status of the environment installation.
enum InstallStatus: Equatable {
    case idle
    case installing
    case succeeded
    case failed(String)
}

/// A service that handles the initial application setup and environment installation.
///
/// Use `OnboardingService` to verify the user's disk space, install the Python backend,
/// and ensure all required dependencies are available before the application launches.
final class OnboardingService: ObservableObject {
    static let shared = OnboardingService()
    
    @Published var isCompleted: Bool {
        didSet { UserDefaults.standard.set(isCompleted, forKey: "onboardingCompleted") }
    }
    
    private init() {
        self.isCompleted = UserDefaults.standard.bool(forKey: "onboardingCompleted")
    }
    
    // MARK: - Disk Space
    
    /// Checks the available disk space on the startup volume.
    ///
    /// - Returns: The available space in gigabytes (GB).
    func checkDiskSpace() -> Double {
        let fileURL = URL(fileURLWithPath: "/")
        do {
            let values = try fileURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let capacity = values.volumeAvailableCapacityForImportantUsage {
                return Double(capacity) / (1024 * 1024 * 1024)
            }
        } catch {
            return 0.0
        }
        return 0.0
    }
    
    // MARK: - Environment Check
    
    /// Verifies that all required scripts and directories exist in the backend installation folder.
    ///
    /// - Returns: `true` if the environment is fully installed; otherwise, `false`.
    func checkEnvironmentInstalled() -> Bool {
        let fm = FileManager.default
        let base = backendDirectoryURL
        let requiredPaths = [
            ".venv/bin/python",
            "generate.py",
            "trellis_daemon.py",
            "daemon_generation.py",
            "daemon_legacy.py",
            "daemon_memory.py",
            "daemon_pipeline.py",
            "daemon_server.py",
            "daemon_transport.py",
            "download_weights.py",
            "TRELLIS.2/trellis2/pipelines/base.py",
            "TRELLIS.2/trellis2/modules/sparse/conv/conv_none.py",
        ]
        return requiredPaths.allSatisfy {
            fm.fileExists(atPath: base.appendingPathComponent($0).path)
        }
    }
    
    var backendDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("com.vinware.trellis-studio/backend")
    }
    
    // MARK: - Bundle Location
    
    /// Resolves the BackendBundle from the app bundle or the source tree (dev mode).
    private func resolveBackendBundleURL() -> URL? {
        // 1. Check inside the compiled .app bundle
        if let bundled = Bundle.main.url(forResource: "BackendBundle", withExtension: nil) {
            return bundled
        }
        
        // 2. Dev fallback: look relative to the source tree
        //    When running from Xcode, __FILE__ is inside the source tree.
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Services/
            .deletingLastPathComponent() // TrellisStudio/
            .appendingPathComponent("BackendBundle")
        if FileManager.default.fileExists(atPath: sourceRoot.path) {
            return sourceRoot
        }
        
        // 3. Try the repo root (two levels above GUI/TrellisStudio)
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Services/
            .deletingLastPathComponent() // TrellisStudio/
            .deletingLastPathComponent() // TrellisStudio/
            .deletingLastPathComponent() // GUI/
        let repoScripts = ["setup.sh", "generate.py", "trellis_daemon.py"]
        let allExist = repoScripts.allSatisfy {
            FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent($0).path)
        }
        if allExist { return repoRoot }
        
        return nil
    }
    
    // MARK: - Install Environment
    
    /// Runs the full Python backend installation and streams structured log entries.
    ///
    /// This method copies the bundled scripts to the user's Application Support directory
    /// and executes the setup script to configure the Python environment.
    ///
    /// - Returns: An asynchronous stream of installation logs that can be displayed to the user.
    func installEnvironment() -> AsyncStream<InstallLogEntry> {
        AsyncStream { continuation in
            Task.detached { [self] in
                let fm = FileManager.default
                let backendURL = self.backendDirectoryURL
                
                // Step 1: Create target directory
                continuation.yield(InstallLogEntry(.info, "Creating backend directory…"))
                do {
                    try fm.createDirectory(at: backendURL, withIntermediateDirectories: true)
                    continuation.yield(InstallLogEntry(.success, "Directory ready: \(backendURL.path)"))
                } catch {
                    continuation.yield(InstallLogEntry(.error, "Failed to create directory: \(error.localizedDescription)"))
                    continuation.finish()
                    return
                }
                
                // Step 2: Locate and copy scripts
                continuation.yield(InstallLogEntry(.info, "Locating backend scripts…"))
                guard let sourceURL = self.resolveBackendBundleURL() else {
                    continuation.yield(InstallLogEntry(.error, "BackendBundle not found in app bundle or source tree."))
                    continuation.yield(InstallLogEntry(.info, "Searched: Bundle.main.resourceURL, source tree, repo root."))
                    continuation.finish()
                    return
                }
                continuation.yield(InstallLogEntry(.success, "Found scripts at: \(sourceURL.path)"))
                
                continuation.yield(InstallLogEntry(.info, "Copying files to Application Support…"))
                do {
                    let items = try fm.contentsOfDirectory(atPath: sourceURL.path)
                    for item in items {
                        let src = sourceURL.appendingPathComponent(item)
                        let dst = backendURL.appendingPathComponent(item)
                        if fm.fileExists(atPath: dst.path) {
                            try fm.removeItem(at: dst)
                        }
                        try fm.copyItem(at: src, to: dst)
                        continuation.yield(InstallLogEntry(.info, "  Copied: \(item)"))
                    }
                    continuation.yield(InstallLogEntry(.success, "All scripts copied."))
                } catch {
                    continuation.yield(InstallLogEntry(.error, "Copy failed: \(error.localizedDescription)"))
                    continuation.finish()
                    return
                }
                
                // Step 3: Verify setup.sh exists before running
                let setupPath = backendURL.appendingPathComponent("setup.sh")
                guard fm.fileExists(atPath: setupPath.path) else {
                    continuation.yield(InstallLogEntry(.error, "setup.sh not found at \(setupPath.path)"))
                    continuation.finish()
                    return
                }
                
                // Step 4: Make setup.sh executable
                do {
                    try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: setupPath.path)
                } catch {
                    continuation.yield(InstallLogEntry(.warning, "Could not chmod setup.sh: \(error.localizedDescription)"))
                }
                
                // Step 5: Run setup.sh
                continuation.yield(InstallLogEntry(.info, "Running setup.sh — this may take several minutes…"))
                
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = ["-l", "setup.sh"]
                process.currentDirectoryURL = backendURL
                process.environment = ProcessInfo.processInfo.environment
                
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe
                
                // Stream stdout
                stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard data.count > 0, let str = String(data: data, encoding: .utf8) else { return }
                    for line in str.components(separatedBy: "\n") where !line.isEmpty {
                        continuation.yield(InstallLogEntry(.info, line))
                    }
                }
                
                // Stream stderr
                stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard data.count > 0, let str = String(data: data, encoding: .utf8) else { return }
                    for line in str.components(separatedBy: "\n") where !line.isEmpty {
                        continuation.yield(InstallLogEntry(.warning, line))
                    }
                }
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    
                    let exitCode = process.terminationStatus
                    if exitCode == 0 {
                        continuation.yield(InstallLogEntry(.success, "Setup completed successfully."))
                    } else {
                        continuation.yield(InstallLogEntry(.error, "setup.sh exited with code \(exitCode)."))
                    }
                } catch {
                    continuation.yield(InstallLogEntry(.error, "Failed to launch setup.sh: \(error.localizedDescription)"))
                }
                
                continuation.finish()
            }
        }
    }
    
}
