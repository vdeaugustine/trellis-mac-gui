import Darwin
import SwiftUI
import SwiftData

/// The main entry point for the Trellis Studio application.
///
/// `TrellisStudioApp` initializes the application's core services, manages the global
/// window group, and coordinates the display of the onboarding flow versus the main
/// workspace depending on the user's installation state.
@main
struct TrellisStudioApp: App {
    @StateObject private var onboardingService = OnboardingService.shared
    @StateObject private var daemonManager = DaemonManager.shared
    @StateObject private var generationService = GenerationService.shared
    @StateObject private var logger = AppLogger.shared

    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup {
            if onboardingService.isCompleted {
                ContentView()
                    .environmentObject(daemonManager)
                    .environmentObject(generationService)
                    .environmentObject(logger)
                    .onAppear { startDaemonIfNeeded() }
            } else {
                OnboardingView()
            }
        }
        .windowStyle(.hiddenTitleBar)
        .modelContainer(for: GenerationRecord.self)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    openWindow(id: "settings")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        Window("Trellis Studio Settings", id: "settings") {
            SettingsView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 750, height: 580)
    }

    private func startDaemonIfNeeded() {
        guard daemonManager.isOffline else { return }

        let backendPath = onboardingService.backendDirectoryURL.path
        let log = AppLogger.shared

        // Validate backend exists
        let pythonPath = onboardingService.backendDirectoryURL
            .appendingPathComponent(".venv/bin/python").path
        guard FileManager.default.fileExists(atPath: pythonPath) else {
            log.error("Python venv not found at: \(pythonPath)", context: "Daemon")
            log.error("Run setup.sh first or re-run onboarding.", context: "Daemon")
            return
        }

        // Auto-sync daemon files from BackendBundle to deployed backend.
        let daemonFilesChanged = syncDaemonFiles()

        let daemonScript = onboardingService.backendDirectoryURL
            .appendingPathComponent("trellis_daemon.py").path
        guard FileManager.default.fileExists(atPath: daemonScript) else {
            log.error("trellis_daemon.py not found at: \(daemonScript)", context: "Daemon")
            return
        }

        if daemonFilesChanged {
            terminateExistingDaemonForSyncedFiles()
        }

        log.info("Starting daemon from: \(backendPath)", context: "Daemon")
        daemonManager.startDaemon(trellisPath: backendPath)
    }

    /// Copies the latest daemon Python files from BackendBundle to the deployed backend.
    private func syncDaemonFiles() -> Bool {
        let log = AppLogger.shared
        let fm = FileManager.default

        let bundleCandidates: [URL] = [
            // 1. App bundle (production builds)
            Bundle.main.url(forResource: "BackendBundle", withExtension: nil),
            // 2. Source tree: #filePath is TrellisStudioApp.swift in TrellisStudio/
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent() // TrellisStudio/
                .appendingPathComponent("BackendBundle"),
            // 3. Source tree: from Services/ subdirectory
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("BackendBundle"),
        ].compactMap { $0 }

        guard let sourceDir = bundleCandidates.first(where: {
            fm.fileExists(atPath: $0.appendingPathComponent("trellis_daemon.py").path)
        }) else {
            log.warning("Could not find BackendBundle daemon files. Tried: \(bundleCandidates.map(\.path))", context: "Daemon")
            return false
        }

        let filenames = [
            "trellis_daemon.py",
            "daemon_generation.py",
            "daemon_legacy.py",
            "daemon_memory.py",
            "daemon_pipeline.py",
            "daemon_server.py",
            "daemon_transport.py",
        ]
        var changed = false
        for filename in filenames {
            let source = sourceDir.appendingPathComponent(filename)
            let dest = onboardingService.backendDirectoryURL.appendingPathComponent(filename)
            guard fm.fileExists(atPath: source.path) else {
                log.warning("Daemon file missing from BackendBundle: \(filename)", context: "Daemon")
                continue
            }
            do {
                if filesDiffer(source: source, dest: dest) {
                    if fm.fileExists(atPath: dest.path) {
                        try fm.removeItem(at: dest)
                    }
                    try fm.copyItem(at: source, to: dest)
                    changed = true
                    log.info("Synced daemon file: \(filename)", context: "Daemon")
                }
            } catch {
                log.warning("Failed to sync \(filename): \(error.localizedDescription)", context: "Daemon")
            }
        }
        return changed
    }

    private func filesDiffer(source: URL, dest: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: dest.path),
              let sourceData = try? Data(contentsOf: source),
              let destData = try? Data(contentsOf: dest) else {
            return true
        }
        return sourceData != destData
    }

    private func terminateExistingDaemonForSyncedFiles() {
        let appSupport = onboardingService.backendDirectoryURL.deletingLastPathComponent()
        let pidURL = appSupport.appendingPathComponent("daemon.pid")
        let portURL = appSupport.appendingPathComponent("daemon.port")
        guard let rawPID = try? String(contentsOf: pidURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
              let pid = Int32(rawPID) else {
            return
        }

        AppLogger.shared.info("Stopping stale daemon after backend sync", context: "Daemon")
        kill(pid, SIGTERM)
        try? FileManager.default.removeItem(at: pidURL)
        try? FileManager.default.removeItem(at: portURL)
    }
}
