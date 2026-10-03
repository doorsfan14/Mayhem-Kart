import Foundation

enum MayhemPacket {
    static let magic = "MAYHEM"
    static let protocolVersion = 2
    static let engineVersion = "26.0"

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
        guard let body = payload.data(using: .utf8), body.count <= 1_048_576 else {
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
