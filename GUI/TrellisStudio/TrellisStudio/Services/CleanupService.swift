import Foundation

/// Knows every location Trellis Studio writes to on disk and can remove them.
///
/// Locations tracked:
/// 1. Application Support backend  — venv, cloned repos, scripts, generated outputs
/// 2. HuggingFace model cache      — downloaded weights (~15 GB)
/// 3. UserDefaults preferences     — app settings plist
/// 4. SwiftData store              — generation history database
final class CleanupService {
    static let shared = CleanupService()
    private init() {}
    
    // MARK: - Path Catalogue
    
    /// `~/Library/Application Support/com.vinware.trellis-studio/`
    var appSupportURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("com.vinware.trellis-studio")
    }
    
    /// `~/Library/Application Support/com.vinware.trellis-studio/backend/`
    var backendURL: URL { appSupportURL.appendingPathComponent("backend") }
    
    /// `~/Library/Application Support/com.vinware.trellis-studio/Generations/`
    var generationsURL: URL { appSupportURL.appendingPathComponent("Generations") }
    
    /// HuggingFace default cache: `~/.cache/huggingface/hub/`
    var huggingFaceCacheURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".cache/huggingface/hub")
    }
    
    /// UserDefaults plist: `~/Library/Preferences/com.vinware.trellis-studio.plist`
    var preferencesPlistURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Preferences/com.vinware.trellis-studio.plist")
    }
    
    /// SwiftData default store location
    var swiftDataStoreURL: URL {
        appSupportURL.appendingPathComponent("default.store")
    }
    
    // MARK: - Size Helpers
    
    /// Returns the size of a directory in bytes, or 0 if it doesn't exist.
    func sizeOfDirectory(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return 0 }
        
        let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])
        var total: Int64 = 0
        while let fileURL = enumerator?.nextObject() as? URL {
            if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let size = values.fileSize {
                total += Int64(size)
            }
        }
        return total
    }
    
    /// Returns a human-readable size string (e.g. "14.3 GB").
    func formattedSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    // MARK: - Individual Cleanup Actions
    
    /// Remove the backend environment (venv, cloned repos, scripts).
    func removeBackend() throws {
        try removeIfExists(backendURL)
    }
    
    /// Remove all generated model outputs.
    func removeGenerations() throws {
        try removeIfExists(generationsURL)
    }
    
    /// Remove cached HuggingFace model weights.
    ///
    /// Only removes Trellis-related model folders to avoid
    /// nuking weights used by other apps on the system.
    func removeTrellisModelCache() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: huggingFaceCacheURL.path) else { return }
        
        let trellisPatterns = [
            "models--microsoft--TRELLIS",
            "models--facebook--dinov3",
            "models--briaai--RMBG"
        ]
        
        let contents = try fm.contentsOfDirectory(atPath: huggingFaceCacheURL.path)
        for item in contents {
            if trellisPatterns.contains(where: { item.hasPrefix($0) }) {
                let itemURL = huggingFaceCacheURL.appendingPathComponent(item)
                try fm.removeItem(at: itemURL)
            }
        }
    }
    
    /// Clear all UserDefaults keys used by the app.
    func removePreferences() {
        let defaults = UserDefaults.standard
        let keys = [
            "onboardingCompleted",
            "hfToken",
            "defaultPipelineType",
            "defaultTextureSize",
            "defaultSeed",
            "advancedEnvVars"
        ]
        for key in keys {
            defaults.removeObject(forKey: key)
        }
        defaults.synchronize()
    }
    
    /// Remove the SwiftData store files.
    func removeSwiftDataStore() throws {
        let fm = FileManager.default
        let storeDir = appSupportURL
        guard fm.fileExists(atPath: storeDir.path) else { return }
        
        let contents = try fm.contentsOfDirectory(atPath: storeDir.path)
        for item in contents where item.hasPrefix("default.store") {
            let itemURL = storeDir.appendingPathComponent(item)
            try fm.removeItem(at: itemURL)
        }
    }
    
    /// Nuclear option: remove everything the app ever wrote.
    func removeEverything() throws {
        try removeBackend()
        try removeGenerations()
        try removeTrellisModelCache()
        try removeSwiftDataStore()
        removePreferences()
        
        // Remove the top-level Application Support folder if now empty
        try removeIfExists(appSupportURL)
    }
    
    // MARK: - Private
    
    private func removeIfExists(_ url: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }
}
