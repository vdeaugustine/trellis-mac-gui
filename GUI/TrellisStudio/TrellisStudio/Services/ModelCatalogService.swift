import Foundation

/// Status of a single model checkpoint in the HuggingFace cache.
enum ModelDownloadStatus: Equatable {
    case downloaded
    case missing
    case downloading(progress: Double)
    case error(String)
}

/// Represents one model checkpoint that the pipeline requires.
struct ModelCatalogEntry: Identifiable {
    let id: String
    let displayName: String
    /// HuggingFace repo that owns this file.
    let repoId: String
    /// Relative file path inside the repo (e.g. "ckpts/shape_dec_...").
    let relativePath: String
    /// Whether this model is gated.
    let isGated: Bool
    /// Role in the pipeline (e.g. "Shape Decoder", "Image Conditioning").
    let role: String

    var status: ModelDownloadStatus = .missing
    /// Size on disk in bytes (0 if not downloaded).
    var sizeBytes: Int64 = 0
}

/// Scans the HuggingFace cache to determine which TRELLIS models are downloaded.
final class ModelCatalogService: ObservableObject {
    static let shared = ModelCatalogService()

    @Published var entries: [ModelCatalogEntry] = []
    @Published var isScanning = false
    @Published var totalSizeBytes: Int64 = 0

    private let hfCacheRoot: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".cache/huggingface/hub")
    }()

    private init() {
        buildCatalog()
    }

    // MARK: - Catalog Definition

    /// Builds the static catalog of all required models.
    private func buildCatalog() {
        entries = [
            // Checkpoint models from microsoft/TRELLIS.2-4B
            makeEntry(
                id: "ss_dec", name: "Sparse Structure Decoder",
                repo: "microsoft/TRELLIS-image-large",
                path: "ckpts/ss_dec_conv3d_16l8_fp16",
                role: "Structure"
            ),
            makeEntry(
                id: "ss_flow", name: "Sparse Structure Flow",
                repo: "microsoft/TRELLIS.2-4B",
                path: "ckpts/ss_flow_img_dit_1_3B_64_bf16",
                role: "Structure"
            ),
            makeEntry(
                id: "shape_dec", name: "Shape Decoder",
                repo: "microsoft/TRELLIS.2-4B",
                path: "ckpts/shape_dec_next_dc_f16c32_fp16",
                role: "Shape"
            ),
            makeEntry(
                id: "shape_flow_512", name: "Shape Flow (512)",
                repo: "microsoft/TRELLIS.2-4B",
                path: "ckpts/slat_flow_img2shape_dit_1_3B_512_bf16",
                role: "Shape"
            ),
            makeEntry(
                id: "shape_flow_1024", name: "Shape Flow (1024)",
                repo: "microsoft/TRELLIS.2-4B",
                path: "ckpts/slat_flow_img2shape_dit_1_3B_1024_bf16",
                role: "Shape"
            ),
            makeEntry(
                id: "tex_dec", name: "Texture Decoder",
                repo: "microsoft/TRELLIS.2-4B",
                path: "ckpts/tex_dec_next_dc_f16c32_fp16",
                role: "Texture"
            ),
            makeEntry(
                id: "tex_flow_512", name: "Texture Flow (512)",
                repo: "microsoft/TRELLIS.2-4B",
                path: "ckpts/slat_flow_imgshape2tex_dit_1_3B_512_bf16",
                role: "Texture"
            ),
            makeEntry(
                id: "tex_flow_1024", name: "Texture Flow (1024)",
                repo: "microsoft/TRELLIS.2-4B",
                path: "ckpts/slat_flow_imgshape2tex_dit_1_3B_1024_bf16",
                role: "Texture"
            ),
            // Auxiliary models (gated)
            ModelCatalogEntry(
                id: "dinov3", displayName: "DINOv3 Vision Encoder",
                repoId: "facebook/dinov3-vitl16-pretrain-lvd1689m",
                relativePath: "config.json",
                isGated: true, role: "Image Understanding"
            ),
            ModelCatalogEntry(
                id: "rmbg", displayName: "RMBG-2.0 Background Remover",
                repoId: "briaai/RMBG-2.0",
                relativePath: "config.json",
                isGated: true, role: "Preprocessing"
            ),
        ]
    }

    private func makeEntry(id: String, name: String, repo: String, path: String, role: String) -> ModelCatalogEntry {
        ModelCatalogEntry(
            id: id, displayName: name,
            repoId: repo, relativePath: path,
            isGated: false, role: role
        )
    }

    // MARK: - Scanning

    /// Scans the HF cache and updates each entry's status and size.
    func scan() {
        guard !isScanning else { return }
        isScanning = true

        Task.detached { [weak self] in
            guard let self else { return }
            var updated = self.entries
            var total: Int64 = 0

            for i in updated.indices {
                let entry = updated[i]
                let (status, size) = self.checkModel(entry)
                updated[i].status = status
                updated[i].sizeBytes = size
                total += size
            }

            let finalEntries = updated
            let finalTotal = total

            await MainActor.run {
                self.entries = finalEntries
                self.totalSizeBytes = finalTotal
                self.isScanning = false
            }
        }
    }

    /// Checks a single model's presence in the HF cache.
    private func checkModel(_ entry: ModelCatalogEntry) -> (ModelDownloadStatus, Int64) {
        let repoDirName = "models--\(entry.repoId.replacingOccurrences(of: "/", with: "--"))"
        let repoDir = hfCacheRoot.appendingPathComponent(repoDirName)

        guard FileManager.default.fileExists(atPath: repoDir.path) else {
            return (.missing, 0)
        }

        // Find the snapshot directory
        let snapshotsDir = repoDir.appendingPathComponent("snapshots")
        guard let snapshots = try? FileManager.default.contentsOfDirectory(atPath: snapshotsDir.path),
              let snapshot = snapshots.first else {
            return (.missing, 0)
        }

        let snapshotDir = snapshotsDir.appendingPathComponent(snapshot)

        // For checkpoint models, check .safetensors file
        if !entry.isGated {
            let safetensorsPath = snapshotDir
                .appendingPathComponent("\(entry.relativePath).safetensors")
            return checkFileExists(safetensorsPath, blobsDir: repoDir.appendingPathComponent("blobs"))
        }

        // For gated models, just check if the repo snapshot has any content
        let size = directorySize(snapshotDir)
        if size > 0 {
            return (.downloaded, size)
        }
        return (.missing, 0)
    }

    /// Resolves symlinks in the HF cache and returns status + real size.
    private func checkFileExists(_ path: URL, blobsDir: URL) -> (ModelDownloadStatus, Int64) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path.path) else {
            return (.missing, 0)
        }

        // HF cache uses symlinks pointing to ../../../blobs/<hash>
        if let attrs = try? fm.attributesOfItem(atPath: path.path),
           attrs[.type] as? FileAttributeType == .typeSymbolicLink {
            if let target = try? fm.destinationOfSymbolicLink(atPath: path.path) {
                let resolved = path.deletingLastPathComponent().appendingPathComponent(target)
                if let size = try? fm.attributesOfItem(atPath: resolved.path)[.size] as? Int64 {
                    return (.downloaded, size)
                }
            }
        }

        // Regular file
        if let size = try? fm.attributesOfItem(atPath: path.path)[.size] as? Int64 {
            return (.downloaded, size)
        }
        return (.downloaded, 0)
    }

    /// Recursively sums file sizes, following symlinks.
    private func directorySize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let file as URL in enumerator {
            // Resolve symlinks
            let resolved = file.resolvingSymlinksInPath()
            if let size = try? resolved.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    // MARK: - Actions

    /// Deletes a single model's cache directory.
    func deleteModel(_ entry: ModelCatalogEntry) throws {
        let repoDirName = "models--\(entry.repoId.replacingOccurrences(of: "/", with: "--"))"
        let repoDir = hfCacheRoot.appendingPathComponent(repoDirName)
        if FileManager.default.fileExists(atPath: repoDir.path) {
            try FileManager.default.removeItem(at: repoDir)
        }
        // Re-scan after delete
        scan()
    }

    // MARK: - Computed

    var downloadedCount: Int {
        entries.filter { $0.status == .downloaded }.count
    }

    var missingCount: Int {
        entries.filter { $0.status == .missing }.count
    }

    var allDownloaded: Bool {
        entries.allSatisfy { $0.status == .downloaded }
    }

    /// Formatted total size string.
    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSizeBytes, countStyle: .file)
    }
}
