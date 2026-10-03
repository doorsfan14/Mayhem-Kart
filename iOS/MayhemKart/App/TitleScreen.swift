import SwiftUI
import Network

struct TitleScreen: View {
    private struct Peer: Identifiable {
        let id: String
        let name: String
        let endpoint: NWEndpoint
    }

    private let version = "Version 26.0 Developer Build"
    private let discovery = MayhemDiscovery()

    @State private var peers: [Peer] = []
    @State private var showingOnline = false
    @State private var status = ""
    @State private var joinRequestName: String?
    @State private var joinReply: ((Bool) -> Void)?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea(edges: .bottom)

            VStack(alignment: .leading, spacing: 8) {
                Text("MAYHEM KART")
                Button("Play") {}

                Button("Online Play") {
                    showingOnline.toggle()
                }

                if showingOnline {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Nearby Players")
                            .font(.headline)

                        if peers.isEmpty {
                            Text("Searching...")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(peers) { peer in
                                Button(peer.name) {
                                    status = "Connecting to (peer.name)…"
                                    discovery.connect(to: peer.endpoint)
                                }
                            }
                        }

                        if !status.isEmpty {
                            Text(status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }

                Button("Settings") {}
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(20)
            .ignoresSafeArea(edges: .bottom)

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(version)
                        Text("Unauthorized distribution or disclosure is prohibited.")
                        Text("© 2026 Team Celeste™. All rights reserved.")
                    }
                    .font(.caption2)
                    .multilineTextAlignment(.trailing)
                }
            }
            .padding(8)
            .ignoresSafeArea(edges: .bottom)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            discovery.onPeerFound = { result in
                let id = String(describing: result.endpoint)
                let name: String
                switch result.endpoint {
                case let .service(serviceName, _, _, _):
                    name = serviceName
                default:
                    name = id
                }

                DispatchQueue.main.async {
                    if !peers.contains(where: { $0.id == id }) {
                        peers.append(Peer(id: id, name: name, endpoint: result.endpoint))
                    }
                }
            }

            discovery.onPeerLost = { result in
                let id = String(describing: result.endpoint)
                DispatchQueue.main.async {
                    peers.removeAll { $0.id == id }
                }
            }

            discovery.onPeerRequest = { name, reply in
                DispatchQueue.main.async {
                    joinRequestName = name
                    joinReply = reply
                }
            }

            discovery.onPeerConnected = {
                DispatchQueue.main.async {
                    status = "Connected."
                }
            }

            discovery.onPeerRejected = { reason in
                DispatchQueue.main.async {
                    status = reason
                }
            }

            discovery.start()
        }
        .onDisappear {
            discovery.stop()
        }
        .alert("Allow Device to Join Your Game?", isPresented: Binding(
            get: { joinRequestName != nil },
            set: {
                if !$0 {
                    joinRequestName = nil
                    joinReply = nil
                }
            }
        )) {
            Button("Yes") {
                joinReply?(true)
                joinRequestName = nil
                joinReply = nil
            }
            Button("No", role: .cancel) {
                joinReply?(false)
                joinRequestName = nil
                joinReply = nil
            }
        } message: {
            Text("Device Name: \(joinRequestName ?? "Unknown Device")")
        }
    }
}
