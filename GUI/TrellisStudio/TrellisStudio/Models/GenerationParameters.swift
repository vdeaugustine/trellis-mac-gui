import Foundation
import Observation

/// The configuration parameters used to start a 3D model generation process.
///
/// Use `GenerationParameters` to store user-selected settings like the random seed,
/// pipeline type, and texture resolution before passing them to the generation service.
@Observable
final class GenerationParameters {
    /// The random seed used for generation.
    var seed: Int = 42
    
    /// The pipeline identifier to run, such as `"512"`.
    var pipelineType: String = "512"
    
    /// The target resolution for the generated textures.
    var textureSize: Int = 1024
    
    /// A Boolean value that determines whether the generation should skip texture creation.
    var noTexture: Bool = false
    
    /// An optional custom number of sampling steps to use during generation.
    var steps: Int? = nil
    
    /// Randomizes the generation seed.
    ///
    /// Call this method to generate a new random seed between 1 and 999,999.
    func randomizeSeed() {
        seed = Int.random(in: 1...999999)
    }
}
