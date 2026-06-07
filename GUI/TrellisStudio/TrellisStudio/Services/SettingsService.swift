import Foundation

/// A centralized service for managing persistent user preferences.
///
/// Use `SettingsService` to read and write application configuration values.
/// Changes to these settings are automatically saved to `UserDefaults`.
final class SettingsService: ObservableObject {
    static let shared = SettingsService()
    
    /// The user's Hugging Face authentication token, used for downloading gated models.
    @Published var hfToken: String {
        didSet { UserDefaults.standard.set(hfToken, forKey: "hfToken") }
    }
    
    /// The default machine learning pipeline type to use for new generation tasks.
    @Published var defaultPipelineType: String {
        didSet { UserDefaults.standard.set(defaultPipelineType, forKey: "defaultPipelineType") }
    }
    
    /// The default texture resolution to use for new generation tasks.
    @Published var defaultTextureSize: Int {
        didSet { UserDefaults.standard.set(defaultTextureSize, forKey: "defaultTextureSize") }
    }
    
    /// The default random seed used to initialize new generation parameters.
    @Published var defaultSeed: Int {
        didSet { UserDefaults.standard.set(defaultSeed, forKey: "defaultSeed") }
    }
    
    /// Custom environment variables applied when launching the Python backend.
    @Published var advancedEnvVars: String {
        didSet { UserDefaults.standard.set(advancedEnvVars, forKey: "advancedEnvVars") }
    }

    private init() {
        self.hfToken = UserDefaults.standard.string(forKey: "hfToken") ?? ""
        self.defaultPipelineType = UserDefaults.standard.string(forKey: "defaultPipelineType") ?? "512"
        self.defaultTextureSize = UserDefaults.standard.integer(forKey: "defaultTextureSize") == 0 ? 1024 : UserDefaults.standard.integer(forKey: "defaultTextureSize")
        self.defaultSeed = UserDefaults.standard.integer(forKey: "defaultSeed") == 0 ? 42 : UserDefaults.standard.integer(forKey: "defaultSeed")
        let savedEnvVars = UserDefaults.standard.string(forKey: "advancedEnvVars")
        self.advancedEnvVars = savedEnvVars == "SPARSE_CONV_BACKEND=flex_gemm"
            ? "SPARSE_CONV_BACKEND=none"
            : (savedEnvVars ?? "SPARSE_CONV_BACKEND=none")
        if savedEnvVars == "SPARSE_CONV_BACKEND=flex_gemm" {
            UserDefaults.standard.set(self.advancedEnvVars, forKey: "advancedEnvVars")
        }
    }
}
