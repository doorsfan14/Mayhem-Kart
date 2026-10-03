import Foundation
import Network
import UIKit

final class MayhemSession {
    static let protocolVersion = 1
    static let engineVersion = "26.0"
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "net.teamceleste.mayhemkart.session")
    private var receivedHello = false

    var onConnected: (() -> Void)?
    var onDisconnected: ((Error?) -> Void)?
    var onRejected: ((String) -> Void)?
    var onPeerRequest: ((String, @escaping (Bool) -> Void) -> Void)?

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
            case .ready: self?.sendHello()
            case .failed(let error): self?.onDisconnected?(error)
            case .cancelled: self?.onDisconnected?(nil)
            default: break
            }
        }
        connection.start(queue: queue)
    }

    private func sendHello() {
        let name = UIDevice.current.name.replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        let hello = "MAYHEM\tHELLO\t\(Self.protocolVersion)\t\(Self.engineVersion)\t\(name)\n"
        connection?.send(content: hello.data(using: .utf8), completion: .contentProcessed { [weak self] error in
            if let error { self?.onDisconnected?(error); return }
            self?.receiveMessage()
        })
    }

    private func receiveMessage() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 2048) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error { self.onDisconnected?(error); return }
            if isComplete { self.onDisconnected?(nil); return }
            guard let data, let message = String(data: data, encoding: .utf8) else {
                self.onRejected?("Invalid Mayhem Kart message.")
                self.disconnect()
                return
            }
            for line in message.split(separator: "\n", omittingEmptySubsequences: true) {
                self.handleMessage(String(line))
            }
            if self.connection != nil { self.receiveMessage() }
        }
    }

    private func handleMessage(_ message: String) {
        let parts = message.split(separator: "\t", omittingEmptySubsequences: false)
        guard parts.count >= 2, parts[0] == "MAYHEM" else {
            onRejected?("Invalid Mayhem Kart message.")
            disconnect()
            return
        }

        switch parts[1] {
        case "HELLO":
            guard parts.count == 5, let version = Int(parts[2]), version == Self.protocolVersion else {
                onRejected?("Incompatible protocol version.")
                disconnect()
                return
            }
            guard !receivedHello else { return }
            receivedHello = true
            let name = String(parts[4]).isEmpty ? "Unknown Device" : String(parts[4])
            onPeerRequest?(name) { [weak self] allowed in
                self?.sendApproval(allowed)
            }
        case "ACCEPT":
            onConnected?()
        case "REJECT":
            onRejected?("The host declined the connection.")
            disconnect()
        default:
            onRejected?("Invalid Mayhem Kart message.")
            disconnect()
        }
    }

    private func sendApproval(_ allowed: Bool) {
        let command = allowed ? "ACCEPT" : "REJECT"
        let message = "MAYHEM\t\(command)\n"
        connection?.send(content: message.data(using: .utf8), completion: .contentProcessed { [weak self] error in
            if let error { self?.onDisconnected?(error); return }
            if !allowed { self?.disconnect() } else { self?.onConnected?() }
        })
    }

    deinit { disconnect() }
}
