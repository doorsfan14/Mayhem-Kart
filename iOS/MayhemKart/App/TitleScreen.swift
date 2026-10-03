import SwiftUI

struct TitleScreen: View {
    private let version = "Version 26.0 Developer Build"

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.08, green: 0.08, blue: 0.08)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            HStack {
                VStack(alignment: .leading, spacing: 12) {
                    Text("MAYHEM KART")
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .tracking(2)

                    MenuButton(title: "Play") {}
                    MenuButton(title: "Play 1/2/3/4") {}
                    MenuButton(title: "Online Play") {}
                    MenuButton(title: "Settings") {}
                    
                    Spacer()
                }
                .frame(width: 300, alignment: .leading)
                .padding(.leading, 56)
                .padding(.top, 54)

                Spacer()
            }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(version)
                        Text("Unauthorized distribution or disclosure is prohibited.")
                        Text("© 2026 Team Celeste™. All rights reserved.")
                    }
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.trailing)
                    .padding(.trailing, 28)
                    .padding(.bottom, 20)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct MenuButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 13)
                .padding(.horizontal, 18)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}
