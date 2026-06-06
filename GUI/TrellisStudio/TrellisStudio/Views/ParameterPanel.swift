import SwiftUI

struct ParameterPanel: View {
    @State private var parameters = GenerationParameters()
    
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
                    Button(action: {
                        parameters.randomizeSeed()
                    }) {
                        Image(systemName: "dice.fill")
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(6)
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
                    Text("1024 Cascade").tag("1024 Cascade")
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
                Button("Fast Draft") {
                    parameters.pipelineType = "512"
                    parameters.textureSize = 512
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.1))
                .cornerRadius(6)
                
                Button("Balanced") {
                    parameters.pipelineType = "1024"
                    parameters.textureSize = 1024
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.1))
                .cornerRadius(6)
                
                Button("Max Quality") {
                    parameters.pipelineType = "1024 Cascade"
                    parameters.textureSize = 2048
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.1))
                .cornerRadius(6)
            }
            .font(.caption)
            
            // Generate Button
            Button(action: {
                // Trigger generation
            }) {
                Text("Generate Model")
                    .bold()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.accentGradient)
                    .foregroundColor(.white)
                    .cornerRadius(Theme.CornerRadius.button)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("g", modifiers: .command)
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .cornerRadius(Theme.CornerRadius.panel)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.panel)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}
