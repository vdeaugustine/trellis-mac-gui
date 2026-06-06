import SwiftUI
import RealityKit

struct ModelViewerPanel: View {
    @State private var showWireframe = false
    @State private var environmentLight = "Studio"
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("3D Viewer")
                    .font(.headline)
                
                Spacer()
                
                // Controls
                HStack(spacing: 16) {
                    Picker("Lighting", selection: $environmentLight) {
                        Text("Studio").tag("Studio")
                        Text("Outdoor").tag("Outdoor")
                        Text("Neutral").tag("Neutral")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                    
                    Toggle("Wireframe", isOn: $showWireframe)
                        .toggleStyle(.switch)
                    
                    Button(action: {
                        // Export
                    }) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .background(Color.white.opacity(0.02))
            
            Divider()
            
            // 3D View Content
            ZStack {
                // Placeholder for RealityView
                Rectangle()
                    .fill(Color.black.opacity(0.2))
                
                VStack {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 64))
                        .foregroundColor(Theme.slateGray)
                    Text("No Model Generated")
                        .font(.headline)
                        .foregroundColor(Theme.slateGray)
                        .padding(.top, 8)
                }
                
                // Stats Overlay
                VStack {
                    Spacer()
                    HStack {
                        HStack(spacing: 16) {
                            StatItem(label: "Vertices", value: "--")
                            StatItem(label: "Triangles", value: "--")
                            StatItem(label: "Time", value: "--")
                        }
                        .padding(12)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                        
                        Spacer()
                    }
                    .padding()
                }
            }
        }
        .background(Color.black.opacity(0.1))
        .cornerRadius(Theme.CornerRadius.panel)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.panel)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .padding(24)
    }
}

struct StatItem: View {
    var label: String
    var value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(Theme.slateGray)
            Text(value)
                .font(.system(.subheadline, design: .monospaced))
                .bold()
        }
    }
}
