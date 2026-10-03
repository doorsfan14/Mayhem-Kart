import Foundation
import Network

final class MayhemDiscovery: NSObject {
    static let serviceType = "_mayhemkart._tcp"

    private let listenerQueue = DispatchQueue(label: "net.teamceleste.mayhemkart.discovery.listener")
    private let browserQueue = DispatchQueue(label: "net.teamceleste.mayhemkart.discovery.browser")

    private var listener: NWListener?
    private var browser: NWBrowser?

    var onPeerFound: ((NWBrowser.Result) -> Void)?
    var onPeerLost: ((NWBrowser.Result) -> Void)?

    func start() {
        stop()

        do {
            let listener = try NWListener(using: .tcp)
            listener.service = NWListener.Service(
                name: "Mayhem Kart iOS",
                type: Self.serviceType
            )

            listener.stateUpdateHandler = { [weak self] state in
                guard self != nil else { return }
                if case .failed = state {
                    self?.listener?.cancel()
                }
            }

            listener.newConnectionHandler = { connection in
                connection.cancel()
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

    func stop() {
        listener?.cancel()
        browser?.cancel()
        listener = nil
        browser = nil
    }

    deinit {
        stop()
    }
}
