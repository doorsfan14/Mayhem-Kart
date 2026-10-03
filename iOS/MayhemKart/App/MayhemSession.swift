import Foundation
import Network
import UIKit

private enum MayhemPacket {
    static let magic = "MAYHEM"
    static let protocolVersion = 2
    static let engineVersion = "26.0"
    static let maxPayloadSize = 1_048_576

    case hello(version: Int, engine: String, deviceName: String)
    case accept
    case reject(reason: String)

    func encoded() throws -> Data {
        let payload: String
        switch self {
        case let .hello(version, engine, deviceName):
            payload = "(Self.magic)\tHELLO\t\(version)\t\(engine)\t\(deviceName)\n"
        case .accept:
            payload = "(Self.magic)\tACCEPT\n"
        case let .reject(reason):
            payload = "(Self.magic)\tREJECT\t\(reason)\n"
        }
        guard let body = payload.data(using: .utf8), body.count <= Self.maxPayloadSize else {
            throw NSError(domain: "MayhemProtocol", code: 1)
        }
        var length = UInt32(body.count).bigEndian
        var packet = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        packet.append(body)
        return packet
    }

    static func decode(_ data: Data) -> MayhemPacket? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let parts = text.trimmingCharacters(in: .newlines)
            .split(separator: "\t", omittingEmptySubsequences: false)
        guard parts.count >= 2, parts[0] == Substring(Self.magic) else { return nil }

        switch parts[1] {
        case "HELLO":
            guard parts.count == 5, let version = Int(parts[2]), version == protocolVersion else { return nil }
            return .hello(version: version, engine: String(parts[3]), deviceName: parts[4].isEmpty ? "Unknown Device" : String(parts[4]))
        case "ACCEPT":
            return .accept
        case "REJECT":
            guard parts.count == 3 else { return nil }
            return .reject(reason: String(parts[2]))
        default:
            return nil
        }
    }
}

final class MayhemSession {
    static let protocolVersion = MayhemPacket.protocolVersion
    static let engineVersion = MayhemPacket.engineVersion

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "net.teamceleste.mayhemkart.session")
    private var receiveBuffer = Data()
    private var initiatedConnection = false
    private var receivedHello = false
    private var connected = false

    var onConnected: (() -> Void)?
    var onDisconnected: ((Error?) -> Void)?
    var onRejected: ((String) -> Void)?
    var onPeerRequest: ((String, @escaping (Bool) -> Void) -> Void)?

    func connect(to endpoint: NWEndpoint) {
        disconnect()
        initiatedConnection = true
        start(NWConnection(to: endpoint, using: .tcp))
    }

    func accept(_ connection: NWConnection) {
        disconnect()
        initiatedConnection = false
        start(connection)
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        receiveBuffer.removeAll(keepingCapacity: false)
        receivedHello = false
        connected = false
    }

    private func start(_ connection: NWConnection) {
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.sendHello()
                self?.receive()
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
        let name = UIDevice.current.name
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        send(.hello(version: Self.protocolVersion, engine: Self.engineVersion, deviceName: name))
    }

    private func send(_ packet: MayhemPacket) {
        do {
            let data = try packet.encoded()
            connection?.send(content: data, completion: .contentProcessed { [weak self] error in
                if let error { self?.onDisconnected?(error) }
            })
        } catch {
            onRejected?("Unable to encode Mayhem Kart packet.")
            disconnect()
        }
    }

    private func receive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65_535) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                self.onDisconnected?(error)
                return
            }
            if isComplete {
                self.onDisconnected?(nil)
                return
            }
            if let data { self.receiveBuffer.append(data) }
            self.processPackets()
            if self.connection != nil { self.receive() }
        }
    }

    private func processPackets() {
        while receiveBuffer.count >= 4 {
            let length = (UInt32(receiveBuffer[0]) << 24) | (UInt32(receiveBuffer[1]) << 16) | (UInt32(receiveBuffer[2]) << 8) | UInt32(receiveBuffer[3])
            guard length > 0, length <= UInt32(MayhemPacket.maxPayloadSize) else {
                onRejected?("Invalid Mayhem Kart packet size.")
                disconnect()
                return
            }
            let total = 4 + Int(length)
            guard receiveBuffer.count >= total else { return }
            let payload = receiveBuffer.subdata(in: 4..<total)
            receiveBuffer.removeSubrange(0..<total)
            guard let packet = MayhemPacket.decode(payload) else {
                onRejected?("Invalid Mayhem Kart packet.")
                disconnect()
                return
            }
            handle(packet)
        }
    }

    private func handle(_ packet: MayhemPacket) {
        switch packet {
        case let .hello(version, engine, deviceName):
            guard version == Self.protocolVersion, engine == Self.engineVersion, !receivedHello else {
                onRejected?("Incompatible Mayhem Kart version.")
                disconnect()
                return
            }
            receivedHello = true
            if initiatedConnection { return }
            onPeerRequest?(deviceName) { [weak self] allowed in
                guard let self else { return }
                if allowed {
                    self.send(.accept)
                    self.markConnected()
                } else {
                    self.send(.reject(reason: "The host declined the connection."))
                    self.disconnect()
                }
            }

        case .accept:
            guard initiatedConnection else { return }
            markConnected()

        case let .reject(reason):
            onRejected?(reason)
            disconnect()
        }
    }

    private func markConnected() {
        guard !connected else { return }
        connected = true
        onConnected?()
    }

    deinit { disconnect() }
}
