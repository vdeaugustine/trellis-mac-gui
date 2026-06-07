import Foundation
import SwiftData

/// A service that handles deleting and exporting saved generation records.
///
/// Use `HistoryService` to safely remove persistent records and their associated files
/// from the disk, or to export generated 3D models to external locations.
final class HistoryService {
    static let shared = HistoryService()
    
    private init() {}
    
    /// Deletes a generation record from the database and removes its on-disk files.
    ///
    /// - Parameters:
    ///   - record: The record to delete.
    ///   - modelContext: The SwiftData context used to execute the deletion.
    func deleteRecord(_ record: GenerationRecord, modelContext: ModelContext) {
        let fileManager = FileManager.default
        let folderURL = URL(fileURLWithPath: record.inputImagePath).deletingLastPathComponent()
        try? fileManager.removeItem(at: folderURL)
        
        modelContext.delete(record)
        try? modelContext.save()
    }
    
    /// Exports the generated GLB model to a specified destination.
    ///
    /// - Parameters:
    ///   - record: The generation record containing the GLB file path.
    ///   - destinationURL: The file URL where the GLB should be copied.
    /// - Throws: An error if the GLB file does not exist or cannot be copied.
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
