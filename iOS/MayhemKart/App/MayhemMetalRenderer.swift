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

        struct Vertex {
            float3 position;
            float3 normal;
        };

        struct FrameUniforms {
            float4x4 modelViewProjection;
            float4x4 model;
            float4 lightDirection;
            float4 baseColor;
            float4 timeOfDay;
        };

        struct SkyUniforms {
            float4x4 inverseViewProjection;
            float4 cameraPosition;
            float4 sunDirection;
            float4 sky;
        };

        struct SceneOut {
            float4 position [[position]];
            float3 normal;
            float3 worldPosition;
        };

        float hash21(float2 p) {
            p = fract(p * float2(123.34, 456.21));
            p += dot(p, p + 45.32);
            return fract(p.x * p.y);
        }

        float noise3(float3 p) {
            float3 i = floor(p);
            float3 f = fract(p);
            f = f * f * (3.0 - 2.0 * f);
            float n000 = hash21(i.xy + i.z * 17.0);
            float n100 = hash21(i.xy + float2(1, 0) + i.z * 17.0);
            float n010 = hash21(i.xy + float2(0, 1) + i.z * 17.0);
            float n110 = hash21(i.xy + float2(1, 1) + i.z * 17.0);
            float n001 = hash21(i.xy + (i.z + 1.0) * 17.0);
            float n101 = hash21(i.xy + float2(1, 0) + (i.z + 1.0) * 17.0);
            float n011 = hash21(i.xy + float2(0, 1) + (i.z + 1.0) * 17.0);
            float n111 = hash21(i.xy + float2(1, 1) + (i.z + 1.0) * 17.0);
            float x00 = mix(n000, n100, f.x);
            float x10 = mix(n010, n110, f.x);
            float x01 = mix(n001, n101, f.x);
            float x11 = mix(n011, n111, f.x);
            return mix(mix(x00, x10, f.y), mix(x01, x11, f.y), f.z);
        }

        float cloudDensity(float3 p) {
            float3 q = p * float3(0.032, 0.045, 0.032);
            float n = noise3(q) * 0.58;
            n += noise3(q * 2.15 + float3(4.1, 1.7, 8.3)) * 0.27;
            n += noise3(q * 4.5 + float3(2.2, 7.4, 3.6)) * 0.15;

            float height = smoothstep(22.0, 27.0, p.y) * (1.0 - smoothstep(39.0, 45.0, p.y));
            float billow = smoothstep(0.44, 0.68, n);
            return billow * height;
        }

        float cloudShadow(float3 worldPosition, float3 sunDirection) {
            float3 p = worldPosition + float3(0, 34, 0);
            float shadow = 0.0;
            for (int i = 0; i < 8; ++i) {
                p += sunDirection * 7.0;
                shadow += cloudDensity(p);
            }
            return clamp(shadow / 8.0, 0.0, 1.0);
        }

        vertex SceneOut mayhem_vertex(
            const device Vertex *vertices [[buffer(0)]],
            constant FrameUniforms &uniforms [[buffer(1)]],
            uint vertexID [[vertex_id]]
        ) {
            SceneOut out;
            float4 world = uniforms.model * float4(vertices[vertexID].position, 1.0);
            out.position = uniforms.modelViewProjection * float4(vertices[vertexID].position, 1.0);
            out.normal = normalize((uniforms.model * float4(vertices[vertexID].normal, 0.0)).xyz);
            out.worldPosition = world.xyz;
            return out;
        }

        fragment float4 mayhem_fragment(
            SceneOut in [[stage_in]],
            constant FrameUniforms &uniforms [[buffer(1)]]
        ) {
            float3 light = normalize(uniforms.lightDirection.xyz);
            float diffuse = max(dot(normalize(in.normal), light), 0.0);
            float shadow = cloudShadow(in.worldPosition, light);
            float cloudShade = 1.0 - shadow * uniforms.timeOfDay.z;
            float lighting = 0.42 + diffuse * 0.58;
            lighting *= cloudShade;
            return float4(uniforms.baseColor.rgb * lighting, 1.0);
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

            float sunset = pow(max(1.0 - abs(sun.y), 0.0), 2.0);
            skyColor += float3(0.95, 0.34, 0.10) * sunset * pow(sunAmount, 6.0) * 0.75;
            skyColor += float3(1.0, 0.86, 0.60) * pow(sunAmount, 80.0) * 0.9;

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
              let vertexFunction = library.makeFunction(name: "mayhem_vertex"),
              let fragmentFunction = library.makeFunction(name: "mayhem_fragment"),
              let skyVertex = library.makeFunction(name: "sky_vertex"),
              let skyFragment = library.makeFunction(name: "sky_fragment") else { return nil }

        let sceneDescriptor = MTLRenderPipelineDescriptor()
        sceneDescriptor.vertexFunction = vertexFunction
        sceneDescriptor.fragmentFunction = fragmentFunction
        sceneDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        sceneDescriptor.depthAttachmentPixelFormat = .depth32Float

        let skyDescriptor = MTLRenderPipelineDescriptor()
        skyDescriptor.vertexFunction = skyVertex
        skyDescriptor.fragmentFunction = skyFragment
        skyDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat

        guard let scenePipeline = try? device.makeRenderPipelineState(descriptor: sceneDescriptor),
              let skyPipeline = try? device.makeRenderPipelineState(descriptor: skyDescriptor) else { return nil }

        self.scenePipeline = scenePipeline
        self.skyPipeline = skyPipeline

        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true

        let noDepthDescriptor = MTLDepthStencilDescriptor()
        noDepthDescriptor.depthCompareFunction = .always
        noDepthDescriptor.isDepthWriteEnabled = false

        guard let depthState = device.makeDepthStencilState(descriptor: depthDescriptor),
              let noDepthState = device.makeDepthStencilState(descriptor: noDepthDescriptor) else { return nil }

        self.depthState = depthState
        self.noDepthState = noDepthState

        let vertices = Self.makeCubeVertices()
        guard let vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<Vertex>.stride,
            options: .storageModeShared
        ) else { return nil }
        self.vertexBuffer = vertexBuffer

        super.init()

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

    private static func drawCube(
        encoder: MTLRenderCommandEncoder,
        model: simd_float4x4,
        color: SIMD3<Float>,
        projection: simd_float4x4,
        viewMatrix: simd_float4x4,
        lightDirection: SIMD3<Float>,
        timeOfDay: MayhemTimeOfDay
    ) {
        var uniforms = FrameUniforms(
            modelViewProjection: simd_mul(projection, simd_mul(viewMatrix, model)),
            model: model,
            lightDirection: SIMD4(lightDirection, 0),
            baseColor: SIMD4(color, 1),
            timeOfDay: SIMD4(timeOfDay.hour, timeOfDay.daylight, timeOfDay.cloudShadowStrength, 0)
        )
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<FrameUniforms>.stride, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 36)
    }

    private static func translation(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
        var matrix = matrix_identity_float4x4
        matrix.columns.3 = SIMD4(x, y, z, 1)
        return matrix
    }

    private static func scale(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4(x, 0, 0, 0),
            SIMD4(0, y, 0, 0),
            SIMD4(0, 0, z, 0),
            SIMD4(0, 0, 0, 1)
        ))
    }

    private static func makeCubeVertices() -> [Vertex] {
        let p: [SIMD3<Float>] = [
            SIMD3(-1,-1, 1), SIMD3( 1,-1, 1), SIMD3( 1, 1, 1), SIMD3(-1, 1, 1),
            SIMD3( 1,-1,-1), SIMD3(-1,-1,-1), SIMD3(-1, 1,-1), SIMD3( 1, 1,-1),
            SIMD3(-1, 1, 1), SIMD3( 1, 1, 1), SIMD3( 1, 1,-1), SIMD3(-1, 1,-1),
            SIMD3(-1,-1,-1), SIMD3( 1,-1,-1), SIMD3( 1,-1, 1), SIMD3(-1,-1, 1),
            SIMD3( 1,-1, 1), SIMD3( 1,-1,-1), SIMD3( 1, 1,-1), SIMD3( 1, 1, 1),
            SIMD3(-1,-1,-1), SIMD3(-1,-1, 1), SIMD3(-1, 1, 1), SIMD3(-1, 1,-1)
        ]
        let n: [SIMD3<Float>] = [
            SIMD3(0,0,1), SIMD3(0,0,-1), SIMD3(0,1,0),
            SIMD3(0,-1,0), SIMD3(1,0,0), SIMD3(-1,0,0)
        ]

        var vertices: [Vertex] = []
        for face in 0..<6 {
            let base = face * 4
            vertices.append(contentsOf: [
                Vertex(position: p[base], normal: n[face]),
                Vertex(position: p[base + 1], normal: n[face]),
                Vertex(position: p[base + 2], normal: n[face]),
                Vertex(position: p[base], normal: n[face]),
                Vertex(position: p[base + 2], normal: n[face]),
                Vertex(position: p[base + 3], normal: n[face])
            ])
        }
        return vertices
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
