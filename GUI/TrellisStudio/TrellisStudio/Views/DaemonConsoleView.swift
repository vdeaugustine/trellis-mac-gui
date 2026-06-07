import SwiftUI

/// A collapsible console that shows live stderr output from the daemon process.
///
/// Displays during startup / pipeline loading so the user can see exactly what
/// the Python backend is doing (e.g., "Importing torch…", "Loading weights…").
struct DaemonConsoleView: View {
    @EnvironmentObject private var daemon: DaemonManager
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            consoleHeader
            if isExpanded {
                consoleBody
            }
        }
        .background(Color.black.opacity(0.4))
        .cornerRadius(Theme.CornerRadius.button)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.button)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    // MARK: - Header

    private var consoleHeader: some View {
        HStack(spacing: 6) {
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(Theme.slateGray)

                    Text("Backend Console")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(Theme.slateGray)
                }
            }
            .buttonStyle(.plain)

            if !daemon.consoleOutput.isEmpty {
                Text("(\(daemon.consoleOutput.count) lines)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(Theme.slateGray.opacity(0.6))
            }

            Spacer()

            if daemon.isOffline && !daemon.isWarmingUp {
                Button(action: restartDaemon) {
                    Label("Restart", systemImage: "arrow.clockwise")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(Theme.accentIndigo)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.accentIndigo.opacity(0.14))
                .cornerRadius(Theme.CornerRadius.button)
                .accessibilityIdentifier(AccessibilityID.daemonRestartButton)
            }

            if !isExpanded && isReceivingOutput {
                Circle()
                    .fill(Theme.successGreen)
                    .frame(width: 6, height: 6)
                    .opacity(pulseOpacity)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulseOpacity)
            }

            Image(systemName: "terminal")
                .font(.caption2)
                .foregroundColor(Theme.slateGray)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Body

    private var consoleBody: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(daemon.consoleOutput.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(lineColor(for: line))
                            .textSelection(.enabled)
                            .id(index)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 160)
            .onChange(of: daemon.consoleOutput.count) { _, newCount in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(newCount - 1, anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Helpers

    private var isReceivingOutput: Bool {
        !daemon.consoleOutput.isEmpty && !daemon.isReady
    }

    private var pulseOpacity: Double {
        isReceivingOutput ? 0.3 : 1.0
    }

    private func lineColor(for line: String) -> Color {
        if line.contains("Error") || line.contains("FAILED") || line.contains("Traceback") {
            return Theme.errorRed
        }
        if line.contains("[daemon]") {
            return Theme.accentIndigo.opacity(0.9)
        }
        if line.contains("OK") || line.contains("ready") || line.contains("loaded") {
            return Theme.successGreen.opacity(0.9)
        }
        return Color.white.opacity(0.6)
    }

    private func restartDaemon() {
        let backendPath = OnboardingService.shared.backendDirectoryURL.path
        AppLogger.shared.info("Restarting daemon…", context: "Daemon")
        daemon.startDaemon(trellisPath: backendPath)
    }
}
