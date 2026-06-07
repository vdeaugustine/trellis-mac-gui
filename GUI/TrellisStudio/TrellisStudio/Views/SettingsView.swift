import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = SettingsService.shared
    @ObservedObject var onboarding = OnboardingService.shared
    
    @State private var activeTab = "General"
    
    var body: some View {
        HStack(spacing: 0) {
            // Sidebar Tabs
            VStack(alignment: .leading, spacing: 4) {
                Spacer().frame(height: 16)
                
                ForEach(["General", "Account", "Models", "Defaults", "Appearance", "Advanced", "Cleanup"], id: \.self) { tab in
                    Button(action: { activeTab = tab }) {
                        HStack {
                            Image(systemName: iconName(for: tab))
                                .frame(width: 20)
                            Text(tab)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(activeTab == tab ? Theme.accentIndigo : Color.clear)
                        .foregroundColor(activeTab == tab ? .white : .white.opacity(0.8))
                        .cornerRadius(Theme.CornerRadius.button)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                }
                
                Spacer()
                
                // System Status
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("System Ready")
                            .font(.caption).bold()
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Theme.successGreen)
                    }
                    
                    HStack(spacing: 12) {
                        Image(systemName: "cpu")
                            .font(.title)
                            .foregroundColor(Theme.accentIndigo)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(SystemInfoProvider.chipName)
                                .font(.caption).bold()
                            Text(SystemInfoProvider.memoryString)
                                .font(.caption2)
                                .foregroundColor(Theme.slateGray)
                            Text(SystemInfoProvider.macOSVersion)
                                .font(.caption2)
                                .foregroundColor(Theme.slateGray)
                        }
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.02))
                .cornerRadius(Theme.CornerRadius.card)
                .border(Theme.border, width: 1)
                .padding(12)
            }
            .frame(width: 200)
            .background(Color.white.opacity(0.01))
            .border(SeparatorShapeStyle(), width: 1)
            
            // Content
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if activeTab == "General" {
                            generalTab
                        } else if activeTab == "Account" {
                            accountTab
                        } else if activeTab == "Models" {
                            modelsTab
                        } else if activeTab == "Defaults" {
                            defaultsTab
                        } else if activeTab == "Appearance" {
                            appearanceTab
                        } else if activeTab == "Advanced" {
                            advancedTab
                        } else if activeTab == "Cleanup" {
                            cleanupTab
                        }
                    }
                    .padding(30)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .frame(
            minWidth: 600, idealWidth: 750, maxWidth: 1000,
            minHeight: 450, idealHeight: 580, maxHeight: 800
        )
        .onAppear {
            // Auto-populate token from HF cache if GUI field is empty
            if settings.hfToken.isEmpty,
               let cached = HFAuthService.shared.detectExistingToken() {
                settings.hfToken = cached
            }
            // Auto-validate and check gated access
            let token = HFAuthService.shared.resolveToken()
            if !token.isEmpty {
                Task {
                    await HFAuthService.shared.performValidation(token: token)
                    if HFAuthService.shared.isTokenValid {
                        await HFAuthService.shared.checkAllGatedAccess(token: token)
                    }
                }
            }
        }
    }
    
    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("General Settings")
                .font(.title2).bold()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Trellis Installation Path")
                    .font(.headline)
                HStack {
                    Text(onboarding.backendDirectoryURL.path)
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(6)
                    Spacer()
                }
                
                if onboarding.checkEnvironmentInstalled() {
                    Text("✓ Valid TRELLIS.2 environment detected")
                        .font(.caption)
                        .foregroundColor(Theme.successGreen)
                } else {
                    Text("✗ Environment not fully installed")
                        .font(.caption)
                        .foregroundColor(Theme.errorRed)
                }
            }

            Divider()

            backendManagementSection
        }
    }

    @ObservedObject private var daemon = DaemonManager.shared

    private var backendManagementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Backend Process")
                .font(.headline)

            HStack(spacing: 8) {
                Circle()
                    .fill(backendStatusColor)
                    .frame(width: 10, height: 10)
                Text(backendStatusText)
                    .font(.subheadline)
                    .foregroundColor(Theme.slateGray)
                Spacer()
            }

            HStack(spacing: 12) {
                Button("Stop Backend") {
                    daemon.stopDaemon()
                }
                .disabled(daemon.isOffline)

                Button("Restart Backend") {
                    daemon.stopDaemon()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        let path = onboarding.backendDirectoryURL.path
                        daemon.startDaemon(trellisPath: path)
                    }
                }
            }

            Text("The backend daemon persists between app sessions to avoid reloading the pipeline (~14GB). Stop it to free GPU memory.")
                .font(.caption)
                .foregroundColor(Theme.slateGray)
        }
    }

    private var backendStatusColor: Color {
        if daemon.isPipelineLoaded { return Theme.successGreen }
        if daemon.isReady { return Theme.warningAmber }
        if daemon.isWarmingUp { return Theme.warningAmber }
        return Theme.errorRed
    }

    private var backendStatusText: String {
        if daemon.isPipelineLoaded { return "Running — Pipeline loaded" }
        if daemon.isReady { return "Running — Pipeline not yet loaded" }
        if daemon.isWarmingUp { return "Loading pipeline…" }
        return "Offline"
    }
    
    private var accountTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Account Settings")
                .font(.title2).bold()

            // Token section
            VStack(alignment: .leading, spacing: 8) {
                Text("HuggingFace Access Token")
                    .font(.headline)

                if HFAuthService.shared.isTokenValid {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(Theme.successGreen)
                        Text("Authenticated as \(HFAuthService.shared.username)")
                            .foregroundColor(Theme.successGreen)
                    }
                }

                SecureField("hf_...", text: $settings.hfToken)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 12) {
                    Button("Validate Token") {
                        Task {
                            let token = HFAuthService.shared.resolveToken()
                            await HFAuthService.shared.performValidation(token: token)
                            if HFAuthService.shared.isTokenValid {
                                _ = HFAuthService.shared.saveTokenToHFCache(token)
                                await HFAuthService.shared.checkAllGatedAccess(token: token)
                            }
                        }
                    }
                    .disabled(HFAuthService.shared.resolveToken().isEmpty || HFAuthService.shared.isValidating)

                    if HFAuthService.shared.isValidating {
                        ProgressView().controlSize(.small)
                    }
                }

                Text("Also saved to ~/.cache/huggingface/token for Python tools.")
                    .font(.caption)
                    .foregroundColor(Theme.slateGray)
            }
            .onAppear {
                // Auto-populate from cache if GUI field is empty
                if settings.hfToken.isEmpty,
                   let cached = HFAuthService.shared.detectExistingToken() {
                    settings.hfToken = cached
                }
                // Auto-check gated access on appear
                let token = HFAuthService.shared.resolveToken()
                if !token.isEmpty && !HFAuthService.shared.isTokenValid {
                    Task {
                        await HFAuthService.shared.performValidation(token: token)
                        if HFAuthService.shared.isTokenValid {
                            await HFAuthService.shared.checkAllGatedAccess(token: token)
                        }
                    }
                }
            }

            Divider()

            // Gated access section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Gated Model Access")
                        .font(.headline)
                    Spacer()
                    Button("Refresh") {
                        Task {
                            let token = HFAuthService.shared.resolveToken()
                            await HFAuthService.shared.checkAllGatedAccess(token: token)
                        }
                    }
                    .font(.caption)
                    .disabled(HFAuthService.shared.resolveToken().isEmpty)
                }

                ForEach(HFAuthService.shared.gatedModels) { model in
                    HStack(spacing: 10) {
                        accessIcon(for: model.status)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(model.displayName)
                                .font(.subheadline)
                            Text(model.repoId)
                                .font(.caption2)
                                .foregroundColor(Theme.slateGray)
                                .monospaced()
                        }
                        Spacer()
                        if model.status == .denied {
                            Button("Request") {
                                NSWorkspace.shared.open(model.requestURL)
                            }
                            .font(.caption)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func accessIcon(for status: GatedModelStatus) -> some View {
        switch status {
        case .granted:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Theme.successGreen)
        case .denied:
            Image(systemName: "lock.fill")
                .foregroundColor(Theme.warningAmber)
        case .checking:
            ProgressView().controlSize(.mini)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Theme.errorRed)
        case .unknown:
            Image(systemName: "circle.dashed")
                .foregroundColor(Theme.slateGray)
        }
    }
    
    private var defaultsTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Generation Defaults")
                .font(.title2).bold()
            
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Default Pipeline Resolution")
                        .font(.headline)
                    Picker("Pipeline Type", selection: $settings.defaultPipelineType) {
                        Text("512 (Fast)").tag("512")
                        Text("1024 (Balanced)").tag("1024")
                        Text("1024 Cascade (High Quality)").tag("1024_cascade")
                    }
                    .pickerStyle(.segmented)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Default Texture Resolution")
                        .font(.headline)
                    Picker("Texture Size", selection: $settings.defaultTextureSize) {
                        Text("512").tag(512)
                        Text("1024").tag(1024)
                        Text("2048").tag(2048)
                    }
                    .pickerStyle(.segmented)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Default Seed")
                        .font(.headline)
                    TextField("42", value: $settings.defaultSeed, formatter: NumberFormatter())
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }
            }
        }
    }
    
    private var appearanceTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Appearance")
                .font(.title2).bold()
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Theme Mode")
                    .font(.headline)
                
                HStack(spacing: 16) {
                    VStack {
                        Image(systemName: "moon.stars.fill")
                            .font(.largeTitle)
                            .foregroundColor(Theme.accentIndigo)
                            .padding(16)
                            .background(Color.white.opacity(0.04))
                            .cornerRadius(Theme.CornerRadius.card)
                            .border(Theme.accentIndigo, width: 2)
                        Text("Dark Mode")
                            .font(.caption).bold()
                    }
                    
                    VStack {
                        Image(systemName: "sun.max.fill")
                            .font(.largeTitle)
                            .foregroundColor(.gray)
                            .padding(16)
                            .background(Color.white.opacity(0.02))
                            .cornerRadius(Theme.CornerRadius.card)
                        Text("Light Mode")
                            .font(.caption)
                    }
                }
            }
        }
    }
    
    private var advancedTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Advanced Environment Overrides")
                .font(.title2).bold()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Environment Variables")
                    .font(.headline)
                TextEditor(text: $settings.advancedEnvVars)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 100)
                    .border(Theme.border, width: 1)
                
                Text("Format: KEY=VALUE. One per line. E.g. SPARSE_CONV_BACKEND=none")
                    .font(.caption)
                    .foregroundColor(Theme.slateGray)
            }
        }
    }
    
    private var cleanupTab: some View {
        CleanupSettingsTab()
    }
    
    private var modelsTab: some View {
        ModelManagementTab()
    }

    private func iconName(for tab: String) -> String {
        switch tab {
        case "General": return "gearshape"
        case "Account": return "person"
        case "Models": return "cube.box"
        case "Defaults": return "slider.horizontal.3"
        case "Appearance": return "paintbrush"
        case "Advanced": return "cpu"
        case "Cleanup": return "trash"
        default: return "gearshape"
        }
    }
}
