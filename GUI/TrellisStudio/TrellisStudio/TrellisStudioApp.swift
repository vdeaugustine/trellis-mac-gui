import SwiftUI
import SwiftData

@main
struct TrellisStudioApp: App {
    @StateObject private var onboardingService = OnboardingService.shared
    @StateObject private var daemonManager = DaemonManager.shared
    @StateObject private var generationService = GenerationService.shared
    @StateObject private var logger = AppLogger.shared

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

        log.info("Starting daemon from: \(backendPath)", context: "Daemon")
        daemonManager.startDaemon(trellisPath: backendPath)
    }
}
