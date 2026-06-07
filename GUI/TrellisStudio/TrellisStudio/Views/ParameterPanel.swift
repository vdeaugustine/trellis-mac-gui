import SwiftUI

/// A control panel for configuring 3D generation parameters.
///
/// Use `ParameterPanel` to allow users to customize the pipeline settings, such as the
/// random seed, model type, and texture resolution. It also provides quick presets and
/// the main button to initiate generation.
struct ParameterPanel: View {
    @Bindable var parameters: GenerationParameters
    @Binding var inputImageURL: URL?
    var onGenerate: () -> Void

    @EnvironmentObject var daemon: DaemonManager
    @EnvironmentObject var generation: GenerationService

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Generation Parameters")
                .font(.headline)

            // Seed
            VStack(alignment: .leading, spacing: 8) {
                Text("Seed")
                    .font(.subheadline)
                    .foregroundColor(Theme.slateGray)
                HStack {
                    TextField("Random Seed", value: $parameters.seed, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier(AccessibilityID.seedTextField)
                    Button(action: { parameters.randomizeSeed() }) {
                        Image(systemName: "dice.fill")
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(6)
                    .accessibilityIdentifier(AccessibilityID.randomizeSeedButton)
                }
            }

            // Pipeline Type
            VStack(alignment: .leading, spacing: 8) {
                Text("Pipeline Type")
                    .font(.subheadline)
                    .foregroundColor(Theme.slateGray)
                Picker("", selection: $parameters.pipelineType) {
                    Text("512").tag("512")
                    Text("1024").tag("1024")
                    Text("1024 Cascade").tag("1024_cascade")
                }
                .pickerStyle(.segmented)
            }

            // Texture Size
            VStack(alignment: .leading, spacing: 8) {
                Text("Texture Size")
                    .font(.subheadline)
                    .foregroundColor(Theme.slateGray)
                Picker("", selection: $parameters.textureSize) {
                    Text("512").tag(512)
                    Text("1024").tag(1024)
                    Text("2048").tag(2048)
                }
                .pickerStyle(.segmented)
                .disabled(parameters.noTexture)
            }

            // No Texture
            Toggle("No Texture", isOn: $parameters.noTexture)
                .toggleStyle(.switch)

            Spacer()

            // Presets
            HStack(spacing: 8) {
                presetButton("Fast Draft", pipeline: "512", texture: 512)
                presetButton("Balanced", pipeline: "1024", texture: 1024)
                presetButton("Max Quality", pipeline: "1024_cascade", texture: 2048)
            }
            .font(.caption)

            // Generate Button
            Button(action: onGenerate) {
                HStack(spacing: 8) {
                    if generation.activeRecord != nil {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                            .tint(.white)
                    } else {
                        Image(systemName: "cube.fill")
                    }
                    Text(generateButtonLabel)
                        .bold()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(generateButtonBackground)
                .foregroundColor(.white)
                .cornerRadius(Theme.CornerRadius.button)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("g", modifiers: .command)
            .disabled(isGenerateDisabled)
            .accessibilityIdentifier(AccessibilityID.generateButton)

            // Status hint
            if isGenerateDisabled {
                statusHint
                    .font(.caption)
                    .foregroundColor(Theme.warningAmber)
            }
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .cornerRadius(Theme.CornerRadius.panel)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.panel)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func presetButton(_ title: String, pipeline: String, texture: Int) -> some View {
        Button(title) {
            parameters.pipelineType = pipeline
            parameters.textureSize = texture
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.1))
        .cornerRadius(6)
    }

    private var isGenerateDisabled: Bool {
        inputImageURL == nil || !daemon.isReady || generation.activeRecord != nil
    }

    private var generateButtonLabel: String {
        if generation.activeRecord != nil { return "Generating…" }
        if inputImageURL == nil { return "Select an Image" }
        if !daemon.isReady { return "Waiting for Backend…" }
        return "Generate Model"
    }

    private var generateButtonBackground: some ShapeStyle {
        if isGenerateDisabled {
            return AnyShapeStyle(Color.gray.opacity(0.3))
        }
        return AnyShapeStyle(Theme.accentGradient)
    }

    @ViewBuilder
    private var statusHint: some View {
        if inputImageURL == nil {
            Label("Drop or browse an image first", systemImage: "photo")
        } else if daemon.isOffline {
            Label("Backend is offline — check Settings", systemImage: "exclamationmark.triangle")
        } else if daemon.isWarmingUp {
            Label("Pipeline loading — please wait", systemImage: "hourglass")
        } else if generation.activeRecord != nil {
            Label("Generation in progress", systemImage: "clock")
        }
    }
}
