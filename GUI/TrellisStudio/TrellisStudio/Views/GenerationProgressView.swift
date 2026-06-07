import SwiftUI

/// Shows live generation progress during an active generation.
struct GenerationProgressView: View {
    @EnvironmentObject private var generation: GenerationService
    var record: GenerationRecord

    private let orderedStages: [GenerationStatus] = [
        .queued, .loadingPipeline, .samplingStructure, .samplingShape, .samplingTexture,
        .decodingShape, .decodingTexture, .extractingMesh, .bakingTexture
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Generation Progress")
                    .font(.headline)
                Spacer()
                if record.status == .failed || record.status == .failedWatchdog {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(Theme.errorRed)
                } else if record.status == .complete {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Theme.successGreen)
                } else {
                    ProgressView().controlSize(.small)
                }
            }

            // Stage list
            HStack(spacing: 4) {
                ForEach(orderedStages, id: \.self) { stage in
                    stageIndicator(stage)
                }
            }

            if let progress = generation.stageProgress,
               progress.stage == record.status,
               record.status != .failed,
               record.status != .failedWatchdog {
                stageProgressDetails(progress)
            }

            // Error message
            if record.status == .failed || record.status == .failedWatchdog,
               let errorMsg = record.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(Theme.errorRed)
                    Text(errorMsg)
                        .font(.caption)
                        .foregroundColor(Theme.errorRed)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
                .padding(10)
                .background(Theme.errorRed.opacity(0.1))
                .cornerRadius(Theme.CornerRadius.button)
            }

            // Stats when available
            if let verts = record.vertexCount, let tris = record.triangleCount {
                HStack(spacing: 16) {
                    Label("\(verts.formatted()) vertices", systemImage: "circle.grid.3x3")
                    Label("\(tris.formatted()) triangles", systemImage: "triangle")
                }
                .font(.caption)
                .foregroundColor(Theme.slateGray)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.02))
        .cornerRadius(Theme.CornerRadius.card)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.card)
                .stroke(progressBorderColor, lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func stageIndicator(_ stage: GenerationStatus) -> some View {
        let currentIndex = orderedStages.firstIndex(of: record.status) ?? -1
        let stageIndex = orderedStages.firstIndex(of: stage) ?? 0
        let isComplete = stageIndex < currentIndex
        let isCurrent = stage == record.status
        let isFailed = (record.status == .failed || record.status == .failedWatchdog)

        return VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(barColor(isComplete: isComplete, isCurrent: isCurrent, isFailed: isFailed))
                .frame(height: 4)
            Text(stage.displayName)
                .font(.system(size: 8))
                .foregroundColor(isCurrent ? .white : Theme.slateGray)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func stageProgressDetails(_ progress: GenerationStageProgress) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(progress.message)
                    .font(.caption)
                    .foregroundColor(Theme.slateGray)
                    .lineLimit(1)
                Spacer()
                if progress.total > 0 {
                    Text("\(progress.current)/\(progress.total)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(Theme.slateGray)
                }
            }

            if progress.total > 0 {
                ProgressView(value: progress.fraction, total: 1)
                    .progressViewStyle(.linear)
                    .tint(Theme.accentIndigo)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(Theme.accentIndigo)
            }
        }
        .padding(.top, 2)
    }

    private func barColor(isComplete: Bool, isCurrent: Bool, isFailed: Bool) -> Color {
        if isFailed && isCurrent { return Theme.errorRed }
        if isComplete { return Theme.successGreen }
        if isCurrent { return Theme.accentIndigo }
        return Color.white.opacity(0.1)
    }

    private var progressBorderColor: Color {
        switch record.status {
        case .failed, .failedWatchdog: return Theme.errorRed.opacity(0.3)
        case .complete: return Theme.successGreen.opacity(0.3)
        default: return Theme.border
        }
    }
}
