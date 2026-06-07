import Foundation

/// A service that tracks and manages all file system locations used by Trellis Studio.
///
/// Use `CleanupService` to calculate disk usage and safely remove cached data.
/// It tracks the Python virtual environment, Hugging Face model weights,
/// user preferences, and SwiftData generation history.
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
    
    /// Calculates the total size of a directory.
    ///
    /// - Parameter url: The file URL of the directory to measure.
    /// - Returns: The total size in bytes, or `0` if the directory does not exist.
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
    
    /// Formats a byte count into a human-readable storage string.
    ///
    /// - Parameter bytes: The number of bytes to format.
    /// - Returns: A localized string (e.g., `"14.3 GB"`).
    func formattedSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    // MARK: - Individual Cleanup Actions
    
    /// Removes the Python backend environment, including the virtual environment and cloned repositories.
    ///
    /// - Throws: An error if the files cannot be removed.
    func removeBackend() throws {
        try removeIfExists(backendURL)
    }
    
    /// Removes all generated 3D models and their associated thumbnails.
    ///
    /// - Throws: An error if the files cannot be removed.
    func removeGenerations() throws {
        try removeIfExists(generationsURL)
    }
    
    /// Removes cached Hugging Face model weights that were downloaded by the application.
    ///
    /// This method only removes models specific to the Trellis pipeline to avoid deleting
    /// weights that might be used by other applications on the system.
    ///
    /// - Throws: An error if the cache directories cannot be removed.
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
    
    /// Removes the application's entire footprint from the disk.
    ///
    /// This operation deletes the backend environment, all generated content, downloaded
    /// model weights, the internal database, and all user preferences.
    ///
    /// > Warning: This operation permanently deletes all local application data and cannot be undone.
    ///
    /// - Throws: An error if any of the targeted directories or files cannot be removed.
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
