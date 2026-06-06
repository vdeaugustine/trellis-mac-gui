import SwiftUI

struct OnboardingView: View {
    @ObservedObject var onboarding = OnboardingService.shared
    @ObservedObject var settings = SettingsService.shared
    
    @State private var currentStep = 1
    @State private var hfToken = ""
    @State private var tokenValid = false
    @State private var validatingToken = false
    
    @State private var installLogs: [String] = []
    @State private var isInstalling = false
    @State private var installComplete = false
    
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
                        .disabled(isInstalling)
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
            installComplete = onboarding.checkEnvironmentInstalled()
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
            Text("Trellis Studio will automatically install the backend environment and its dependencies.")
                .font(.body)
                .foregroundColor(Theme.slateGray)
            
            if !installComplete && !isInstalling {
                Button("Install Environment") {
                    startInstallation()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Theme.accentGradient)
                .foregroundColor(.white)
                .cornerRadius(Theme.CornerRadius.button)
            }
            
            if isInstalling || installComplete {
                VStack(alignment: .leading) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(installLogs.enumerated()), id: \.offset) { index, log in
                                    Text(log)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(Theme.slateGray)
                                        .id(index)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 200)
                        .onChange(of: installLogs.count) { _, newValue in
                            withAnimation {
                                proxy.scrollTo(newValue - 1, anchor: .bottom)
                            }
                        }
                    }
                }
                .padding(16)
                .background(Color.black.opacity(0.2))
                .cornerRadius(Theme.CornerRadius.card)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.card)
                        .stroke(Theme.border, lineWidth: 1)
                )
            }
            
            if installComplete {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Theme.successGreen)
                    Text("Installation Complete")
                        .foregroundColor(Theme.successGreen)
                        .bold()
                }
            }
        }
    }
    
    private func startInstallation() {
        isInstalling = true
        installLogs.append("Starting installation...")
        
        Task {
            let stream = onboarding.installEnvironment()
            for await line in stream {
                await MainActor.run {
                    installLogs.append(line)
                }
            }
            
            await MainActor.run {
                isInstalling = false
                installComplete = onboarding.checkEnvironmentInstalled()
                if !installComplete {
                    installLogs.append("Installation failed. Please review the logs above.")
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
        if isInstalling { return true }
        if currentStep == 3 { return !installComplete }
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
