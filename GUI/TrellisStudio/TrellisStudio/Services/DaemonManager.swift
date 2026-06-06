import Foundation

final class DaemonManager: ObservableObject {
    static let shared = DaemonManager()
    
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    
    @Published var isReady = false
    @Published var isWarmingUp = false
    @Published var isOffline = true
    
    var isDryRun = false
    
    private var progressCallbacks: [([String: Any]) -> Void] = []
    
    private init() {}
    
    func startDaemon(trellisPath: String, dryRun: Bool = false) {
        self.isDryRun = dryRun
        self.isOffline = false
        self.isWarmingUp = true
        
        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        
        let pythonPath = URL(fileURLWithPath: trellisPath).appendingPathComponent(".venv/bin/python").path
        let scriptPath = URL(fileURLWithPath: trellisPath).appendingPathComponent("trellis_daemon.py").path
        
        process.executableURL = URL(fileURLWithPath: pythonPath)
        var arguments = [scriptPath]
        if dryRun {
            arguments.append("--dry-run")
        }
        process.arguments = arguments
        
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        env["PYTORCH_ENABLE_MPS_FALLBACK"] = "1"
        if !SettingsService.shared.hfToken.isEmpty {
            env["HF_TOKEN"] = SettingsService.shared.hfToken
        }
        process.environment = env
        
        self.process = process
        self.stdinPipe = stdinPipe
        self.stdoutPipe = stdoutPipe
        
        do {
            try process.run()
            
            Task {
                await listenToStdout(pipe: stdoutPipe)
            }
        } catch {
            DispatchQueue.main.async {
                self.isOffline = true
                self.isWarmingUp = false
                self.isReady = false
            }
        }
    }
    
    func stopDaemon() {
        sendRequest(command: ["command": "shutdown"])
        process?.terminate()
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        DispatchQueue.main.async {
            self.isOffline = true
            self.isReady = false
            self.isWarmingUp = false
        }
    }
    
    func sendRequest(command: [String: Any]) {
        guard let stdinPipe = stdinPipe else { return }
        let payload = ["command": command]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
           let jsonString = String(data: data, encoding: .utf8) {
            let line = jsonString + "\n"
            if let lineData = line.data(using: .utf8) {
                stdinPipe.fileHandleForWriting.write(lineData)
            }
        }
    }
    
    func registerCallback(_ callback: @escaping ([String: Any]) -> Void) {
        progressCallbacks.append(callback)
    }
    
    func clearCallbacks() {
        progressCallbacks.removeAll()
    }
    
    private func listenToStdout(pipe: Pipe) async {
        let fileHandle = pipe.fileHandleForReading
        var buffer = Data()
        
        while true {
            do {
                guard let data = try fileHandle.read(upToCount: 1024), !data.isEmpty else {
                    break
                }
                buffer.append(data)
                
                while let range = buffer.range(of: Data([10])) {
                    let lineData = buffer.subdata(in: 0..<range.lowerBound)
                    buffer.removeSubrange(0...range.lowerBound)
                    
                    if let line = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty {
                        await parseDaemonLine(line)
                    }
                }
            } catch {
                break
            }
        }
        
        DispatchQueue.main.async {
            self.isOffline = true
            self.isWarmingUp = false
            self.isReady = false
        }
    }
    
    private func parseDaemonLine(_ line: String) async {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let response = json["response"] as? [String: Any] else {
            return
        }
        
        DispatchQueue.main.async {
            for cb in self.progressCallbacks {
                cb(response)
            }
            
            if let stageRaw = response["stage"] as? String,
               let stage = GenerationStatus(rawValue: stageRaw) {
                if stage == .loadingPipeline {
                    if response["status"] as? String == "done" {
                        self.isWarmingUp = false
                        self.isReady = true
                    }
                } else if stage == .shutdown {
                    self.isReady = false
                    self.isOffline = true
                }
            }
        }
    }
}
