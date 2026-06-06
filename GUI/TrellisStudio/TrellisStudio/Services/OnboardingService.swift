import Foundation

final class OnboardingService: ObservableObject {
    static let shared = OnboardingService()
    
    @Published var isCompleted: Bool {
        didSet { UserDefaults.standard.set(isCompleted, forKey: "onboardingCompleted") }
    }
    
    private init() {
        self.isCompleted = UserDefaults.standard.bool(forKey: "onboardingCompleted")
    }
    
    func checkDiskSpace() -> Double {
        let fileURL = URL(fileURLWithPath: "/")
        do {
            let values = try fileURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let capacity = values.volumeAvailableCapacityForImportantUsage {
                return Double(capacity) / (1024 * 1024 * 1024)
            }
        } catch {
            return 0.0
        }
        return 0.0
    }
    
    func checkEnvironmentInstalled() -> Bool {
        let fileManager = FileManager.default
        let backendPath = backendDirectoryURL.path
        let pythonPath = backendDirectoryURL.appendingPathComponent(".venv/bin/python").path
        let generatePath = backendDirectoryURL.appendingPathComponent("generate.py").path
        return fileManager.fileExists(atPath: pythonPath) && fileManager.fileExists(atPath: generatePath)
    }
    
    var backendDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("com.vinware.trellis-studio/backend")
    }
    
    func installEnvironment() -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                let fileManager = FileManager.default
                let backendURL = backendDirectoryURL
                
                // 1. Create Application Support dir if needed
                do {
                    try fileManager.createDirectory(at: backendURL, withIntermediateDirectories: true)
                } catch {
                    continuation.yield("Error creating backend directory: \(error)")
                    continuation.finish()
                    return
                }
                
                // 2. Copy bundled scripts
                continuation.yield("Copying scripts...")
                if let bundleResourceURL = Bundle.main.resourceURL?.appendingPathComponent("BackendBundle") {
                    do {
                        let items = try fileManager.contentsOfDirectory(atPath: bundleResourceURL.path)
                        for item in items {
                            let src = bundleResourceURL.appendingPathComponent(item)
                            let dst = backendURL.appendingPathComponent(item)
                            if fileManager.fileExists(atPath: dst.path) {
                                try fileManager.removeItem(at: dst)
                            }
                            try fileManager.copyItem(at: src, to: dst)
                        }
                    } catch {
                        continuation.yield("Error copying scripts: \(error)")
                        continuation.finish()
                        return
                    }
                } else {
                    continuation.yield("Warning: BackendBundle not found in App Resources. Running in-place if dev mode.")
                }
                
                // 3. Execute setup.sh
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = ["setup.sh"]
                process.currentDirectoryURL = backendURL
                
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                
                let fileHandle = pipe.fileHandleForReading
                fileHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.count > 0, let str = String(data: data, encoding: .utf8) {
                        // Yield each line
                        let lines = str.split(separator: "\n").map(String.init)
                        for line in lines {
                            continuation.yield(line)
                        }
                    }
                }
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    fileHandle.readabilityHandler = nil
                    
                    if process.terminationStatus == 0 {
                        continuation.yield("Setup completed successfully.")
                    } else {
                        continuation.yield("Setup failed with code \(process.terminationStatus).")
                    }
                } catch {
                    continuation.yield("Error running setup: \(error)")
                }
                
                continuation.finish()
            }
        }
    }
    
    func validateHFToken(_ token: String) async -> Bool {
        guard !token.isEmpty else { return false }
        var request = URLRequest(url: URL(string: "https://huggingface.co/api/whoami-v2")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
        } catch {
            return false
        }
        return false
    }
}
