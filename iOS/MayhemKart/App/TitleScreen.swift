import SwiftUI

struct TitleScreen: View {
    private let version = "Version 26.0 Developer Build"

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 8) {
                Text("MAYHEM KART")
                Button("Play") {}
                Button("Play 1/2/3/4") {}
                Button("Online Play") {}
                Button("Settings") {}

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(20)
            .ignoresSafeArea()

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
            .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
    }
}
