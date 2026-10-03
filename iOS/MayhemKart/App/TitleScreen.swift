import SwiftUI

struct TitleScreen: View {
    private let version = "Version 26.0 Developer Build"
    private let discovery = MayhemDiscovery()

    var body: some View {
        ZStack {
            // The render surface is edge-to-edge, including the areas behind
            // the notch / Dynamic Island and Home Indicator.
            Color.black
                .ignoresSafeArea()

            // UI stays inside the system safe area so it never sits under
            // the notch, Dynamic Island, or Home Indicator.
            VStack(alignment: .leading, spacing: 8) {
                Text("MAYHEM KART")
                Button("Play") {}
                Button("Online Play") {}
                Button("Settings") {}

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(20)

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
        }
        .preferredColorScheme(.dark)
        .onAppear {
            discovery.onPeerFound = { _ in
                print("Mayhem Kart peer found")
            }
            discovery.onPeerLost = { _ in
                print("Mayhem Kart peer lost")
            }
            discovery.start()
        }
        .onDisappear {
            discovery.stop()
        }
    }
}
