import SwiftUI
import SceneKit
import UniformTypeIdentifiers

/// Displays a 3D model from a completed generation, or a placeholder when none exists.
struct ModelViewerPanel: View {
    var record: GenerationRecord?

    @State private var showWireframe = false
    @State private var environmentLight = "Studio"
    @State private var sceneLoaded = false
    @State private var loadError: String?
    @State private var scene: SCNScene?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            viewerContent
        }
        .background(Color.black.opacity(0.1))
        .cornerRadius(Theme.CornerRadius.panel)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.panel)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .padding(24)
        .onChange(of: record?.id) { _, _ in
            loadModel()
        }
        .onAppear {
            loadModel()
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            Text("3D Viewer")
                .font(.headline)

            Spacer()

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

                Button(action: exportModel) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
                .disabled(record?.outputGLBPath == nil)
            }
        }
        .padding()
        .background(Color.white.opacity(0.02))
    }

    // MARK: - Viewer Content

    @ViewBuilder
    private var viewerContent: some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.2))

            if let scene = scene {
                SceneKitModelView(
                    scene: scene,
                    showWireframe: showWireframe,
                    environmentLight: environmentLight
                )
            } else if let error = loadError {
                errorPlaceholder(error)
            } else if record != nil && !sceneLoaded {
                ProgressView("Loading model…")
                    .foregroundColor(Theme.slateGray)
            } else {
                emptyPlaceholder
            }

            statsOverlay
        }
    }

    private var emptyPlaceholder: some View {
        VStack {
            Image(systemName: "cube.transparent")
                .font(.system(size: 64))
                .foregroundColor(Theme.slateGray)
            Text("No Model Generated")
                .font(.headline)
                .foregroundColor(Theme.slateGray)
                .padding(.top, 8)
        }
    }

    private func errorPlaceholder(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(Theme.errorRed)
            Text("Failed to load model")
                .font(.headline)
                .foregroundColor(Theme.errorRed)
            Text(message)
                .font(.caption)
                .foregroundColor(Theme.slateGray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private var statsOverlay: some View {
        VStack {
            Spacer()
            HStack {
                HStack(spacing: 16) {
                    StatItem(
                        label: "Vertices",
                        value: record?.vertexCount.map { formatCount($0) } ?? "--"
                    )
                    StatItem(
                        label: "Triangles",
                        value: record?.triangleCount.map { formatCount($0) } ?? "--"
                    )
                    StatItem(
                        label: "Time",
                        value: record?.generationTimeSeconds.map { formatTime($0) } ?? "--"
                    )
                }
                .padding(12)
                .background(.ultraThinMaterial)
                .cornerRadius(8)

                Spacer()
            }
            .padding()
        }
    }

    // MARK: - Model Loading

    private func loadModel() {
        scene = nil
        loadError = nil
        sceneLoaded = false

        // Prefer OBJ (SceneKit handles it natively), fall back to GLB
        let modelPath = record?.outputOBJPath ?? record?.outputGLBPath
        guard let path = modelPath else { return }

        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            loadError = "Model file not found at: \(path)"
            sceneLoaded = true
            return
        }

        Task.detached {
            do {
                let loadedScene = try SCNScene(url: url, options: [
                    .checkConsistency: true
                ])
                await MainActor.run {
                    self.scene = loadedScene
                    self.sceneLoaded = true
                }
            } catch {
                await MainActor.run {
                    self.loadError = error.localizedDescription
                    self.sceneLoaded = true
                }
            }
        }
    }

    private func exportModel() {
        guard let glbPath = record?.outputGLBPath else { return }
        let sourceURL = URL(fileURLWithPath: glbPath)

        let panel = NSSavePanel()
        let glbType = UTType(filenameExtension: "glb") ?? .data
        panel.allowedContentTypes = [glbType]
        panel.nameFieldStringValue = sourceURL.lastPathComponent
        panel.begin { result in
            guard result == .OK, let dest = panel.url else { return }
            try? FileManager.default.copyItem(at: sourceURL, to: dest)
        }
    }

    // MARK: - Formatting

    private func formatCount(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func formatTime(_ seconds: Double) -> String {
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(mins)m \(secs)s"
    }
}

// MARK: - SceneKit View

/// Wraps an SCNView for displaying a 3D scene with orbit controls.
struct SceneKitModelView: NSViewRepresentable {
    var scene: SCNScene
    var showWireframe: Bool
    var environmentLight: String

    func makeNSView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.scene = scene
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = true
        scnView.backgroundColor = .clear
        scnView.antialiasingMode = .multisampling4X
        applyLighting(to: scene, style: environmentLight)
        return scnView
    }

    func updateNSView(_ scnView: SCNView, context: Context) {
        if scnView.scene !== scene {
            scnView.scene = scene
            applyLighting(to: scene, style: environmentLight)
        }

        // Toggle wireframe
        let renderingAPI: SCNDebugOptions = showWireframe ? .showWireframe : []
        scnView.debugOptions = renderingAPI
    }

    private func applyLighting(to scene: SCNScene, style: String) {
        // Remove existing lights tagged as "env_light"
        scene.rootNode.childNodes
            .filter { $0.name == "env_light" }
            .forEach { $0.removeFromParentNode() }

        let lightNode = SCNNode()
        lightNode.name = "env_light"
        let light = SCNLight()

        switch style {
        case "Outdoor":
            light.type = .directional
            light.intensity = 1200
            light.color = NSColor.white
            lightNode.eulerAngles = SCNVector3(-Float.pi / 4, Float.pi / 4, 0)
        case "Neutral":
            light.type = .ambient
            light.intensity = 800
            light.color = NSColor(white: 0.9, alpha: 1)
        default: // Studio
            light.type = .omni
            light.intensity = 1000
            light.color = NSColor.white
            lightNode.position = SCNVector3(2, 5, 5)
        }

        lightNode.light = light
        scene.rootNode.addChildNode(lightNode)
    }
}

// MARK: - Stat Item

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
