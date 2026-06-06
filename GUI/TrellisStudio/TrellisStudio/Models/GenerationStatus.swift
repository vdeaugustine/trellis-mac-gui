import Foundation

enum GenerationStatus: String, Codable, CaseIterable {
    case queued = "queued"
    case warmingUp = "warmingUp"
    case loadingPipeline = "loadingPipeline"
    case samplingStructure = "samplingStructure"
    case samplingShape = "samplingShape"
    case samplingTexture = "samplingTexture"
    case decodingShape = "decodingShape"
    case decodingTexture = "decodingTexture"
    case extractingMesh = "extractingMesh"
    case bakingTexture = "bakingTexture"
    case complete = "complete"
    case failed = "failed"
    case failedWatchdog = "failedWatchdog"
    case shutdown = "shutdown"
    
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
        }
    }
}
