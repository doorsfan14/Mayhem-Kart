import Foundation
import simd

public struct MayhemTimeOfDay {
    /// Decimal local time in hours. 0 = midnight, 12 = noon.
    public var hour: Float

    public init(hour: Float = 12) {
        self.hour = hour.truncatingRemainder(dividingBy: 24) >= 0
            ? hour.truncatingRemainder(dividingBy: 24)
            : hour.truncatingRemainder(dividingBy: 24) + 24
    }

    public var normalized: Float {
        hour / 24
    }

    /// Approximate sun direction used by the lighting system.
    public var sunDirection: SIMD3<Float> {
        let angle = (hour - 6) / 24 * 2 * .pi
        let elevation = sin(angle)
        let azimuth = cos(angle)
        return simd_normalize(SIMD3<Float>(azimuth * 0.65, max(elevation, -0.15), 0.45))
    }

    public var daylight: Float {
        let sun = sin((hour - 6) / 24 * 2 * .pi)
        return max(0, min(1, sun * 0.5 + 0.5))
    }

    public var skyBrightness: Float {
        0.08 + daylight * 0.92
    }

    public var cloudShadowStrength: Float {
        0.18 + daylight * 0.30
    }
}

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
    public var volumetricClouds: Bool
    public var skyShadows: Bool

    public init(
        maximumFramesPerSecond: Int = 60,
        preferredSampleCount: Int = 1,
        enableDepth: Bool = true,
        volumetricClouds: Bool = true,
        skyShadows: Bool = true
    ) {
        self.maximumFramesPerSecond = maximumFramesPerSecond
        self.preferredSampleCount = preferredSampleCount
        self.enableDepth = enableDepth
        self.volumetricClouds = volumetricClouds
        self.skyShadows = skyShadows
    }
}

public protocol MayhemGraphicsBackend {
    var camera: MayhemCamera { get set }
    func resize(width: Float, height: Float)
    func drawFrame(deltaTime: Float)
}
