import SwiftUI
import UIKit
import MetalKit

struct GameView: View {
    @State private var timeOfDay: Float = 12

    var body: some View {
        ZStack(alignment: .bottom) {
            MayhemMetalView(timeOfDay: timeOfDay)
                .ignoresSafeArea()

            VStack(spacing: 8) {
                HStack {
                    Text("TimeOfDay")
                    Spacer()
                    Text(String(Int(timeOfDay)) + ":00")
                        .monospacedDigit()
                }

                Slider(value: Binding(
                    get: { Double(timeOfDay) },
                    set: { timeOfDay = Float($0) }
                ), in: 0...24, step: 0.25)
            }
            .padding(14)
            .background(.black.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding()
        }
        .preferredColorScheme(.dark)
    }
}

private struct MayhemMetalView: UIViewRepresentable {
    let timeOfDay: Float

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero)
        view.clearColor = MTLClearColor(red: 0.025, green: 0.035, blue: 0.05, alpha: 1)

        guard let renderer = MayhemMetalRenderer(view: view) else {
            return view
        }

        renderer.timeOfDay = MayhemTimeOfDay(hour: timeOfDay)
        context.coordinator.renderer = renderer
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.renderer?.timeOfDay = MayhemTimeOfDay(hour: timeOfDay)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var renderer: MayhemMetalRenderer?
    }
}
