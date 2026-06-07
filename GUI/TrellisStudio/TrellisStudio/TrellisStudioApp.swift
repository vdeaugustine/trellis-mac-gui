import SwiftUI
import SwiftData

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
        let daemonScript = onboardingService.backendDirectoryURL
            .appendingPathComponent("trellis_daemon.py").path

        guard FileManager.default.fileExists(atPath: pythonPath) else {
            log.error("Python venv not found at: \(pythonPath)", context: "Daemon")
            log.error("Run setup.sh first or re-run onboarding.", context: "Daemon")
            return
        }

        guard FileManager.default.fileExists(atPath: daemonScript) else {
            log.error("trellis_daemon.py not found at: \(daemonScript)", context: "Daemon")
            return
        }

        // Auto-sync daemon script from BackendBundle to deployed backend
        syncDaemonScript()

        log.info("Starting daemon from: \(backendPath)", context: "Daemon")
        daemonManager.startDaemon(trellisPath: backendPath)
    }

    /// Copies the latest trellis_daemon.py from BackendBundle to the deployed backend.
    private func syncDaemonScript() {
        let log = AppLogger.shared
        let destURL = onboardingService.backendDirectoryURL
            .appendingPathComponent("trellis_daemon.py")
        let fm = FileManager.default

        // Try multiple source locations
        let candidates: [URL] = [
            // 1. App bundle (production builds)
            Bundle.main
                .url(forResource: "BackendBundle", withExtension: nil)?
                .appendingPathComponent("trellis_daemon.py"),
            // 2. Source tree: #filePath is TrellisStudioApp.swift in TrellisStudio/
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent() // TrellisStudio/
                .appendingPathComponent("BackendBundle/trellis_daemon.py"),
            // 3. Source tree: from Services/ subdirectory
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("BackendBundle/trellis_daemon.py"),
        ].compactMap { $0 }

        guard let source = candidates.first(where: { fm.fileExists(atPath: $0.path) }) else {
            log.warning("Could not find BackendBundle daemon to sync. Tried: \(candidates.map(\.path))", context: "Daemon")
            return
        }

        do {
            if fm.fileExists(atPath: destURL.path) {
                try fm.removeItem(at: destURL)
            }
            try fm.copyItem(at: source, to: destURL)
            log.info("Synced daemon script from: \(source.lastPathComponent)", context: "Daemon")
        } catch {
            log.warning("Failed to sync daemon script: \(error.localizedDescription)", context: "Daemon")
        }
    }
}
