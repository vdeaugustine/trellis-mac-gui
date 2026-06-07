import Foundation

final class SettingsService: ObservableObject {
    static let shared = SettingsService()
    
    @Published var hfToken: String {
        didSet { UserDefaults.standard.set(hfToken, forKey: "hfToken") }
    }
    
    @Published var defaultPipelineType: String {
        didSet { UserDefaults.standard.set(defaultPipelineType, forKey: "defaultPipelineType") }
    }
    
    @Published var defaultTextureSize: Int {
        didSet { UserDefaults.standard.set(defaultTextureSize, forKey: "defaultTextureSize") }
    }
    
    @Published var defaultSeed: Int {
        didSet { UserDefaults.standard.set(defaultSeed, forKey: "defaultSeed") }
    }
    
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
