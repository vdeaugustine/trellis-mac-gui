import Foundation
import SwiftData

/// A persistent record of a 3D model generation process.
///
/// Use `GenerationRecord` to track the state, inputs, and outputs of a Trellis 3D generation.
/// This model persists the configuration used to start the generation, such as the input image and seed,
/// the current execution state, and the resulting 3D asset paths once the generation completes.
@Model
final class GenerationRecord {
    /// The stable, unique identifier for the generation.
    @Attribute(.unique) var id: UUID
    
    /// The file path to the input image used for generation.
    var inputImagePath: String
    
    /// The file path to the generated GLB 3D model.
    ///
    /// This value is `nil` until the generation successfully completes and outputs a GLB file.
    var outputGLBPath: String?
    
    /// The file path to the generated OBJ 3D model.
    ///
    /// This value is `nil` until the generation successfully completes and outputs an OBJ file.
    var outputOBJPath: String?
    
    /// The file path to a preview thumbnail of the generated model.
    ///
    /// This value is `nil` until a thumbnail has been rendered from the generated 3D model.
    var thumbnailPath: String?
    
    /// The random seed used for the generation process.
    ///
    /// Providing the same seed with the same input image and parameters yields identical results.
    var seed: Int
    
    /// The identifier for the pipeline type used to generate the model.
    var pipelineType: String
    
    /// The resolution of the generated texture maps.
    var textureSize: Int
    
    /// The number of vertices in the generated 3D model.
    ///
    /// This value is `nil` until the generation completes and the model geometry can be analyzed.
    var vertexCount: Int?
    
    /// The number of triangles in the generated 3D model.
    ///
    /// This value is `nil` until the generation completes and the model geometry can be analyzed.
    var triangleCount: Int?
    
    /// The total duration of the generation process, measured in seconds.
    ///
    /// This value is `nil` until the generation completes.
    var generationTimeSeconds: Double?
    
    /// The date and time when the generation record was created.
    var createdAt: Date
    
    /// The current execution status of the generation process.
    var status: GenerationStatus
    
    /// A description of the error that caused the generation to fail.
    ///
    /// This value is `nil` unless the generation fails.
    var errorMessage: String?
    
    /// Creates a new generation record with the specified parameters.
    ///
    /// - Parameters:
    ///   - id: The unique identifier for the record. Defaults to a new UUID.
    ///   - inputImagePath: The file path to the source image.
    ///   - seed: The random seed to use for generation.
    ///   - pipelineType: The type of generation pipeline to run.
    ///   - textureSize: The desired texture resolution.
    ///   - status: The initial state of the generation. Defaults to `.queued`.
    ///   - createdAt: The creation date of the record. Defaults to the current time.
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
