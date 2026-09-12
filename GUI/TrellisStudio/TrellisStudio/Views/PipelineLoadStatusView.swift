import SwiftUI

/// Displays detailed live status for Python daemon startup and pipeline loading.
struct PipelineLoadStatusView: View {
    @EnvironmentObject private var daemon: DaemonManager

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            VStack(alignment: .leading, spacing: 12) {
                if let progress = daemon.pipelineLoadProgress {
                    progressContent(progress, now: context.date)
                } else {
                    startupContent
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.025))
            .cornerRadius(Theme.CornerRadius.card)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.card)
                    .stroke(Theme.warningAmber.opacity(0.25), lineWidth: 1)
            )
        }
    }

    private func progressContent(_ progress: DaemonPipelineLoadProgress, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Theme.warningAmber)
                    .frame(width: 8, height: 8)
                Text("Pipeline Load")
                    .font(.headline)
                Text("\(progress.percent)%")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(Theme.warningAmber)
                Spacer()
                Text(progress.stepText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(Theme.slateGray)
            }

            ProgressView(value: progress.fraction, total: 1)
                .progressViewStyle(.linear)
                .tint(Theme.warningAmber)

            VStack(alignment: .leading, spacing: 4) {
                Text(progress.message)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .lineLimit(2)
                if let detail = progress.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(Theme.slateGray)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }

            HStack(spacing: 10) {
                PipelineMetricView(
                    title: "Total",
                    value: progress.totalElapsed(at: now).pipelineDurationText
                )
                PipelineMetricView(
                    title: "Step",
                    value: progress.stepElapsed(at: now).pipelineDurationText
                )
                PipelineMetricView(
                    title: "Last Update",
                    value: progress.lastUpdateAge(at: now).pipelineDurationText
                )
                PipelineMetricView(title: "Phase", value: progress.phase)
            }

            recentConsoleLines
        }
    }

    private var startupContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Theme.warningAmber)
                    .frame(width: 8, height: 8)
                Text("Backend Startup")
                    .font(.headline)
                Spacer()
            }
            Text(daemon.connectionStatus ?? "Waiting for backend status")
                .font(.subheadline)
                .foregroundColor(Theme.slateGray)
                .textSelection(.enabled)
            recentConsoleLines
        }
    }

    @ViewBuilder
    private var recentConsoleLines: some View {
        let lines = daemon.consoleOutput.suffix(5)
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(consoleColor(for: line))
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.28))
            .cornerRadius(Theme.CornerRadius.button)
        }
    }

    private func consoleColor(for line: String) -> Color {
        if line.contains("Error") || line.contains("FAILED") || line.contains("Traceback") {
            return Theme.errorRed
        }
        if line.contains("ready") || line.contains("loaded") || line.contains("OK") {
            return Theme.successGreen.opacity(0.9)
        }
        if line.contains("[daemon-detail]") {
            return Theme.slateGray
        }
        return Color.white.opacity(0.72)
    }
}

private struct PipelineMetricView: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Theme.slateGray.opacity(0.75))
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.white.opacity(0.035))
        .cornerRadius(Theme.CornerRadius.button)
    }
}
