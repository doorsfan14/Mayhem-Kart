import Foundation
import MetalKit
import simd
import QuartzCore
import UIKit

final class MayhemMetalRenderer: NSObject, MTKViewDelegate {
    private struct SkyUniforms {
        var inverseViewProjection: simd_float4x4
        var cameraPosition: SIMD4<Float>
        var sunDirection: SIMD4<Float>
        var sky: SIMD4<Float>
    }

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let skyPipeline: MTLRenderPipelineState
    private let noDepthState: MTLDepthStencilState

    private var viewportSize = SIMD2<Float>(1, 1)
    private var elapsedTime: Float = 0
    private var lastTimestamp: CFTimeInterval = CACurrentMediaTime()
    private var fpsAccumulator: Float = 0
    private var fpsFrameCount = 0
    weak var fpsLabel: UILabel?

    /// Modders can set this directly per track, e.g. 7.5 for 07:30.
    var timeOfDay = MayhemTimeOfDay(hour: 12)

    var camera = MayhemCamera(
        position: SIMD3(0, 3.2, 8.5),
        target: SIMD3(0, 0.35, 0),
        up: SIMD3(0, 1, 0),
        fieldOfView: 58,
        nearPlane: 0.05,
        farPlane: 250
    )

    init?(view: MTKView) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else { return nil }

        self.device = device
        self.commandQueue = commandQueue

        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct SkyUniforms {
            float4x4 inverseViewProjection;
            float4 cameraPosition;
            float4 sunDirection;
            float4 sky;
        };

        float hash3(float3 p) {
            p = fract(p * 0.3183099 + float3(0.1, 0.2, 0.3));
            p *= 17.0;
            return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
        }

        float noise3(float3 p) {
            float3 i = floor(p);
            float3 f = fract(p);
            f = f * f * (3.0 - 2.0 * f);

            float n000 = hash3(i + float3(0, 0, 0));
            float n100 = hash3(i + float3(1, 0, 0));
            float n010 = hash3(i + float3(0, 1, 0));
            float n110 = hash3(i + float3(1, 1, 0));
            float n001 = hash3(i + float3(0, 0, 1));
            float n101 = hash3(i + float3(1, 0, 1));
            float n011 = hash3(i + float3(0, 1, 1));
            float n111 = hash3(i + float3(1, 1, 1));

            float nx00 = mix(n000, n100, f.x);
            float nx10 = mix(n010, n110, f.x);
            float nx01 = mix(n001, n101, f.x);
            float nx11 = mix(n011, n111, f.x);
            return mix(mix(nx00, nx10, f.y), mix(nx01, nx11, f.y), f.z);
        }

        float cloudDensity(float3 p) {
            float3 q = p * float3(0.028, 0.040, 0.028);
            float n = noise3(q) * 0.72;
            n += noise3(q * 2.0 + float3(7.1, 2.3, 4.7)) * 0.28;

            float height = smoothstep(22.0, 27.0, p.y) *
                           (1.0 - smoothstep(39.0, 45.0, p.y));
            return smoothstep(0.46, 0.66, n) * height;
        }

        vertex float4 sky_vertex(uint vertexID [[vertex_id]]) {
            const float2 positions[3] = {
                float2(-1, -1), float2(3, -1), float2(-1, 3)
            };
            return float4(positions[vertexID], 0, 1);
        }

        fragment float4 sky_fragment(
            float4 position [[position]],
            constant SkyUniforms &uniforms [[buffer(0)]]
        ) {
            float2 uv = position.xy / uniforms.sky.zw;
            float2 ndc = float2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);

            float4 nearPoint = uniforms.inverseViewProjection * float4(ndc, 0, 1);
            float4 farPoint = uniforms.inverseViewProjection * float4(ndc, 1, 1);
            nearPoint /= nearPoint.w;
            farPoint /= farPoint.w;

            float3 ray = normalize(farPoint.xyz - nearPoint.xyz);
            float3 sun = normalize(uniforms.sunDirection.xyz);
            float sunAmount = max(dot(ray, sun), 0.0);

            float3 horizon = float3(0.43, 0.63, 0.90);
            float3 zenith = float3(0.035, 0.10, 0.24);
            float height = clamp(ray.y * 0.5 + 0.5, 0.0, 1.0);
            float3 skyColor = mix(horizon, zenith, height);

            // Keep the actual atmospheric horizon visible where the sky meets the track.
            float horizonBand = 1.0 - smoothstep(0.0, 0.12, abs(ray.y));
            skyColor = mix(skyColor, horizon, horizonBand * 0.55);

            float cloudAccum = 0.0;
            float transmittance = 1.0;
            float3 samplePoint = uniforms.cameraPosition.xyz + ray * 22.0;
            for (int i = 0; i < 10; ++i) {
                samplePoint += ray * 5.0;
                float density = cloudDensity(samplePoint);
                float lightProbe = cloudDensity(samplePoint + sun * 8.0);
                float lit = 0.45 + (1.0 - lightProbe) * 0.55;
                float contribution = density * 0.22;
                cloudAccum += contribution * transmittance * lit;
                transmittance *= 1.0 - density * 0.14;
                if (transmittance < 0.03) break;
            }

            float daylight = uniforms.sky.x;
            float3 cloudColor = mix(float3(0.12, 0.14, 0.17), float3(1.0, 0.98, 0.92), daylight);
            skyColor = mix(skyColor, cloudColor, clamp(cloudAccum, 0.0, 0.92));

            // Dynamic sun glare: only appears when the camera is actually aimed at the sun.
            // Keep it cheap: one smooth directional mask and a tiny radial falloff.
            float glareAlignment = max(dot(ray, sun), 0.0);
            float glare = pow(glareAlignment, 96.0) * (0.35 + daylight * 0.65);
            float glareHalo = pow(glareAlignment, 18.0) * 0.10 * daylight;
            float3 glareColor = float3(1.0, 0.82, 0.48);
            skyColor += glareColor * (glare * 1.35 + glareHalo);
            skyColor *= uniforms.sky.y;

            return float4(clamp(skyColor, 0.0, 1.0), 1.0);
        }
        """

        guard let library = try? device.makeLibrary(source: shaderSource, options: nil),
              let skyVertex = library.makeFunction(name: "sky_vertex"),
              let skyFragment = library.makeFunction(name: "sky_fragment") else { return nil }

        let skyDescriptor = MTLRenderPipelineDescriptor()
        skyDescriptor.vertexFunction = skyVertex
        skyDescriptor.fragmentFunction = skyFragment
        skyDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat

        guard let skyPipeline = try? device.makeRenderPipelineState(descriptor: skyDescriptor) else { return nil }
        self.skyPipeline = skyPipeline

        let noDepthDescriptor = MTLDepthStencilDescriptor()
        noDepthDescriptor.depthCompareFunction = .always
        noDepthDescriptor.isDepthWriteEnabled = false

        guard let noDepthState = device.makeDepthStencilState(descriptor: noDepthDescriptor) else { return nil }
        self.noDepthState = noDepthState

        super.init()

        if view.drawableSize.width > 0, view.drawableSize.height > 0 {
            viewportSize = SIMD2(
                Float(view.drawableSize.width),
                Float(view.drawableSize.height)
            )
        }

        view.device = device
        view.delegate = self
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.autoResizeDrawable = true
        view.contentScaleFactor = UIScreen.main.scale
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewportSize = SIMD2(Float(max(size.width, 1)), Float(max(size.height, 1)))
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }

        let now = CACurrentMediaTime()
        let deltaTime = Float(min(max(now - lastTimestamp, 0.0), 0.05))
        lastTimestamp = now
        elapsedTime += deltaTime

        fpsAccumulator += deltaTime
        fpsFrameCount += 1
        if fpsAccumulator >= 0.25 {
            let fps = Float(fpsFrameCount) / fpsAccumulator
            let text = String(format: "%.0f FPS", fps)
            DispatchQueue.main.async { [weak self] in
                self?.fpsLabel?.text = text
            }
            fpsAccumulator = 0
            fpsFrameCount = 0
        }

        let aspect = viewportSize.x / max(viewportSize.y, 1)
        let projection = Self.perspective(
            fovY: camera.fieldOfView * .pi / 180,
            aspect: aspect,
            near: camera.nearPlane,
            far: camera.farPlane
        )
        let viewMatrix = Self.lookAt(eye: camera.position, target: camera.target, up: camera.up)
        let inverseViewProjection = simd_inverse(simd_mul(projection, viewMatrix))

        let sun = timeOfDay.sunDirection
        let daylight = timeOfDay.daylight

        var skyUniforms = SkyUniforms(
            inverseViewProjection: inverseViewProjection,
            cameraPosition: SIMD4(camera.position, 1),
            sunDirection: SIMD4(sun, 0),
            sky: SIMD4(daylight, timeOfDay.skyBrightness, viewportSize.x, viewportSize.y)
        )

        encoder.setRenderPipelineState(skyPipeline)
        encoder.setDepthStencilState(noDepthState)
        encoder.setFragmentBytes(&skyUniforms, length: MemoryLayout<SkyUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }


    func orbitCamera(deltaX: Float, deltaY: Float) {
        let offset = camera.position - camera.target
        let radius = max(simd_length(offset), 0.5)
        var yaw = atan2(offset.x, offset.z)
        var pitch = asin(offset.y / radius)
        yaw -= deltaX * 0.008
        pitch += deltaY * 0.008
        pitch = min(max(pitch, -1.35), 1.35)
        camera.position = camera.target + SIMD3<Float>(
            sin(yaw) * cos(pitch) * radius,
            sin(pitch) * radius,
            cos(yaw) * cos(pitch) * radius
        )
    }

    private static func perspective(fovY: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let y = 1 / tan(fovY * 0.5)
        let x = y / aspect
        let z = far / (near - far)
        return simd_float4x4(columns: (
            SIMD4(x, 0, 0, 0),
            SIMD4(0, y, 0, 0),
            SIMD4(0, 0, z, -1),
            SIMD4(0, 0, z * near, 0)
        ))
    }

    private static func lookAt(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let z = simd_normalize(eye - target)
        let x = simd_normalize(simd_cross(up, z))
        let y = simd_cross(z, x)
        return simd_float4x4(columns: (
            SIMD4(x.x, y.x, z.x, 0),
            SIMD4(x.y, y.y, z.y, 0),
            SIMD4(x.z, y.z, z.z, 0),
            SIMD4(-simd_dot(x, eye), -simd_dot(y, eye), -simd_dot(z, eye), 1)
        ))
    }

    private static func rotationY(_ angle: Float) -> simd_float4x4 {
        let c = cos(angle)
        let s = sin(angle)
        return simd_float4x4(columns: (
            SIMD4(c, 0, -s, 0),
            SIMD4(0, 1, 0, 0),
            SIMD4(s, 0, c, 0),
            SIMD4(0, 0, 0, 1)
        ))
    }
}
