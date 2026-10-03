import Foundation
import simd

public struct MayhemCamera {
    public var position: SIMD3<Float>
    public var target: SIMD3<Float>
    public var up: SIMD3<Float>
    public var fieldOfView: Float
    public var nearPlane: Float
    public var farPlane: Float

    public init(
        position: SIMD3<Float> = SIMD3(0, 1.5, 5),
        target: SIMD3<Float> = SIMD3(0, 0.5, 0),
        up: SIMD3<Float> = SIMD3(0, 1, 0),
        fieldOfView: Float = 60,
        nearPlane: Float = 0.05,
        farPlane: Float = 500
    ) {
        self.position = position
        self.target = target
        self.up = up
        self.fieldOfView = fieldOfView
        self.nearPlane = nearPlane
        self.farPlane = farPlane
    }
}

public struct MayhemGraphicsConfiguration {
    public var maximumFramesPerSecond: Int
    public var preferredSampleCount: Int
    public var enableDepth: Bool

    public init(
        maximumFramesPerSecond: Int = 60,
        preferredSampleCount: Int = 1,
        enableDepth: Bool = true
    ) {
        self.maximumFramesPerSecond = maximumFramesPerSecond
        self.preferredSampleCount = preferredSampleCount
        self.enableDepth = enableDepth
    }
}

public protocol MayhemGraphicsBackend {
    var camera: MayhemCamera { get set }
    func resize(width: Float, height: Float)
    func drawFrame(deltaTime: Float)
}
