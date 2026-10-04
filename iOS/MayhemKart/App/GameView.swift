import SwiftUI
import UIKit
import MetalKit

struct GameView: View {
    @State private var timeOfDay: Float = 12
    @State private var speed: Double = 0
    @State private var position: Int = 1
    @State private var lap: Int = 1
    @State private var itemPulse = false

    var body: some View {
        ZStack {
            MayhemMetalView(timeOfDay: timeOfDay)
                .ignoresSafeArea()

            // Bare-bones game HUD. This is actual GUI content layered above Metal,
            // separate from the camera/atmospheric effects in the renderer.
            VStack {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("1st")
                            .font(.system(size: 28, weight: .heavy, design: .rounded))
                        Text("POSITION")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .opacity(0.72)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.58))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    Spacer()

                    VStack(alignment: .trailing, spacing: 3) {
                        Text("LAP \(lap)/3")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                        Text("00:00.000")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .opacity(0.78)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.58))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding(.horizontal)
                .padding(.top, 8)

                Spacer()

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ITEM")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .opacity(0.7)

                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.white.opacity(0.72), lineWidth: 1.5)
                            .frame(width: 58, height: 58)
                            .overlay {
                                Text("?")
                                    .font(.system(size: 27, weight: .heavy, design: .rounded))
                                    .opacity(itemPulse ? 1.0 : 0.72)
                                    .scaleEffect(itemPulse ? 1.08 : 1.0)
                            }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 0) {
                        Text(String(format: "%.0f", speed))
                            .font(.system(size: 42, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                        Text("KM/H")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .opacity(0.72)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 12)

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
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(
                .easeInOut(duration: 0.75)
                .repeatForever(autoreverses: true)
            ) {
                itemPulse = true
            }
        }
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

        let fpsLabel = UILabel()
        fpsLabel.text = "-- FPS"
        fpsLabel.textColor = .white
        fpsLabel.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .medium)
        fpsLabel.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        fpsLabel.layer.cornerRadius = 6
        fpsLabel.layer.masksToBounds = true
        fpsLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(fpsLabel)
        NSLayoutConstraint.activate([
            fpsLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            fpsLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10)
        ])
        renderer.fpsLabel = fpsLabel

        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        view.addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePinch(_:))
        )
        view.addGestureRecognizer(pinch)

        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.renderer?.timeOfDay = MayhemTimeOfDay(hour: timeOfDay)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject {
        var renderer: MayhemMetalRenderer?

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let renderer else { return }
            let translation = gesture.translation(in: gesture.view)
            renderer.orbitCamera(
                deltaX: Float(translation.x),
                deltaY: Float(translation.y)
            )
            gesture.setTranslation(.zero, in: gesture.view)
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let renderer else { return }
            if gesture.state == .changed {
                renderer.zoomCamera(scale: Float(gesture.scale))
                gesture.scale = 1
            }
        }
    }
}
