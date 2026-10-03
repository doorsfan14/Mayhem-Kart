import SwiftUI
import MetalKit

struct GameView: View {
    var body: some View {
        MayhemMetalView()
            .ignoresSafeArea()
            .preferredColorScheme(.dark)
    }
}

private struct MayhemMetalView: UIViewRepresentable {
    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero)
        view.clearColor = MTLClearColor(red: 0.025, green: 0.035, blue: 0.05, alpha: 1)

        guard let renderer = MayhemMetalRenderer(view: view) else {
            return view
        }

        context.coordinator.renderer = renderer
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var renderer: MayhemMetalRenderer?
    }
}
