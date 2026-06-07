import SwiftUI

/// Settings tab that shows all required models, their download status, sizes, and actions.
struct ModelManagementTab: View {
    @ObservedObject private var catalog = ModelCatalogService.shared
    @State private var showDeleteAlert = false
    @State private var pendingDeleteEntry: ModelCatalogEntry?
    @State private var actionMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            summaryCard
            modelList
            if let msg = actionMessage {
                actionBanner(msg)
            }
        }
        .onAppear { catalog.scan() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Model Weights")
                    .font(.title2).bold()
                Spacer()
                Button(action: { catalog.scan() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh")
                    }
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .disabled(catalog.isScanning)
            }
            Text("TRELLIS.2 requires 10 model checkpoints (~15 GB) stored in your HuggingFace cache.")
                .font(.body)
                .foregroundColor(Theme.slateGray)
        }
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        HStack(spacing: 24) {
            summaryMetric(
                icon: "checkmark.circle.fill",
                color: Theme.successGreen,
                value: "\(catalog.downloadedCount)/\(catalog.entries.count)",
                label: "Downloaded"
            )
            Divider().frame(height: 40)
            summaryMetric(
                icon: "internaldrive",
                color: Theme.accentIndigo,
                value: catalog.formattedTotalSize,
                label: "Disk Usage"
            )
            Divider().frame(height: 40)
            summaryMetric(
                icon: catalog.allDownloaded ? "checkmark.seal.fill" : "exclamationmark.triangle",
                color: catalog.allDownloaded ? Theme.successGreen : Theme.warningAmber,
                value: catalog.allDownloaded ? "Ready" : "\(catalog.missingCount) Missing",
                label: "Pipeline Status"
            )
            if catalog.isScanning {
                Divider().frame(height: 40)
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Scanning…")
                        .font(.caption)
                        .foregroundColor(Theme.slateGray)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.02))
        .cornerRadius(Theme.CornerRadius.card)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.card)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    private func summaryMetric(icon: String, color: Color, value: String, label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.headline)
                Text(label)
                    .font(.caption2)
                    .foregroundColor(Theme.slateGray)
            }
        }
    }

    // MARK: - Model List

    private var modelList: some View {
        VStack(spacing: 0) {
            // Group header: Core Checkpoints
            sectionHeader("Core Checkpoints", subtitle: "microsoft/TRELLIS.2-4B")
            let coreModels = catalog.entries.filter { !$0.isGated }
            ForEach(Array(coreModels.enumerated()), id: \.element.id) { index, entry in
                modelRow(entry)
                if index < coreModels.count - 1 {
                    Divider().padding(.leading, 56)
                }
            }

            Divider()

            // Group header: Auxiliary Models
            sectionHeader("Auxiliary Models", subtitle: "Gated — require HuggingFace access approval")
            let auxModels = catalog.entries.filter { $0.isGated }
            ForEach(Array(auxModels.enumerated()), id: \.element.id) { index, entry in
                modelRow(entry)
                if index < auxModels.count - 1 {
                    Divider().padding(.leading, 56)
                }
            }
        }
        .background(Color.white.opacity(0.02))
        .cornerRadius(Theme.CornerRadius.card)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.card)
                .stroke(Theme.border, lineWidth: 1)
        )
        .alert("Delete Model Cache?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                guard let entry = pendingDeleteEntry else { return }
                do {
                    try catalog.deleteModel(entry)
                    actionMessage = "Deleted \(entry.displayName)"
                } catch {
                    actionMessage = "Error: \(error.localizedDescription)"
                }
            }
        } message: {
            if let entry = pendingDeleteEntry {
                Text("This will delete the cached weights for \(entry.displayName) (\(entry.repoId)). You'll need to re-download them before generating.")
            }
        }
    }

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline).bold()
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(Theme.slateGray)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.02))
    }

    private func modelRow(_ entry: ModelCatalogEntry) -> some View {
        HStack(spacing: 12) {
            statusIcon(entry.status)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.displayName)
                        .font(.subheadline).bold()
                    roleBadge(entry.role)
                    if entry.isGated {
                        gatedBadge
                    }
                }
                Text(entry.repoId + "/" + entry.relativePath)
                    .font(.caption2)
                    .foregroundColor(Theme.slateGray)
                    .monospaced()
                    .lineLimit(1)
            }

            Spacer()

            // Size
            if entry.sizeBytes > 0 {
                Text(ByteCountFormatter.string(fromByteCount: entry.sizeBytes, countStyle: .file))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(Theme.slateGray)
                    .frame(width: 80, alignment: .trailing)
            } else {
                Text("—")
                    .font(.caption)
                    .foregroundColor(Theme.slateGray)
                    .frame(width: 80, alignment: .trailing)
            }

            // Actions
            if entry.status == .downloaded {
                Button(action: {
                    pendingDeleteEntry = entry
                    showDeleteAlert = true
                }) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(Theme.slateGray)
                }
                .buttonStyle(.plain)
                .help("Delete cached weights")
            } else if entry.isGated {
                Button(action: {
                    let url = URL(string: "https://huggingface.co/\(entry.repoId)")!
                    NSWorkspace.shared.open(url)
                }) {
                    Text("Request")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.accentIndigo.opacity(0.2))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Components

    @ViewBuilder
    private func statusIcon(_ status: ModelDownloadStatus) -> some View {
        switch status {
        case .downloaded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Theme.successGreen)
        case .missing:
            Image(systemName: "arrow.down.circle")
                .foregroundColor(Theme.slateGray)
        case .downloading:
            ProgressView().controlSize(.mini)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Theme.errorRed)
        }
    }

    private func roleBadge(_ role: String) -> some View {
        Text(role)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(roleColor(role).opacity(0.15))
            .foregroundColor(roleColor(role))
            .cornerRadius(4)
    }

    private var gatedBadge: some View {
        HStack(spacing: 2) {
            Image(systemName: "lock.fill")
                .font(.system(size: 8))
            Text("GATED")
                .font(.system(size: 9, weight: .semibold))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Theme.warningAmber.opacity(0.15))
        .foregroundColor(Theme.warningAmber)
        .cornerRadius(4)
    }

    private func roleColor(_ role: String) -> Color {
        switch role {
        case "Structure": return .cyan
        case "Shape": return .blue
        case "Texture": return .purple
        case "Image Understanding": return .orange
        case "Preprocessing": return .pink
        default: return Theme.slateGray
        }
    }

    private func actionBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Theme.successGreen)
            Text(message)
                .font(.caption)
                .foregroundColor(Theme.successGreen)
            Spacer()
            Button(action: { actionMessage = nil }) {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundColor(Theme.slateGray)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Theme.successGreen.opacity(0.08))
        .cornerRadius(Theme.CornerRadius.button)
        .transition(.opacity)
    }
}
