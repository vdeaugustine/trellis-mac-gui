import SwiftUI

struct ContentView: View {
    @State private var selectedItem: String?

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedItem: $selectedItem)
                .navigationSplitViewColumnWidth(min: 250, ideal: 280, max: 320)
        } detail: {
            MainWorkspaceView()
        }
    }
}

struct MainWorkspaceView: View {
    @EnvironmentObject var daemon: DaemonManager
    @EnvironmentObject var generation: GenerationService
    @EnvironmentObject var logger: AppLogger
    @Environment(\.modelContext) private var modelContext

    @State private var inputImageURL: URL?
    @State private var parameters = GenerationParameters()

    var body: some View {
        VStack(spacing: 0) {
            // Error banner
            if logger.showErrorBanner, let errorMsg = logger.lastError {
                errorBanner(errorMsg)
            }

            // Daemon status bar
            daemonStatusBar

            HStack(spacing: 24) {
                InputPanel(inputImageURL: $inputImageURL)
                    .frame(maxWidth: .infinity)

                ParameterPanel(
                    parameters: parameters,
                    inputImageURL: $inputImageURL,
                    onGenerate: startGeneration
                )
                .frame(width: 320)
            }
            .padding(24)

            Divider()

            // Progress view during active generation
            if let active = generation.activeRecord {
                GenerationProgressView(record: active)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
            }

            ModelViewerPanel()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }

    // MARK: - Generate Action

    private func startGeneration() {
        let log = AppLogger.shared

        // Pre-flight: image selected?
        guard let imageURL = inputImageURL else {
            log.error("No image selected. Drag an image or click Browse.", context: "Generate")
            return
        }

        // Pre-flight: image file exists?
        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            log.error("Image file not found: \(imageURL.path)", context: "Generate")
            return
        }

        // Pre-flight: daemon ready?
        guard daemon.isReady else {
            if daemon.isWarmingUp {
                log.warning("Pipeline is still loading. Please wait for warmup to finish.", context: "Generate")
            } else if daemon.isOffline {
                log.error("Backend daemon is offline. Check Settings > General for installation status.", context: "Generate")
            } else {
                log.error("Daemon is not ready. Current state unknown.", context: "Generate")
            }
            return
        }

        // Pre-flight: not already generating?
        guard generation.activeRecord == nil else {
            log.warning("A generation is already in progress. Wait for it to finish.", context: "Generate")
            return
        }

        log.info("Starting generation: \(imageURL.lastPathComponent), seed=\(parameters.seed), pipeline=\(parameters.pipelineType)", context: "Generate")

        let record = GenerationRecord(
            inputImagePath: imageURL.path,
            seed: parameters.seed,
            pipelineType: parameters.pipelineType,
            textureSize: parameters.textureSize
        )

        generation.addToQueue(record: record, modelContext: modelContext)
    }

    // MARK: - Daemon Status

    private var daemonStatusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(daemonStatusColor)
                .frame(width: 8, height: 8)
            Text(daemonStatusText)
                .font(.caption)
                .foregroundColor(Theme.slateGray)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.02))
    }

    private var daemonStatusColor: Color {
        if daemon.isReady { return Theme.successGreen }
        if daemon.isWarmingUp { return Theme.warningAmber }
        return Theme.errorRed
    }

    private var daemonStatusText: String {
        if daemon.isReady { return "Backend Ready" }
        if daemon.isWarmingUp { return "Loading Pipeline…" }
        return "Backend Offline"
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.white)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.white)
                .lineLimit(2)
            Spacer()
            Button(action: { logger.dismissError() }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Theme.errorRed.opacity(0.9))
        .cornerRadius(Theme.CornerRadius.button)
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
