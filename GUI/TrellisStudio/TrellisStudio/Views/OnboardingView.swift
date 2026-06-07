import SwiftUI

struct OnboardingView: View {
    @ObservedObject var onboarding = OnboardingService.shared
    @ObservedObject var settings = SettingsService.shared
    
    @State private var currentStep = 1
    @State private var hfToken = ""
    @State private var tokenValid = false
    @State private var validatingToken = false
    
    @State private var installLogs: [InstallLogEntry] = []
    @State private var installStatus: InstallStatus = .idle
    
    var body: some View {
        HStack(spacing: 0) {
            // Sidebar steps
            VStack(alignment: .leading, spacing: 20) {
                Spacer().frame(height: 20)
                
                ForEach(1...5, id: \.self) { step in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(currentStep == step ? Theme.accentIndigo : (currentStep > step ? Theme.successGreen : Color.white.opacity(0.15)))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Text("\(step)")
                                    .font(.system(.body, design: .rounded))
                                    .bold()
                                    .foregroundColor(.white)
                            )
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stepTitle(for: step))
                                .font(.headline)
                                .foregroundColor(currentStep == step ? .white : .white.opacity(0.6))
                            Text(stepSubtitle(for: step))
                                .font(.caption)
                                .foregroundColor(currentStep == step ? .white.opacity(0.8) : .white.opacity(0.4))
                        }
                    }
                    .padding(.horizontal, 20)
                    .opacity(currentStep == step ? 1.0 : 0.6)
                }
                
                Spacer()
                
                // Logo
                VStack(alignment: .leading, spacing: 4) {
                    Text("T R E L L I S . 2")
                        .font(.system(.subheadline, design: .monospaced))
                        .bold()
                        .foregroundColor(Theme.accentIndigo)
                    Text("On Apple Silicon")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .frame(width: 250)
            .background(Color.white.opacity(0.03))
            .border(SeparatorShapeStyle(), width: 1)
            
            // Content Pane
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if currentStep == 1 {
                            welcomeStep
                        } else if currentStep == 2 {
                            diskSpaceStep
                        } else if currentStep == 3 {
                            environmentSetupStep
                        } else if currentStep == 4 {
                            huggingFaceStep
                        } else if currentStep == 5 {
                            readyStep
                        }
                    }
                    .padding(40)
                }
                
                Spacer()
                
                // Footer buttons
                HStack {
                    if currentStep > 1 {
                        Button("Back") {
                            withAnimation(.smoothSpring) {
                                currentStep -= 1
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(Theme.CornerRadius.button)
                        .disabled(installStatus == .installing)
                    }
                    
                    Spacer()
                    
                    Button(currentStep == 5 ? "Launch" : "Continue") {
                        if currentStep == 5 {
                            settings.hfToken = hfToken
                            onboarding.isCompleted = true
                        } else {
                            withAnimation(.smoothSpring) {
                                currentStep += 1
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .background(Theme.accentGradient)
                    .foregroundColor(.white)
                    .cornerRadius(Theme.CornerRadius.button)
                    .disabled(shouldDisableNextButton)
                }
                .padding(24)
                .background(Color.white.opacity(0.01))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .onAppear {
            hfToken = settings.hfToken
            tokenValid = !hfToken.isEmpty
            if onboarding.checkEnvironmentInstalled() {
                installStatus = .succeeded
            }
        }
    }
    
    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to Trellis Studio")
                .font(.system(size: 32, weight: .bold))
            Text("Let's get everything ready to turn your images into beautiful 3D models.")
                .font(.body)
                .foregroundColor(Theme.slateGray)
            
            Spacer().frame(height: 20)
            
            HStack(spacing: 20) {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 64))
                    .foregroundColor(Theme.accentIndigo)
                    .pulse()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Highly Optimized 3D Generation")
                        .font(.headline)
                    Text("Trellis Studio uses a persistent backend process to load weights once and generate meshes in seconds, avoiding cold starts.")
                        .font(.subheadline)
                        .foregroundColor(Theme.slateGray)
                }
            }
            .padding(20)
            .background(Color.white.opacity(0.02))
            .cornerRadius(Theme.CornerRadius.card)
        }
    }
    
    private var diskSpaceStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Disk Space Check")
                .font(.title2).bold()
            Text("Ensure you have enough free space to download weights and generate output.")
                .font(.body)
                .foregroundColor(Theme.slateGray)
            
            let freeSpace = onboarding.checkDiskSpace()
            let enoughSpace = freeSpace >= 15.0
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Available:")
                    Spacer()
                    Text(String(format: "%.1f GB available", freeSpace))
                        .bold()
                }
                
                ProgressView(value: min(freeSpace, 50.0), total: 50.0)
                    .progressViewStyle(.linear)
                    .tint(enoughSpace ? Theme.accentIndigo : Theme.errorRed)
                
                HStack {
                    Text("Required: 15 GB")
                        .font(.caption)
                        .foregroundColor(Theme.slateGray)
                    Spacer()
                    if enoughSpace {
                        Text("Enough space")
                            .font(.caption)
                            .foregroundColor(Theme.successGreen)
                    } else {
                        Text("Low disk space")
                            .font(.caption)
                            .foregroundColor(Theme.errorRed)
                    }
                }
            }
            .padding(20)
            .background(Color.white.opacity(0.02))
            .cornerRadius(Theme.CornerRadius.card)
        }
    }
    
    private var environmentSetupStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Environment Setup")
                .font(.title2).bold()
            Text("Trellis Studio will automatically install the Python backend, clone required repositories, and compile Metal acceleration.")
                .font(.body)
                .foregroundColor(Theme.slateGray)
            
            // Status banner
            statusBanner
            
            // Install / Retry button
            if installStatus == .idle || installStatus != .installing && installStatus != .succeeded {
                Button(action: { startInstallation() }) {
                    HStack(spacing: 8) {
                        Image(systemName: installStatus == .idle ? "arrow.down.circle.fill" : "arrow.clockwise")
                        Text(installStatus == .idle ? "Install Environment" : "Retry Installation")
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
            if !installLogs.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    // Console header
                    HStack {
                        Image(systemName: "terminal")
                            .font(.caption)
                        Text("Installation Log")
                            .font(.caption).bold()
                        Spacer()
                        Text("\(installLogs.count) entries")
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
                                ForEach(installLogs) { entry in
                                    logEntryRow(entry)
                                        .id(entry.id)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 220)
                        .onChange(of: installLogs.count) { _, _ in
                            if let last = installLogs.last {
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
                        .stroke(logBorderColor, lineWidth: 1)
                )
            }
        }
    }
    
    @ViewBuilder
    private var statusBanner: some View {
        switch installStatus {
        case .idle:
            EmptyView()
        case .installing:
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                Text("Installing — this may take several minutes…")
                    .font(.subheadline)
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
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(Theme.successGreen)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Installation Complete")
                        .font(.headline)
                        .foregroundColor(Theme.successGreen)
                    Text("Backend environment is ready.")
                        .font(.caption)
                        .foregroundColor(Theme.slateGray)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.successGreen.opacity(0.08))
            .cornerRadius(Theme.CornerRadius.card)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.card)
                    .stroke(Theme.successGreen.opacity(0.3), lineWidth: 1)
            )
        case .failed(let reason):
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundColor(Theme.errorRed)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Installation Failed")
                        .font(.headline)
                        .foregroundColor(Theme.errorRed)
                    Text(reason)
                        .font(.caption)
                        .foregroundColor(Theme.slateGray)
                        .lineLimit(3)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.errorRed.opacity(0.08))
            .cornerRadius(Theme.CornerRadius.card)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.card)
                    .stroke(Theme.errorRed.opacity(0.3), lineWidth: 1)
            )
        }
    }
    
    private func logEntryRow(_ entry: InstallLogEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(logIcon(for: entry.level))
                .font(.system(.caption2, design: .monospaced))
            Text(entry.message)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(logColor(for: entry.level))
                .textSelection(.enabled)
        }
    }
    
    private func logIcon(for level: InstallLogLevel) -> String {
        switch level {
        case .info: return "▸"
        case .warning: return "⚠"
        case .error: return "✖"
        case .success: return "✔"
        }
    }
    
    private func logColor(for level: InstallLogLevel) -> Color {
        switch level {
        case .info: return Theme.slateGray
        case .warning: return Theme.warningAmber
        case .error: return Theme.errorRed
        case .success: return Theme.successGreen
        }
    }
    
    private var logBorderColor: Color {
        switch installStatus {
        case .failed: return Theme.errorRed.opacity(0.3)
        case .succeeded: return Theme.successGreen.opacity(0.3)
        default: return Theme.border
        }
    }
    
    private func startInstallation() {
        installStatus = .installing
        installLogs = []
        
        Task {
            let stream = onboarding.installEnvironment()
            for await entry in stream {
                await MainActor.run {
                    installLogs.append(entry)
                }
            }
            
            await MainActor.run {
                let success = onboarding.checkEnvironmentInstalled()
                if success {
                    installStatus = .succeeded
                } else {
                    let lastError = installLogs.last(where: { $0.level == .error })?.message ?? "Unknown error"
                    installStatus = .failed(lastError)
                }
            }
        }
    }
    
    private var huggingFaceStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("HuggingFace Access Token")
                .font(.title2).bold()
            Text("Required to download gated model weights. Get one from huggingface.co.")
                .font(.body)
                .foregroundColor(Theme.slateGray)
            
            HStack {
                SecureField("hf_...", text: $hfToken)
                    .textFieldStyle(.roundedBorder)
                
                Button(validatingToken ? "Testing..." : "Test Token") {
                    validatingToken = true
                    Task {
                        let ok = await onboarding.validateHFToken(hfToken)
                        await MainActor.run {
                            tokenValid = ok
                            validatingToken = false
                        }
                    }
                }
                .disabled(validatingToken || hfToken.isEmpty)
            }
            
            if tokenValid {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Theme.successGreen)
                    Text("Token valid and authorized")
                        .foregroundColor(Theme.successGreen)
                }
            } else if !hfToken.isEmpty && !validatingToken {
                HStack {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Theme.errorRed)
                        .foregroundColor(Theme.errorRed)
                    Text("Invalid token or authentication failed")
                        .foregroundColor(Theme.errorRed)
                }
            }
        }
    }
    
    private var readyStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Ready to Generate")
                .font(.title2).bold()
            Text("You're all set! Trellis Studio is ready to go.")
                .font(.body)
                .foregroundColor(Theme.slateGray)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Backend Engine:")
                        .foregroundColor(Theme.slateGray)
                    Spacer()
                    Text("Installed and Ready")
                        .foregroundColor(Theme.successGreen)
                }
                Divider()
                HStack {
                    Text("Token Status:")
                        .foregroundColor(Theme.slateGray)
                    Spacer()
                    Text(tokenValid ? "Authorized" : "Cached")
                }
                Divider()
                HStack {
                    Text("Disk Status:")
                        .foregroundColor(Theme.slateGray)
                    Spacer()
                    Text("Space OK")
                }
            }
            .padding(20)
            .background(Color.white.opacity(0.02))
            .cornerRadius(Theme.CornerRadius.card)
        }
    }
    
    private var shouldDisableNextButton: Bool {
        if installStatus == .installing { return true }
        if currentStep == 3 { return installStatus != .succeeded }
        if currentStep == 4 { return hfToken.isEmpty }
        return false
    }
    
    private func stepTitle(for step: Int) -> String {
        switch step {
        case 1: return "Welcome"
        case 2: return "Disk Space"
        case 3: return "Environment Setup"
        case 4: return "HuggingFace Token"
        case 5: return "Ready"
        default: return ""
        }
    }
    
    private func stepSubtitle(for step: Int) -> String {
        switch step {
        case 1: return "Meet Trellis Studio"
        case 2: return "Check requirements"
        case 3: return "Install backend scripts"
        case 4: return "Connect to the hub"
        case 5: return "All set to create"
        default: return ""
        }
    }
}
