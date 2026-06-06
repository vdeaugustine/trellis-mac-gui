import Foundation
import SwiftData

@Model
final class GenerationRecord {
    @Attribute(.unique) var id: UUID
    var inputImagePath: String
    var outputGLBPath: String?
    var outputOBJPath: String?
    var thumbnailPath: String?
    var seed: Int
    var pipelineType: String
    var textureSize: Int
    var vertexCount: Int?
    var triangleCount: Int?
    var generationTimeSeconds: Double?
    var createdAt: Date
    var status: GenerationStatus
    var errorMessage: String?
    
    init(
        id: UUID = UUID(),
        inputImagePath: String,
        seed: Int,
        pipelineType: String,
        textureSize: Int,
        status: GenerationStatus = .queued,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.inputImagePath = inputImagePath
        self.seed = seed
        self.pipelineType = pipelineType
        self.textureSize = textureSize
        self.status = status
        self.createdAt = createdAt
    }
}
