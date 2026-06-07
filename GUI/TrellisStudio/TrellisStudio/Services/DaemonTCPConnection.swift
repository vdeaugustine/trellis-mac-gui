import Foundation
import Network

/// Manages a TCP connection to the daemon process using Network.framework.
///
/// Uses `NWConnection` instead of CFStream to avoid priority inversions and
/// properly handle asynchronous connection establishment. The old CFStream
/// approach checked stream status immediately after a non-blocking `open()`,
/// which always failed because the status was `.opening` (1), not `.open` (2).
final class DaemonTCPConnection {

    private var connection: NWConnection?
    private var readBuffer = Data()

    private let networkQueue = DispatchQueue(
        label: "com.vinware.trellis-studio.daemon-tcp",
        qos: .userInitiated
    )

    private let log = AppLogger.shared

    /// Called whenever a complete JSON response is received from the daemon.
    var onResponse: (([String: Any]) -> Void)?

    /// Called when the TCP connection disconnects or fails.
    var onDisconnect: (() -> Void)?

    /// Whether the TCP connection is currently in the `.ready` state.
    var isConnected: Bool {
        connection?.state == .ready
    }

    // MARK: - Connect

    /// Establishes a TCP connection to localhost on the given port.
    ///
    /// - Parameters:
    ///   - port: The port number the daemon is listening on.
    ///   - completion: Called on the main queue with `true` if connected.
    func connect(port: Int, completion: @escaping (Bool) -> Void) {
        // Tear down any existing connection first
        disconnectInternal()

        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            log.error("Invalid port number: \(port)", context: "Daemon")
            DispatchQueue.main.async { completion(false) }
            return
        }

        let host = NWEndpoint.Host("127.0.0.1")
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback

        let conn = NWConnection(host: host, port: nwPort, using: params)
        self.connection = conn

        var completionCalled = false

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                if !completionCalled {
                    completionCalled = true
                    self.log.info("TCP connected to daemon on port \(port)", context: "Daemon")
                    self.startReceiving()
                    DispatchQueue.main.async { completion(true) }
                }

            case .failed(let error):
                self.log.error("TCP connection failed: \(error.localizedDescription)", context: "Daemon")
                if !completionCalled {
                    completionCalled = true
                    DispatchQueue.main.async { completion(false) }
                }
                self.handleConnectionLost()

            case .cancelled:
                if !completionCalled {
                    completionCalled = true
                    DispatchQueue.main.async { completion(false) }
                }

            case .waiting(let error):
                self.log.warning("TCP connection waiting: \(error.localizedDescription)", context: "Daemon")

            default:
                break
            }
        }

        conn.start(queue: networkQueue)

        // Timeout: if not connected within 5 seconds, fail
        networkQueue.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard !completionCalled else { return }
            completionCalled = true
            self?.log.error("TCP connect timed out after 5s on port \(port)", context: "Daemon")
            conn.cancel()
            DispatchQueue.main.async { completion(false) }
        }
    }

    // MARK: - Send

    /// Encodes a dictionary as JSON and writes it to the TCP connection.
    ///
    /// - Parameter command: The dictionary to encode and send.
    func send(command: [String: Any]) {
        guard let conn = connection, conn.state == .ready else {
            log.error("Cannot send — TCP not connected", context: "Daemon")
            return
        }

        let payload = ["command": command]
        do {
            let data = try JSONSerialization.data(withJSONObject: payload)
            guard var jsonStr = String(data: data, encoding: .utf8) else { return }
            jsonStr += "\n"
            guard let lineData = jsonStr.data(using: .utf8) else { return }

            conn.send(content: lineData, completion: .contentProcessed { [weak self] error in
                if let error {
                    self?.log.error("TCP send error: \(error.localizedDescription)", context: "Daemon")
                }
            })
            log.info("→ \(jsonStr.prefix(200))", context: "Daemon")
        } catch {
            log.error("JSON serialize error: \(error.localizedDescription)", context: "Daemon")
        }
    }

    // MARK: - Receive Loop

    private func startReceiving() {
        scheduleReceive()
    }

    private func scheduleReceive() {
        guard let conn = connection, conn.state == .ready else { return }

        conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] content, _, isComplete, error in
            guard let self else { return }

            if let data = content, !data.isEmpty {
                self.readBuffer.append(data)
                self.processLines()
            }

            if isComplete || error != nil {
                self.handleConnectionLost()
                return
            }

            // Continue reading
            self.scheduleReceive()
        }
    }

    private func processLines() {
        while let newlineIndex = readBuffer.firstIndex(of: 0x0A) {
            let lineData = readBuffer[readBuffer.startIndex..<newlineIndex]
            readBuffer.removeSubrange(readBuffer.startIndex...newlineIndex)

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

    /// Closes the connection and resets internal state.
    func disconnect() {
        disconnectInternal()
    }

    private func disconnectInternal() {
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        readBuffer = Data()
    }

    private func handleConnectionLost() {
        disconnectInternal()
        DispatchQueue.main.async { [weak self] in
            self?.onDisconnect?()
        }
    }
}
