import SwiftUI

struct TitleScreen: View {
    private let version = "Version 26.0 Developer Build"
    private let discovery = MayhemDiscovery()
    @State private var joinRequestName: String?
    @State private var joinReply: ((Bool) -> Void)?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea(edges: .bottom)
            VStack(alignment: .leading, spacing: 8) {
                Text("MAYHEM KART")
                Button("Play") {}
                Button("Online Play") {}
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
            discovery.onPeerFound = { result in print("Mayhem Kart peer found: \(result)") }
            discovery.onPeerLost = { result in print("Mayhem Kart peer lost: \(result)") }
            discovery.onPeerRequest = { name, reply in
                DispatchQueue.main.async {
                    joinRequestName = name
                    joinReply = reply
                }
            }
            discovery.onPeerRejected = { reason in print("Mayhem Kart peer rejected: \(reason)") }
            discovery.start()
        }
        .onDisappear { discovery.stop() }
        .alert("Allow Device to Join Your Game?", isPresented: Binding(
            get: { joinRequestName != nil },
            set: { if !$0 { joinRequestName = nil; joinReply = nil } }
        )) {
            Button("Yes") { joinReply?(true); joinRequestName = nil; joinReply = nil }
            Button("No", role: .cancel) { joinReply?(false); joinRequestName = nil; joinReply = nil }
        } message: {
            Text("Device Name: \(joinRequestName ?? "Unknown Device")")
        }
    }
}
