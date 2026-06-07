import SwiftUI

/// Settings tab that shows disk usage for every location the app writes to
/// and lets users selectively or fully remove them.
struct CleanupSettingsTab: View {
    private let cleanup = CleanupService.shared
    
    @State private var backendSize: String = "Calculating…"
    @State private var generationsSize: String = "Calculating…"
    @State private var modelCacheSize: String = "Calculating…"
    @State private var showFullUninstallAlert = false
    @State private var actionMessage: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Cleanup & Uninstall")
                .font(.title2).bold()
            
            Text("Remove downloaded data to free disk space. Trellis Studio keeps all files in known locations so nothing is left behind.")
                .font(.body)
                .foregroundColor(Theme.slateGray)
            
            // Individual cleanup rows
            VStack(spacing: 0) {
                cleanupRow(
                    icon: "server.rack",
                    title: "Backend Environment",
                    subtitle: "Python venv, cloned repos, build artifacts",
                    size: backendSize,
                    action: {
                        try cleanup.removeBackend()
                        OnboardingService.shared.isCompleted = false
                        refreshSizes()
                        actionMessage = "Backend removed."
                    }
                )
                
                Divider().padding(.horizontal, 16)
                
                cleanupRow(
                    icon: "cube.box",
                    title: "Generated Models",
                    subtitle: "GLB/OBJ outputs and input image copies",
                    size: generationsSize,
                    action: {
                        try cleanup.removeGenerations()
                        refreshSizes()
                        actionMessage = "Generated models removed."
                    }
                )
                
                Divider().padding(.horizontal, 16)
                
                cleanupRow(
                    icon: "arrow.down.circle",
                    title: "Model Weights Cache",
                    subtitle: "TRELLIS, DINOv3, RMBG weights in ~/.cache/huggingface",
                    size: modelCacheSize,
                    action: {
                        try cleanup.removeTrellisModelCache()
                        refreshSizes()
                        actionMessage = "Model cache cleared."
                    }
                )
            }
            .background(Color.white.opacity(0.02))
            .cornerRadius(Theme.CornerRadius.card)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.card)
                    .stroke(Theme.border, lineWidth: 1)
            )
            
            if let msg = actionMessage {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Theme.successGreen)
                    Text(msg)
                        .foregroundColor(Theme.successGreen)
                }
                .transition(.opacity)
            }
            
            // Full uninstall
            VStack(alignment: .leading, spacing: 12) {
                Text("Full Uninstall")
                    .font(.headline)
                Text("Removes all of the above plus preferences and history database. The app will reset to a fresh first-launch state.")
                    .font(.caption)
                    .foregroundColor(Theme.slateGray)
                
                Button(action: { showFullUninstallAlert = true }) {
                    HStack {
                        Image(systemName: "trash.fill")
                        Text("Remove Everything")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Theme.errorRed)
                    .foregroundColor(.white)
                    .cornerRadius(Theme.CornerRadius.button)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(Theme.errorRed.opacity(0.05))
            .cornerRadius(Theme.CornerRadius.card)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.card)
                    .stroke(Theme.errorRed.opacity(0.3), lineWidth: 1)
            )
        }
        .onAppear { refreshSizes() }
        .alert("Remove Everything?", isPresented: $showFullUninstallAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Remove Everything", role: .destructive) {
                do {
                    try cleanup.removeEverything()
                    OnboardingService.shared.isCompleted = false
                    refreshSizes()
                    actionMessage = "All data removed. Restart the app to set up again."
                } catch {
                    actionMessage = "Error: \(error.localizedDescription)"
                }
            }
        } message: {
            Text("This will delete the backend environment, all generated models, cached model weights (~15 GB), preferences, and history. This cannot be undone.")
        }
    }
    
    // MARK: - Helpers
    
    private func cleanupRow(
        icon: String,
        title: String,
        subtitle: String,
        size: String,
        action: @escaping () throws -> Void
    ) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(Theme.accentIndigo)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(Theme.slateGray)
            }
            
            Spacer()
            
            Text(size)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(Theme.slateGray)
                .frame(width: 80, alignment: .trailing)
            
            Button("Remove") {
                do {
                    try action()
                } catch {
                    actionMessage = "Error: \(error.localizedDescription)"
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.1))
            .cornerRadius(6)
        }
        .padding(16)
    }
    
    private func refreshSizes() {
        let backendURL = cleanup.backendURL
        let generationsURL = cleanup.generationsURL
        let huggingFaceCacheURL = cleanup.huggingFaceCacheURL

        Task.detached {
            let service = CleanupService.shared
            let bSize = service.formattedSize(service.sizeOfDirectory(at: backendURL))
            let gSize = service.formattedSize(service.sizeOfDirectory(at: generationsURL))
            let mSize = service.formattedSize(service.sizeOfDirectory(at: huggingFaceCacheURL))

            await MainActor.run {
                backendSize = bSize
                generationsSize = gSize
                modelCacheSize = mSize
            }
        }
    }
}
