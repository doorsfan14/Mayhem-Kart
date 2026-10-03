import Foundation
import Network

final class MayhemSession {
    static let protocolVersion = 1
    static let engineVersion = "26.0"

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "net.teamceleste.mayhemkart.session")

    var onConnected: (() -> Void)?
    var onDisconnected: ((Error?) -> Void)?
    var onRejected: ((String) -> Void)?

    func connect(to endpoint: NWEndpoint) {
        disconnect()
        start(NWConnection(to: endpoint, using: .tcp))
    }

    func accept(_ connection: NWConnection) {
        disconnect()
        start(connection)
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
    }

    private func start(_ connection: NWConnection) {
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.sendHello()
            case .failed(let error):
                self?.onDisconnected?(error)
            case .cancelled:
                self?.onDisconnected?(nil)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func sendHello() {
        let hello = "MAYHEM\tHELLO\t\(Self.protocolVersion)\t\(Self.engineVersion)\n"
        connection?.send(content: hello.data(using: .utf8), completion: .contentProcessed { [weak self] error in
            if let error {
                self?.onDisconnected?(error)
                return
            }
            self?.receiveHello()
        })
    }

    private func receiveHello() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                self.onDisconnected?(error)
                return
            }
            if isComplete {
                self.onDisconnected?(nil)
                return
            }

            guard let data, let message = String(data: data, encoding: .utf8),
                  let hello = Self.parseHello(message) else {
                self.onRejected?("Invalid Mayhem Kart handshake.")
                self.disconnect()
                return
            }

            guard hello.protocolVersion == Self.protocolVersion else {
                self.onRejected?("Incompatible protocol version.")
                self.disconnect()
                return
            }

            self.onConnected?()
        }
    }

    private static func parseHello(_ message: String) -> (protocolVersion: Int, engineVersion: String)? {
        let parts = message.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\t", omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0] == "MAYHEM", parts[1] == "HELLO", let version = Int(parts[2]) else {
            return nil
        }
        return (version, String(parts[3]))
    }

    deinit {
        disconnect()
    }
}
