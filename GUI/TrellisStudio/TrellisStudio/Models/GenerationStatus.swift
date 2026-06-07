import Foundation

/// The execution state of a 3D model generation process.
///
/// Use `GenerationStatus` to determine the current progress of a generation task.
/// The status advances sequentially from queued to complete, with failure states
/// handling unexpected errors or watchdog timeouts.
enum GenerationStatus: String, Codable, CaseIterable {
    /// The generation request is queued and waiting to start.
    case queued = "queued"
    
    /// The daemon is preparing the execution environment.
    case warmingUp = "warmingUp"
    
    /// The machine learning pipeline is loading into memory.
    case loadingPipeline = "loadingPipeline"
    
    /// The pipeline is generating the structural representation of the model.
    case samplingStructure = "samplingStructure"
    
    /// The pipeline is generating the geometric shape.
    case samplingShape = "samplingShape"
    
    /// The pipeline is generating the texture maps.
    case samplingTexture = "samplingTexture"
    
    /// The structural shape is being decoded into a 3D format.
    case decodingShape = "decodingShape"
    
    /// The texture maps are being decoded.
    case decodingTexture = "decodingTexture"
    
    /// The 3D mesh is being extracted from the decoded shape.
    case extractingMesh = "extractingMesh"
    
    /// Textures are being baked onto the extracted mesh.
    case bakingTexture = "bakingTexture"
    
    /// The generation process has successfully completed.
    case complete = "complete"
    
    /// The generation process failed due to an error.
    case failed = "failed"
    
    /// The generation process was terminated by the watchdog timer.
    case failedWatchdog = "failedWatchdog"
    
    /// The daemon was shut down during the generation process.
    case shutdown = "shutdown"

    /// The generation was cancelled by the user.
    case cancelled = "cancelled"
    
    /// A localized, human-readable name for the status.
    ///
    /// Use this property when displaying the generation progress in the user interface.
    var displayName: String {
        switch self {
        case .queued: return "Queued"
        case .warmingUp: return "Warming Up"
        case .loadingPipeline: return "Loading Pipeline"
        case .samplingStructure: return "Sampling Structure"
        case .samplingShape: return "Sampling Shape"
        case .samplingTexture: return "Sampling Texture"
        case .decodingShape: return "Decoding Shape"
        case .decodingTexture: return "Decoding Texture"
        case .extractingMesh: return "Extracting Mesh"
        case .bakingTexture: return "Baking Texture"
        case .complete: return "Complete"
        case .failed: return "Failed"
        case .failedWatchdog: return "Failed (Watchdog)"
        case .shutdown: return "Shutdown"
        case .cancelled: return "Cancelled"
        }
    }
}
