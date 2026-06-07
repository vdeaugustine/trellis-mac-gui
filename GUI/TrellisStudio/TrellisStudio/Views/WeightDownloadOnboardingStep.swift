import SwiftUI

/// Onboarding step that pre-downloads all TRELLIS.2 model weights.
struct WeightDownloadOnboardingStep: View {
    @Binding var downloadStatus: InstallStatus
    @Binding var downloadLogs: [InstallLogEntry]
    @Binding var downloadProgress: WeightDownloadProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Download Model Weights")
                .font(.title2).bold()
            Text("TRELLIS.2 needs ~15 GB of model files from HuggingFace. This only happens once — future launches start instantly.")
                .font(.body)
                .foregroundColor(Theme.slateGray)

            // Progress card
            progressCard

            // Action button
            if downloadStatus == .idle || downloadStatus != .installing && downloadStatus != .succeeded {
                Button(action: { startDownload() }) {
                    HStack(spacing: 8) {
                        Image(systemName: downloadStatus == .idle
                              ? "arrow.down.circle.fill" : "arrow.clockwise")
                        Text(downloadStatus == .idle
                             ? "Download Weights" : "Retry Download")
                            .bold()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.accentGradient)
                    .foregroundColor(.white)
                    .cornerRadius(Theme.CornerRadius.button)
                }
                .buttonStyle(.plain)
            }

            // Log console
            if !downloadLogs.isEmpty {
                downloadLogConsole
            }
        }
    }

    // MARK: - Progress Card

    @ViewBuilder
    private var progressCard: some View {
        switch downloadStatus {
        case .idle:
            infoCard(
                icon: "arrow.down.doc",
                color: Theme.accentIndigo,
                title: "Ready to Download",
                subtitle: "10 model downloads (~15 GB total)"
            )
        case .installing:
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Downloading: \(downloadProgress.currentModel)")
                            .font(.headline)
                        Text("\(downloadProgress.completed)/\(downloadProgress.total) models")
                            .font(.caption)
                            .foregroundColor(Theme.slateGray)
                    }
                    Spacer()
                }

                ProgressView(
                    value: Double(downloadProgress.completed),
                    total: max(1, Double(downloadProgress.total))
                )
                .progressViewStyle(.linear)
                .tint(Theme.accentIndigo)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.accentIndigo.opacity(0.1))
            .cornerRadius(Theme.CornerRadius.card)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.card)
                    .stroke(Theme.accentIndigo.opacity(0.3), lineWidth: 1)
            )
        case .succeeded:
            infoCard(
                icon: "checkmark.circle.fill",
                color: Theme.successGreen,
                title: "All Weights Downloaded",
                subtitle: "Pipeline will load instantly on launch."
            )
        case .failed(let reason):
            infoCard(
                icon: "exclamationmark.triangle.fill",
                color: Theme.errorRed,
                title: "Download Failed",
                subtitle: reason
            )
        }
    }

    private func infoCard(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(color)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(Theme.slateGray)
                    .lineLimit(3)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08))
        .cornerRadius(Theme.CornerRadius.card)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.card)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Log Console

    private var downloadLogConsole: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "arrow.down.doc")
                    .font(.caption)
                Text("Download Log")
                    .font(.caption).bold()
                Spacer()
                Text("\(downloadLogs.count) entries")
                    .font(.caption2)
                    .foregroundColor(Theme.slateGray)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.03))

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(downloadLogs) { entry in
                            logRow(entry).id(entry.id)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 160)
                .onChange(of: downloadLogs.count) { _, _ in
                    if let last = downloadLogs.last {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(Color(hex: 0x0A0C12))
        .cornerRadius(Theme.CornerRadius.card)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.card)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    private func logRow(_ entry: InstallLogEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.level == .error ? "✖" : entry.level == .success ? "✔" : "▸")
                .font(.system(.caption2, design: .monospaced))
            Text(entry.message)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(logColor(entry.level))
                .textSelection(.enabled)
        }
    }

    private func logColor(_ level: InstallLogLevel) -> Color {
        switch level {
        case .info: return Theme.slateGray
        case .warning: return Theme.warningAmber
        case .error: return Theme.errorRed
        case .success: return Theme.successGreen
        }
    }

    // MARK: - Download Execution

    private func startDownload() {
        downloadStatus = .installing
        downloadLogs = []
        downloadProgress = WeightDownloadProgress()

        Task {
            await runWeightDownload()
        }
    }

    private func runWeightDownload() async {
        let backendURL = OnboardingService.shared.backendDirectoryURL
        let pythonPath = backendURL.appendingPathComponent(".venv/bin/python").path
        let scriptPath = backendURL.appendingPathComponent("download_weights.py").path

        guard FileManager.default.fileExists(atPath: pythonPath) else {
            await MainActor.run {
                appendLog(.error, "Python not found. Run Environment Setup first.")
                downloadStatus = .failed("Python venv not found")
            }
            return
        }

        guard FileManager.default.fileExists(atPath: scriptPath) else {
            await MainActor.run {
                appendLog(.error, "download_weights.py not found at \(scriptPath)")
                downloadStatus = .failed("Download script not found")
            }
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [scriptPath]
        process.currentDirectoryURL = backendURL

        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        let token = SettingsService.shared.hfToken
        if !token.isEmpty { env["HF_TOKEN"] = token }
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let str = String(data: data, encoding: .utf8) else { return }
            for line in str.components(separatedBy: "\n") where !line.isEmpty {
                DispatchQueue.main.async { self.parseLine(line) }
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let str = String(data: data, encoding: .utf8) else { return }
            for line in str.components(separatedBy: "\n") where !line.isEmpty {
                DispatchQueue.main.async { self.appendLog(.warning, line) }
            }
        }

        do {
            try process.run()
            process.waitUntilExit()

            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil

            await MainActor.run {
                if process.terminationStatus == 0 {
                    let hasErrors = downloadLogs.contains { $0.level == .error }
                    if hasErrors {
                        downloadStatus = .failed("Some downloads failed — check log")
                    } else {
                        downloadStatus = .succeeded
                    }
                } else {
                    downloadStatus = .failed("Download exited with code \(process.terminationStatus)")
                }
            }
        } catch {
            await MainActor.run {
                appendLog(.error, "Failed to run: \(error.localizedDescription)")
                downloadStatus = .failed(error.localizedDescription)
            }
        }
    }

    private func parseLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            DispatchQueue.main.async { self.appendLog(.info, line) }
            return
        }

        let stage = json["stage"] as? String ?? ""
        let status = json["status"] as? String ?? ""
        let message = json["message"] as? String ?? ""
        let model = json["model"] as? String ?? ""

        DispatchQueue.main.async {
            if status == "error" {
                appendLog(.error, message)
            } else if status == "gated" {
                appendLog(.warning, message)
            } else if status == "done" && stage == "download" {
                appendLog(.success, "✓ \(model)")
                downloadProgress.completed = json["current"] as? Int ?? downloadProgress.completed
            } else if status == "downloading" {
                appendLog(.info, message)
                downloadProgress.currentModel = model
                if let total = json["total"] as? Int { downloadProgress.total = total }
            } else if stage == "complete" {
                appendLog(status == "done" ? .success : .warning, message)
            } else if !message.isEmpty {
                appendLog(.info, message)
            }
        }
    }

    private func appendLog(_ level: InstallLogLevel, _ message: String) {
        downloadLogs.append(InstallLogEntry(level, message))
    }
}

/// Tracks weight download progress for the UI.
struct WeightDownloadProgress {
    var currentModel: String = ""
    var completed: Int = 0
    var total: Int = 10
}
