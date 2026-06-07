import SwiftUI
import UniformTypeIdentifiers

struct InputPanel: View {
    @Binding var inputImageURL: URL?
    @State private var isHovering = false

    var body: some View {
        VStack {
            if let imageURL = inputImageURL, let nsImage = NSImage(contentsOf: imageURL) {
                imagePreview(imageURL: imageURL, nsImage: nsImage)
            } else {
                dropZone
            }
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .cornerRadius(Theme.CornerRadius.panel)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.panel)
                .strokeBorder(
                    isHovering ? Theme.accentIndigo : Color.white.opacity(0.1),
                    style: StrokeStyle(lineWidth: isHovering ? 2 : 1, dash: inputImageURL == nil ? [6] : [])
                )
        )
    }

    // MARK: - Image Preview

    private func imagePreview(imageURL: URL, nsImage: NSImage) -> some View {
        VStack(spacing: 12) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .cornerRadius(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier(AccessibilityID.imagePreview)

            HStack {
                Text(imageURL.lastPathComponent)
                    .font(.caption)
                    .foregroundColor(Theme.slateGray)
                    .lineLimit(1)
                    .accessibilityIdentifier(AccessibilityID.imageFilename)

                Spacer()

                Button(action: { inputImageURL = nil }) {
                    Image(systemName: "trash")
                        .foregroundColor(Theme.errorRed)
                }
                .buttonStyle(.plain)
                .padding(4)
                .background(Color.white.opacity(0.1))
                .cornerRadius(4)
                .accessibilityIdentifier(AccessibilityID.removeImageButton)
            }
        }
    }

    // MARK: - Drop Zone

    private var dropZone: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundColor(isHovering ? Theme.accentIndigo : Theme.slateGray)

            VStack(spacing: 8) {
                Text("Drag & Drop Image Here")
                    .font(.headline)
                Text("PNG, JPG, HEIC, WEBP")
                    .font(.caption)
                    .foregroundColor(Theme.slateGray)
            }

            Button("Browse...") {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.image]
                panel.canChooseFiles = true
                panel.canChooseDirectories = false
                panel.allowsMultipleSelection = false

                if panel.runModal() == .OK {
                    inputImageURL = panel.url
                    AppLogger.shared.info("Image selected: \(panel.url?.lastPathComponent ?? "unknown")", context: "Input")
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.1))
            .cornerRadius(Theme.CornerRadius.button)
            .accessibilityIdentifier(AccessibilityID.browseButton)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isHovering ? Theme.accentIndigo.opacity(0.1) : Color.clear)
        .onDrop(of: [.image], isTargeted: $isHovering) { providers in
            guard let provider = providers.first(where: {
                $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
            }) else { return false }

            provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { item, error in
                if let error = error {
                    AppLogger.shared.error("Drop failed: \(error.localizedDescription)", context: "Input")
                    return
                }
                if let url = item as? URL {
                    DispatchQueue.main.async {
                        self.inputImageURL = url
                        AppLogger.shared.info("Image dropped: \(url.lastPathComponent)", context: "Input")
                    }
                }
            }
            return true
        }
    }
}
