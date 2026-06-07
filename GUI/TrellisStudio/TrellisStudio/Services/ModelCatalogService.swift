import Foundation

/// The download status of a model checkpoint in the local cache.
enum ModelDownloadStatus: Equatable {
    case downloaded
    case missing
    case downloading(progress: Double)
    case error(String)
}

/// The progress details of a model download operation.
///
/// Use `ModelCatalogDownloadProgress` to display the current state of a long-running
/// model download to the user in the settings interface.
struct ModelCatalogDownloadProgress {
    var currentModelID: String = ""
    var currentModelName: String = "Preparing download"
    var currentRepoID: String = ""
    var completed: Int = 0
    var total: Int = 0
    var message: String = ""
}

/// A representation of a required machine learning model checkpoint.
///
/// Use `ModelCatalogEntry` to track whether a specific component of the generation
/// pipeline has been downloaded and is available for execution.
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

/// A service that monitors and manages downloaded machine learning models.
///
/// Use `ModelCatalogService` to verify the presence of required Hugging Face models,
/// download missing weights, and delete cached checkpoints. The service scans the
/// local cache to ensure all dependencies are met before generation can occur.
final class ModelCatalogService: ObservableObject {
    static let shared = ModelCatalogService()

    @Published var entries: [ModelCatalogEntry] = []
    @Published var isScanning = false
    @Published var isDownloading = false
    @Published var downloadProgress = ModelCatalogDownloadProgress()
    @Published var downloadMessage: String?
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

    /// Scans the local Hugging Face cache to determine the availability and size of all required models.
    ///
    /// This method runs asynchronously in the background and updates the service's published
    /// properties when the scan completes.
    func scan() {
        guard !isScanning, !isDownloading else { return }
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

    /// Deletes a specific model from the local cache.
    ///
    /// - Parameter entry: The catalog entry representing the model to delete.
    /// - Throws: An error if the cache directory cannot be removed.
    func deleteModel(_ entry: ModelCatalogEntry) throws {
        let repoDirName = "models--\(entry.repoId.replacingOccurrences(of: "/", with: "--"))"
        let repoDir = hfCacheRoot.appendingPathComponent(repoDirName)
        if FileManager.default.fileExists(atPath: repoDir.path) {
            try FileManager.default.removeItem(at: repoDir)
        }
        // Re-scan after delete
        scan()
    }

    /// Initiates a background process to download all missing model weights.
    ///
    /// This method invokes the `download_weights.py` script via the Python backend
    /// and streams the progress back to the user interface.
    @MainActor
    func downloadAllWeights() {
        guard !isDownloading else { return }

        isDownloading = true
        downloadMessage = nil
        downloadProgress = ModelCatalogDownloadProgress(total: entries.count)
        markMissingEntriesAsDownloading()

        Task.detached { [weak self] in
            await self?.runDownloadScript()
        }
    }

    private func runDownloadScript() async {
        let backendURL = OnboardingService.shared.backendDirectoryURL
        let pythonPath = backendURL.appendingPathComponent(".venv/bin/python").path
        let scriptPath = backendURL.appendingPathComponent("download_weights.py").path

        guard FileManager.default.fileExists(atPath: pythonPath) else {
            await finishDownload(message: "Python venv not found", failed: true)
            return
        }
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            await finishDownload(message: "Download script not found", failed: true)
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [scriptPath]
        process.currentDirectoryURL = backendURL

        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        let token = HFAuthService.shared.resolveToken()
        if !token.isEmpty { env["HF_TOKEN"] = token }
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let output = String(data: data, encoding: .utf8) else { return }
            for line in output.components(separatedBy: "\n") where !line.isEmpty {
                Task { @MainActor in self?.handleDownloadLine(line) }
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let output = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in self?.downloadMessage = output.trimmingCharacters(in: .whitespacesAndNewlines) }
        }

        do {
            try process.run()
            process.waitUntilExit()
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil

            if process.terminationStatus == 0 {
                await finishDownload(message: "Model download complete", failed: false)
            } else {
                await finishDownload(message: "Download exited with code \(process.terminationStatus)", failed: true)
            }
        } catch {
            await finishDownload(message: error.localizedDescription, failed: true)
        }
    }

    @MainActor
    private func handleDownloadLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            downloadMessage = line
            return
        }

        let stage = json["stage"] as? String ?? ""
        let status = json["status"] as? String ?? ""
        let model = json["model"] as? String ?? ""
        let repo = json["repo"] as? String ?? ""
        let message = json["message"] as? String ?? ""

        if let total = json["total"] as? Int { downloadProgress.total = total }
        if let completed = json["current"] as? Int { downloadProgress.completed = completed }
        if !model.isEmpty { downloadProgress.currentModelID = model }
        if !repo.isEmpty { downloadProgress.currentRepoID = repo }
        if !message.isEmpty {
            downloadProgress.message = message
            downloadMessage = message
        }

        if status == "downloading" {
            setEntryStatus(modelID: model, repoID: repo, status: .downloading(progress: currentDownloadFraction))
        } else if status == "done", stage == "download" {
            setEntryStatus(modelID: model, repoID: repo, status: .downloaded)
        } else if status == "error" || status == "gated" {
            setEntryStatus(modelID: model, repoID: repo, status: .error(message))
        }
    }

    @MainActor
    private func finishDownload(message: String, failed: Bool) {
        downloadMessage = message
        isDownloading = false
        if failed {
            entries = entries.map { entry in
                var updated = entry
                if case .downloading = updated.status {
                    updated.status = .missing
                }
                return updated
            }
        }
        scan()
    }

    @MainActor
    private func markMissingEntriesAsDownloading() {
        entries = entries.map { entry in
            var updated = entry
            if updated.status == .missing {
                updated.status = .downloading(progress: 0)
            }
            return updated
        }
    }

    @MainActor
    private func setEntryStatus(modelID: String, repoID: String, status: ModelDownloadStatus) {
        guard let index = entries.firstIndex(where: { entry in
            entry.id == modelID || (!repoID.isEmpty && entry.repoId == repoID && entry.isGated)
        }) else { return }
        entries[index].status = status
    }

    private var currentDownloadFraction: Double {
        guard downloadProgress.total > 0 else { return 0 }
        return Double(downloadProgress.completed) / Double(downloadProgress.total)
    }

    // MARK: - Computed

    var downloadedCount: Int {
        entries.filter { $0.status == .downloaded }.count
    }

    var missingCount: Int {
        entries.filter { entry in
            if entry.status == .missing { return true }
            if case .error = entry.status { return true }
            return false
        }.count
    }

    var allDownloaded: Bool {
        entries.allSatisfy { $0.status == .downloaded }
    }

    /// Formatted total size string.
    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSizeBytes, countStyle: .file)
    }
}
