import Foundation
import SwiftData

@MainActor
final class GenerationService: ObservableObject {
    static let shared = GenerationService()
    
    @Published var activeRecord: GenerationRecord?
    @Published var queue: [GenerationRecord] = []
    
    private var isProcessing = false
    
    private init() {}
    
    func addToQueue(record: GenerationRecord, modelContext: ModelContext) {
        queue.append(record)
        modelContext.insert(record)
        try? modelContext.save()
        
        processNext()
    }
    
    func processNext() {
        guard !isProcessing, !queue.isEmpty else { return }
        isProcessing = true
        
        let nextRecord = queue.removeFirst()
        activeRecord = nextRecord
        
        Task {
            await runGeneration(record: nextRecord)
        }
    }
    
    private func runGeneration(record: GenerationRecord) async {
        let fileManager = FileManager.default
        let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let trellisDir = appSupportDir.appendingPathComponent("com.vinware.trellis-studio/Generations/\(record.id.uuidString)")
        
        do {
            try fileManager.createDirectory(at: trellisDir, withIntermediateDirectories: true)
            
            let originalInputURL = URL(fileURLWithPath: record.inputImagePath)
            let ext = originalInputURL.pathExtension.isEmpty ? "png" : originalInputURL.pathExtension
            let copiedInputURL = trellisDir.appendingPathComponent("input.\(ext)")
            
            if fileManager.fileExists(atPath: copiedInputURL.path) {
                try? fileManager.removeItem(at: copiedInputURL)
            }
            try fileManager.copyItem(at: originalInputURL, to: copiedInputURL)
            
            record.inputImagePath = copiedInputURL.path
            
            DaemonManager.shared.clearCallbacks()
            DaemonManager.shared.registerCallback { response in
                Task { @MainActor in
                    self.handleDaemonResponse(response, for: record)
                }
            }
            
            let req: [String: Any] = [
                "command": "generate",
                "image": copiedInputURL.path,
                "seed": record.seed,
                "pipeline_type": record.pipelineType,
                "texture_size": record.textureSize,
                "output_dir": trellisDir.path
            ]
            DaemonManager.shared.sendRequest(command: req)
            
        } catch {
            record.status = .failed
            record.errorMessage = error.localizedDescription
            finishActive()
        }
    }
    
    private func handleDaemonResponse(_ response: [String: Any], for record: GenerationRecord) {
        guard let stageRaw = response["stage"] as? String,
              let stage = GenerationStatus(rawValue: stageRaw) else {
            return
        }
        
        record.status = stage
        
        if stage == .complete {
            record.outputGLBPath = response["glb_path"] as? String
            record.outputOBJPath = response["obj_path"] as? String
            record.vertexCount = response["vertices"] as? Int
            record.triangleCount = response["triangles"] as? Int
            record.generationTimeSeconds = response["total_s"] as? Double
            record.thumbnailPath = record.inputImagePath
            
            finishActive()
        } else if stage == .failed {
            let reason = response["reason"] as? String ?? ""
            record.errorMessage = response["message"] as? String ?? "Unknown error"
            if reason == "watchdog" {
                record.status = .failedWatchdog
            }
            finishActive()
        }
    }
    
    private func finishActive() {
        if let modelContext = activeRecord?.modelContext {
            try? modelContext.save()
        }
        
        DaemonManager.shared.clearCallbacks()
        activeRecord = nil
        isProcessing = false
        
        processNext()
    }
}
