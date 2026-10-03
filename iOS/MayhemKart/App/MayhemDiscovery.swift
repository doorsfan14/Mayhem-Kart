import Foundation
import Network

final class MayhemDiscovery: NSObject {
    static let serviceType = "_mayhemkart._tcp"
    static let maxPlayers = 4
    private let listenerQueue = DispatchQueue(label: "net.teamceleste.mayhemkart.discovery.listener")
    private let browserQueue = DispatchQueue(label: "net.teamceleste.mayhemkart.discovery.browser")
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var sessions: [UUID: MayhemSession] = [:]

    var onPeerFound: ((NWBrowser.Result) -> Void)?
    var onPeerLost: ((NWBrowser.Result) -> Void)?
    var onPeerRequest: ((String, @escaping (Bool) -> Void) -> Void)?
    var onPeerConnected: (() -> Void)?
    var onPeerRejected: ((String) -> Void)?

    func start() {
        stop()
        do {
            let listener = try NWListener(using: .tcp)
            listener.service = NWListener.Service(name: "Mayhem Kart iOS", type: Self.serviceType)
            listener.stateUpdateHandler = { [weak self] state in
                if case .failed = state { self?.listener?.cancel() }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.beginSession(with: connection)
            }
            listener.start(queue: listenerQueue)
            self.listener = listener
        } catch { return }

        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, changes in
            for change in changes {
                switch change {
                case .added(let result): self?.onPeerFound?(result)
                case .removed(let result): self?.onPeerLost?(result)
                default: break
                }
            }
            _ = results
        }
        browser.stateUpdateHandler = { _ in }
        browser.start(queue: browserQueue)
        self.browser = browser
    }

    func connect(to endpoint: NWEndpoint) {
        guard sessions.count < Self.maxPlayers - 1 else { return }
        beginSession(with: endpoint)
    }

    private func attach(_ session: MayhemSession, id: UUID) {
        session.onPeerRequest = { [weak self] name, reply in self?.onPeerRequest?(name, reply) }
        session.onConnected = { [weak self] in self?.onPeerConnected?() }
        session.onRejected = { [weak self] reason in
            self?.onPeerRejected?(reason)
            self?.sessions.removeValue(forKey: id)
        }
        session.onDisconnected = { [weak self] _ in self?.sessions.removeValue(forKey: id) }
    }

    private func beginSession(with endpoint: NWEndpoint) {
        guard sessions.count < Self.maxPlayers - 1 else { return }
        let id = UUID()
        let session = MayhemSession()
        attach(session, id: id)
        sessions[id] = session
        session.connect(to: endpoint)
    }

    private func beginSession(with connection: NWConnection) {
        guard sessions.count < Self.maxPlayers - 1 else { connection.cancel(); return }
        let id = UUID()
        let session = MayhemSession()
        attach(session, id: id)
        sessions[id] = session
        session.accept(connection)
    }

    func stop() {
        sessions.values.forEach { $0.disconnect() }
        sessions.removeAll()
        listener?.cancel()
        browser?.cancel()
        listener = nil
        browser = nil
    }

    deinit { stop() }
}
