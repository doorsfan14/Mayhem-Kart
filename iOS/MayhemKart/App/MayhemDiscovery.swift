import Foundation
import Network

final class MayhemDiscovery: NSObject {
    static let serviceType = "_mayhemkart._tcp"

    private let listenerQueue = DispatchQueue(label: "net.teamceleste.mayhemkart.discovery.listener")
    private let browserQueue = DispatchQueue(label: "net.teamceleste.mayhemkart.discovery.browser")

    private var listener: NWListener?
    private var browser: NWBrowser?
    private var session: MayhemSession?

    var onPeerFound: ((NWBrowser.Result) -> Void)?
    var onPeerLost: ((NWBrowser.Result) -> Void)?
    var onPeerConnected: (() -> Void)?
    var onPeerRejected: ((String) -> Void)?

    func start() {
        stop()

        do {
            let listener = try NWListener(using: .tcp)
            listener.service = NWListener.Service(name: "Mayhem Kart iOS", type: Self.serviceType)

            listener.stateUpdateHandler = { [weak self] state in
                if case .failed = state {
                    self?.listener?.cancel()
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.beginSession(with: connection)
            }

            listener.start(queue: listenerQueue)
            self.listener = listener
        } catch {
            return
        }

        let browser = NWBrowser(
            for: .bonjour(type: Self.serviceType, domain: nil),
            using: .tcp
        )

        browser.browseResultsChangedHandler = { [weak self] results, changes in
            for change in changes {
                switch change {
                case .added(let result):
                    self?.onPeerFound?(result)
                    self?.beginSession(with: result.endpoint)
                case .removed(let result):
                    self?.onPeerLost?(result)
                default:
                    break
                }
            }
            _ = results
        }

        browser.stateUpdateHandler = { _ in }
        browser.start(queue: browserQueue)
        self.browser = browser
    }

    private func beginSession(with endpoint: NWEndpoint) {
        if session != nil { return }

        let session = MayhemSession()
        session.onConnected = { [weak self] in
            self?.onPeerConnected?()
        }
        session.onRejected = { [weak self] reason in
            self?.onPeerRejected?(reason)
            self?.session?.disconnect()
            self?.session = nil
        }
        session.onDisconnected = { [weak self] _ in
            self?.session = nil
        }

        self.session = session
        session.connect(to: endpoint)
    }

    func stop() {
        session?.disconnect()
        session = nil
        listener?.cancel()
        browser?.cancel()
        listener = nil
        browser = nil
    }

    deinit {
        stop()
    }
}
