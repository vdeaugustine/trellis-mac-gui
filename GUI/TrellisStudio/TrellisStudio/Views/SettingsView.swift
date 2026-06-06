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
                
                ForEach(["General", "Account", "Defaults", "Appearance", "Advanced"], id: \.self) { tab in
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
                            Text("Apple M3 Pro")
                                .font(.caption).bold()
                            Text("18 GB Unified Memory")
                                .font(.caption2)
                                .foregroundColor(Theme.slateGray)
                            Text("macOS 14.4.1")
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
                        } else if activeTab == "Defaults" {
                            defaultsTab
                        } else if activeTab == "Appearance" {
                            appearanceTab
                        } else if activeTab == "Advanced" {
                            advancedTab
                        }
                    }
                    .padding(30)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .frame(width: 700, height: 500)
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
        }
    }
    
    private var accountTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Account Settings")
                .font(.title2).bold()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("HuggingFace Access Token")
                    .font(.headline)
                SecureField("hf_...", text: $settings.hfToken)
                    .textFieldStyle(.roundedBorder)
                
                Text("Securely stored in your user settings. Required for downloading weights.")
                    .font(.caption)
                    .foregroundColor(Theme.slateGray)
            }
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
    
    private func iconName(for tab: String) -> String {
        switch tab {
        case "General": return "gearshape"
        case "Account": return "person"
        case "Defaults": return "slider.horizontal.3"
        case "Appearance": return "paintbrush"
        case "Advanced": return "cpu"
        default: return "gearshape"
        }
    }
}
