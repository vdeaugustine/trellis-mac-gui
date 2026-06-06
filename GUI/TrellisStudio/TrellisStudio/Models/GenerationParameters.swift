import Foundation
import Observation

@Observable
final class GenerationParameters {
    var seed: Int = 42
    var pipelineType: String = "512"
    var textureSize: Int = 1024
    var noTexture: Bool = false
    var steps: Int? = nil
    
    func randomizeSeed() {
        seed = Int.random(in: 1...999999)
    }
}
