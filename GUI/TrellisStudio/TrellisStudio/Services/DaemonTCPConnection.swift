import Foundation

/// Manages a TCP connection to the daemon process.
///
/// Use `DaemonTCPConnection` to establish a persistent connection with the Python backend.
/// It provides methods for connecting, sending JSON payloads, and parsing incoming JSON
/// responses asynchronously.
final class DaemonTCPConnection {
    private var inputStream: InputStream?
    private var outputStream: OutputStream?
    private var readThread: Thread?
    private var readBuffer = Data()
    private let connectQueue = DispatchQueue(
        label: "com.vinware.trellis-studio.daemon-tcp-connect",
        qos: .userInitiated
    )

    private let log = AppLogger.shared
    
    /// A closure that is called whenever a complete JSON response is received.
    var onResponse: (([String: Any]) -> Void)?
    
    /// A closure that is called when the TCP connection disconnects or fails.
    var onDisconnect: (() -> Void)?

    /// A Boolean value that indicates whether the TCP connection is currently open.
    var isConnected: Bool {
        guard let input = inputStream, let output = outputStream else {
            return false
        }
        return input.streamStatus == .open && output.streamStatus == .open
    }

    // MARK: - Connect

    /// Establishes a TCP connection to the specified localhost port.
    ///
    /// - Parameter port: The port number to connect to.
    /// - Parameter completion: A closure that receives whether the streams opened successfully.
    func connect(port: Int, completion: @escaping (Bool) -> Void) {
        connectQueue.async { [weak self] in
            guard let self else { return }
            let connected = self.openConnection(port: port)
            DispatchQueue.main.async {
                completion(connected)
            }
        }
    }

    private func openConnection(port: Int) -> Bool {
        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?

        CFStreamCreatePairWithSocketToHost(
            nil,
            "127.0.0.1" as CFString,
            UInt32(port),
            &readStream,
            &writeStream
        )

        guard let input = readStream?.takeRetainedValue() as InputStream?,
              let output = writeStream?.takeRetainedValue() as OutputStream? else {
            log.error("Failed to create TCP streams for port \(port)", context: "Daemon")
            return false
        }

        input.open()
        output.open()

        guard input.streamStatus == .open, output.streamStatus == .open else {
            let status = "input=\(input.streamStatus.rawValue) output=\(output.streamStatus.rawValue)"
            log.error("TCP connection failed — stream status: \(status)", context: "Daemon")
            input.close()
            output.close()
            return false
        }

        self.inputStream = input
        self.outputStream = output
        startReading()

        log.info("TCP connected to daemon on port \(port)", context: "Daemon")
        return true
    }

    // MARK: - Send

    /// Encodes a dictionary as JSON and writes it to the TCP output stream.
    ///
    /// - Parameter command: The dictionary to encode and send.
    func send(command: [String: Any]) {
        guard let output = outputStream, output.streamStatus == .open else {
            log.error("Cannot send — TCP not connected", context: "Daemon")
            return
        }

        let payload = ["command": command]
        do {
            let data = try JSONSerialization.data(withJSONObject: payload)
            guard var jsonStr = String(data: data, encoding: .utf8) else { return }
            jsonStr += "\n"
            guard let lineData = jsonStr.data(using: .utf8) else { return }

            lineData.withUnsafeBytes { buffer in
                guard let ptr = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                output.write(ptr, maxLength: lineData.count)
            }
            log.info("→ \(jsonStr.prefix(200))", context: "Daemon")
        } catch {
            log.error("JSON serialize error: \(error.localizedDescription)", context: "Daemon")
        }
    }

    // MARK: - Read Loop

    private func startReading() {
        let thread = Thread { [weak self] in
            self?.readLoop()
        }
        thread.name = "DaemonTCPReader"
        thread.qualityOfService = .userInitiated
        thread.start()
        self.readThread = thread
    }

    private func readLoop() {
        guard let input = inputStream else { return }
        let bufferSize = 8192
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while input.streamStatus == .open {
            guard input.hasBytesAvailable else {
                Thread.sleep(forTimeInterval: 0.01)
                continue
            }

            let bytesRead = input.read(buffer, maxLength: bufferSize)
            if bytesRead <= 0 {
                break  // EOF or error
            }

            readBuffer.append(buffer, count: bytesRead)
            processLines()
        }

        DispatchQueue.main.async { [weak self] in
            self?.onDisconnect?()
        }
    }

    private func processLines() {
        while let range = readBuffer.range(of: Data([10])) {  // newline
            let lineData = readBuffer.subdata(in: 0..<range.lowerBound)
            readBuffer.removeSubrange(0...range.lowerBound)

            guard let line = String(data: lineData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !line.isEmpty else { continue }

            parseResponseLine(line)
        }
    }

    private func parseResponseLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = json["response"] as? [String: Any] else {
            log.info("stdout (raw): \(line.prefix(300))", context: "Daemon")
            return
        }

        let stage = response["stage"] as? String ?? "?"
        let status = response["status"] as? String ?? "?"
        log.info("← stage=\(stage) status=\(status)", context: "Daemon")

        DispatchQueue.main.async { [weak self] in
            self?.onResponse?(response)
        }
    }

    // MARK: - Disconnect

    /// Closes the connection streams and stops the reading thread.
    func disconnect() {
        inputStream?.close()
        outputStream?.close()
        readThread?.cancel()
        inputStream = nil
        outputStream = nil
        readThread = nil
        readBuffer = Data()
    }
}
