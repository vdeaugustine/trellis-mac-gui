import Foundation
import SwiftData

/// Live progress details for the active daemon stage.
///
/// Use `GenerationStageProgress` to calculate and display progress bars and descriptive text
/// while a generation task is running.
struct GenerationStageProgress {
    /// The current execution state of the pipeline.
    let stage: GenerationStatus
    
    /// The number of completed steps in the current stage.
    let current: Int
    
    /// The total number of steps in the current stage.
    let total: Int
    
    /// A localized description of the current stage's progress.
    let message: String

    /// The normalized progress fraction, from `0.0` to `1.0`.
    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(current) / Double(total)))
    }
}

/// A background service that manages the queue and execution of 3D generation tasks.
///
/// Use `GenerationService` to submit new generation records, monitor active generation
/// progress, and safely serialize requests to the backend daemon. The service guarantees
/// that only one generation task runs at a time.
@MainActor
final class GenerationService: ObservableObject {
    static let shared = GenerationService()

    /// The generation record currently being processed by the backend.
    @Published var activeRecord: GenerationRecord?
    
    /// The most recently completed generation record.
    @Published var lastCompletedRecord: GenerationRecord?
    
    /// The queue of pending generation records waiting to be processed.
    @Published var queue: [GenerationRecord] = []
    
    /// The live progress of the active generation task.
    @Published var stageProgress: GenerationStageProgress?

    private var isProcessing = false
    private let log = AppLogger.shared

    private init() {}

    /// Adds a generation record to the processing queue.
    ///
    /// - Parameters:
    ///   - record: The generation record to enqueue.
    ///   - modelContext: The SwiftData context used to persist the record.
    func addToQueue(record: GenerationRecord, modelContext: ModelContext) {
        log.info("Adding generation to queue: \(record.id)", context: "Generation")
        queue.append(record)
        modelContext.insert(record)

        do {
            try modelContext.save()
            log.info("Record saved to SwiftData", context: "Generation")
        } catch {
            log.error("Failed to save record: \(error.localizedDescription)", context: "Generation")
        }

        processNext()
    }

    /// Advances the queue and starts processing the next generation record if the service is idle.
    func processNext() {
        guard !isProcessing, !queue.isEmpty else {
            if isProcessing {
                log.info("Already processing — \(queue.count) item(s) queued", context: "Generation")
            }
            return
        }
        isProcessing = true

        let nextRecord = queue.removeFirst()
        activeRecord = nextRecord
        stageProgress = nil
        log.info("Processing: \(nextRecord.id)", context: "Generation")

        Task {
            await runGeneration(record: nextRecord)
        }
    }

    /// Cancels the currently active generation and cleans up its output files.
    func cancelActive() {
        guard let record = activeRecord else {
            log.warning("No active generation to cancel", context: "Generation")
            return
        }

        log.info("Cancelling generation: \(record.id)", context: "Generation")

        // Tell daemon to abort (it will ignore if already done)
        DaemonManager.shared.sendRequest(command: ["command": "cancel"])

        // Mark as cancelled
        record.status = .cancelled

        // Clean up output directory
        let fileManager = FileManager.default
        let appSupportDir = fileManager.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let generationDir = appSupportDir.appendingPathComponent(
            "com.vinware.trellis-studio/Generations/\(record.id.uuidString)"
        )
        if fileManager.fileExists(atPath: generationDir.path) {
            try? fileManager.removeItem(at: generationDir)
            log.info("Cleaned up output directory: \(generationDir.path)", context: "Generation")
        }

        finishActive()
    }

    private func runGeneration(record: GenerationRecord) async {
        // Log full job parameters for diagnostics
        let dateFormatter = ISO8601DateFormatter()
        log.info("""
        ┌─ Generation Job ─────────────────────────
        │ ID:        \(record.id)
        │ Image:     \(URL(fileURLWithPath: record.inputImagePath).lastPathComponent)
        │ Seed:      \(record.seed)
        │ Pipeline:  \(record.pipelineType)
        │ Texture:   \(record.noTexture ? "Geometry only" : "\(record.textureSize)px")
        │ Started:   \(dateFormatter.string(from: Date()))
        └───────────────────────────────────────────
        """, context: "Generation")

        let fileManager = FileManager.default
        let appSupportDir = fileManager.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let generationDir = appSupportDir.appendingPathComponent(
            "com.vinware.trellis-studio/Generations/\(record.id.uuidString)"
        )

        do {
            // Create output directory
            try fileManager.createDirectory(at: generationDir, withIntermediateDirectories: true)
            log.info("Output directory: \(generationDir.path)", context: "Generation")

            // Validate and copy input image
            let originalInputURL = URL(fileURLWithPath: record.inputImagePath)
            guard fileManager.fileExists(atPath: originalInputURL.path) else {
                throw GenerationError.inputNotFound(record.inputImagePath)
            }

            let ext = originalInputURL.pathExtension.isEmpty ? "png" : originalInputURL.pathExtension
            let copiedInputURL = generationDir.appendingPathComponent("input.\(ext)")

            if fileManager.fileExists(atPath: copiedInputURL.path) {
                try? fileManager.removeItem(at: copiedInputURL)
            }
            try fileManager.copyItem(at: originalInputURL, to: copiedInputURL)
            log.info("Input copied to: \(copiedInputURL.path)", context: "Generation")

            record.inputImagePath = copiedInputURL.path

            // Verify daemon is ready
            guard DaemonManager.shared.isReady else {
                throw GenerationError.daemonNotReady
            }

            // Wire up progress callbacks
            DaemonManager.shared.clearCallbacks()
            DaemonManager.shared.clearCrashCallbacks()
            DaemonManager.shared.registerCallback { response in
                Task { @MainActor in
                    self.handleDaemonResponse(response, for: record)
                }
            }
            DaemonManager.shared.registerCrashCallback { message in
                Task { @MainActor in
                    self.handleDaemonCrash(message, for: record)
                }
            }

            // Send generate request
            let req: [String: Any] = [
                "command": "generate",
                "image": copiedInputURL.path,
                "seed": record.seed,
                "pipeline_type": record.pipelineType,
                "texture_size": record.textureSize,
                "no_texture": record.noTexture,
                "output_dir": generationDir.path
            ]
            log.info("Sending generate request to daemon", context: "Generation")
            DaemonManager.shared.sendRequest(command: req)

        } catch {
            let errorMsg: String
            if let genError = error as? GenerationError {
                errorMsg = genError.userMessage
            } else {
                errorMsg = error.localizedDescription
            }

            record.status = .failed
            record.errorMessage = errorMsg
            log.error("Generation failed: \(errorMsg)", context: "Generation")
            finishActive()
        }
    }

    private func handleDaemonResponse(_ response: [String: Any], for record: GenerationRecord) {
        guard let stageRaw = response["stage"] as? String else {
            log.warning("Response missing 'stage' key: \(response)", context: "Generation")
            return
        }

        guard let stage = GenerationStatus(rawValue: stageRaw) else {
            log.warning("Unknown stage: \(stageRaw)", context: "Generation")
            return
        }

        record.status = stage
        updateStageProgress(response, stage: stage)
        log.info("Stage update: \(stage.displayName)", context: "Generation")

        if stage == .complete {
            record.outputGLBPath = response["glb_path"] as? String
            record.outputOBJPath = response["obj_path"] as? String
            record.vertexCount = response["vertices"] as? Int
            record.triangleCount = response["triangles"] as? Int
            record.generationTimeSeconds = response["total_s"] as? Double
            record.thumbnailPath = record.inputImagePath

            log.success(
                "Generation complete: \(record.vertexCount ?? 0) verts, \(record.triangleCount ?? 0) tris, \(String(format: "%.1f", record.generationTimeSeconds ?? 0))s",
                context: "Generation"
            )
            finishActive()

        } else if stage == .failed {
            let reason = response["reason"] as? String ?? "unknown"
            let message = response["message"] as? String ?? "No details provided"
            record.errorMessage = "[\(reason)] \(message)"

            if reason == "watchdog" {
                record.status = .failedWatchdog
                log.error("GPU watchdog killed generation. Try headless mode.", context: "Generation")
            } else {
                log.error("Daemon reported failure: \(reason) — \(message)", context: "Generation")
            }
            finishActive()

        } else if stage == .extractingMesh {
            if let verts = response["vertices"] as? Int,
               let tris = response["triangles"] as? Int {
                record.vertexCount = verts
                record.triangleCount = tris
            }
        }
    }

    private func updateStageProgress(_ response: [String: Any], stage: GenerationStatus) {
        guard let current = response["current"] as? Int,
              let total = response["total"] as? Int else {
            if response["status"] as? String == "started" {
                let message = response["message"] as? String ?? stage.displayName
                stageProgress = GenerationStageProgress(stage: stage, current: 0, total: 0, message: message)
            }
            return
        }
        let message = response["message"] as? String ?? stage.displayName
        stageProgress = GenerationStageProgress(stage: stage, current: current, total: total, message: message)
    }

    private func handleDaemonCrash(_ message: String, for record: GenerationRecord) {
        guard activeRecord?.id == record.id else { return }
        record.status = .failed
        record.errorMessage = message
        log.error("Daemon crashed during generation: \(message)", context: "Generation")
        finishActive()
    }

    private func finishActive() {
        if let record = activeRecord {
            if record.status == .complete {
                lastCompletedRecord = record
            }

            if let modelContext = record.modelContext {
                do {
                    try modelContext.save()
                } catch {
                    log.error("Failed to save final state: \(error.localizedDescription)", context: "Generation")
                }
            }
        }

        DaemonManager.shared.clearCallbacks()
        DaemonManager.shared.clearCrashCallbacks()
        stageProgress = nil
        activeRecord = nil
        isProcessing = false

        processNext()
    }
}

// MARK: - Error Types

/// Errors that can occur when preparing or starting a generation task.
enum GenerationError: Error {
    /// The source image file could not be found at the specified path.
    case inputNotFound(String)
    
    /// The Python backend is not fully loaded and ready to accept requests.
    case daemonNotReady
    
    /// The service could not create a dedicated output directory for the generation results.
    case outputDirectoryFailed(String)

    /// A localized, human-readable description of the error.
    var userMessage: String {
        switch self {
        case .inputNotFound(let path):
            return "Input image not found: \(path). It may have been moved or deleted."
        case .daemonNotReady:
            return "Backend daemon is not ready. Wait for pipeline to load or check Settings."
        case .outputDirectoryFailed(let path):
            return "Could not create output directory: \(path)"
        }
    }
}
