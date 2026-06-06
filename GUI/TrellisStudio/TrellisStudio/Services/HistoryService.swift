import Foundation
import SwiftData

final class HistoryService {
    static let shared = HistoryService()
    
    private init() {}
    
    func deleteRecord(_ record: GenerationRecord, modelContext: ModelContext) {
        let fileManager = FileManager.default
        let folderURL = URL(fileURLWithPath: record.inputImagePath).deletingLastPathComponent()
        try? fileManager.removeItem(at: folderURL)
        
        modelContext.delete(record)
        try? modelContext.save()
    }
    
    func exportGLB(_ record: GenerationRecord, to destinationURL: URL) throws {
        guard let glbPath = record.outputGLBPath else {
            throw NSError(
                domain: "HistoryService",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "No GLB file found for this record"]
            )
        }
        let glbURL = URL(fileURLWithPath: glbPath)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: glbURL, to: destinationURL)
    }
}
