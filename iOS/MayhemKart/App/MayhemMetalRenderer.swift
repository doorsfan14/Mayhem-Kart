import Foundation
import MetalKit
import simd
import QuartzCore

final class MayhemMetalRenderer: NSObject, MTKViewDelegate {
    private struct Vertex {
        var position: SIMD3<Float>
        var normal: SIMD3<Float>
    }

    private struct FrameUniforms {
        var modelViewProjection: simd_float4x4
        var model: simd_float4x4
        var lightDirection: SIMD4<Float>
        var baseColor: SIMD4<Float>
        var timeOfDay: SIMD4<Float>
    }

    private struct SkyUniforms {
        var inverseViewProjection: simd_float4x4
        var cameraPosition: SIMD4<Float>
        var sunDirection: SIMD4<Float>
        var sky: SIMD4<Float>
    }

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let scenePipeline: MTLRenderPipelineState
    private let skyPipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let noDepthState: MTLDepthStencilState
    private let vertexBuffer: MTLBuffer

    private var viewportSize = SIMD2<Float>(1, 1)
    private var elapsedTime: Float = 0
    private var lastTimestamp: CFTimeInterval = CACurrentMediaTime()

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

        float noise2(float2 p) {
            float2 i = floor(p);
            float2 f = fract(p);
            f = f * f * (3.0 - 2.0 * f);
            float a = hash21(i);
            float b = hash21(i + float2(1, 0));
            float c = hash21(i + float2(0, 1));
            float d = hash21(i + float2(1, 1));
            return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
        }

        float cloudField(float3 p) {
            float2 q = p.xz * 0.035 + float2(p.y * 0.018, p.y * -0.012);
            float n = noise2(q) * 0.55;
            n += noise2(q * 2.1) * 0.30;
            n += noise2(q * 4.7) * 0.15;
            float vertical = 1.0 - abs(p.y - 34.0) / 12.0;
            return clamp((n - 0.48) * 4.0, 0.0, 1.0) * clamp(vertical, 0.0, 1.0);
        }

        float cloudShadow(float3 worldPosition, float3 sunDirection) {
            float3 p = worldPosition + float3(0, 34, 0);
            float shadow = 0.0;
            for (int i = 0; i < 6; ++i) {
                p += sunDirection * (8.0 + float(i) * 7.0);
                shadow += cloudField(p);
            }
            return clamp(shadow / 6.0, 0.0, 1.0);
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
            float lighting = 0.16 + diffuse * 0.84;
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

            float sunset = pow(max(1.0 - abs(sun.y), 0.0), 2.0);
            skyColor += float3(0.95, 0.34, 0.10) * sunset * pow(sunAmount, 6.0) * 0.75;
            skyColor += float3(1.0, 0.86, 0.60) * pow(sunAmount, 80.0) * 0.9;

            float cloudAccum = 0.0;
            float transmittance = 1.0;
            float3 samplePoint = uniforms.cameraPosition.xyz + ray * 22.0;
            for (int i = 0; i < 18; ++i) {
                samplePoint += ray * 3.8;
                float density = cloudField(samplePoint);
                float lightProbe = cloudField(samplePoint + sun * 8.0);
                float lit = 0.45 + (1.0 - lightProbe) * 0.55;
                float contribution = density * 0.18;
                cloudAccum += contribution * transmittance * lit;
                transmittance *= 1.0 - density * 0.12;
            }

            float daylight = uniforms.sky.x;
            float3 cloudColor = mix(float3(0.12, 0.14, 0.17), float3(1.0, 0.98, 0.92), daylight);
            skyColor = mix(skyColor, cloudColor, clamp(cloudAccum, 0.0, 0.92));
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
        view.depthStencilPixelFormat = .depth32Float
        view.framebufferOnly = true
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

        encoder.setRenderPipelineState(scenePipeline)
        encoder.setDepthStencilState(depthState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

        let light = sun

        Self.drawCube(
            encoder: encoder,
            model: simd_mul(Self.translation(0, -0.16, 0), Self.scale(5.2, 0.18, 22)),
            color: SIMD3<Float>(0.055, 0.06, 0.07),
            projection: projection, viewMatrix: viewMatrix, lightDirection: light,
            timeOfDay: timeOfDay
        )

        for x in [-6.0, 6.0] {
            Self.drawCube(
                encoder: encoder,
                model: simd_mul(Self.translation(x, -0.22, 0), Self.scale(7.0, 0.12, 22)),
                color: SIMD3<Float>(0.18, 0.24, 0.18),
                projection: projection, viewMatrix: viewMatrix, lightDirection: light,
                timeOfDay: timeOfDay
            )
        }

        for x in [-5.55, 5.55] {
            Self.drawCube(
                encoder: encoder,
                model: simd_mul(Self.translation(x, 0.03, 0), Self.scale(0.28, 0.22, 22)),
                color: SIMD3<Float>(0.72, 0.72, 0.67),
                projection: projection, viewMatrix: viewMatrix, lightDirection: light,
                timeOfDay: timeOfDay
            )
        }

        for z in stride(from: -18.0, through: 18.0, by: 4.0) {
            Self.drawCube(
                encoder: encoder,
                model: simd_mul(Self.translation(0, 0.03, Float(z)), Self.scale(0.10, 0.03, 0.9)),
                color: SIMD3<Float>(0.86, 0.84, 0.72),
                projection: projection, viewMatrix: viewMatrix, lightDirection: light,
                timeOfDay: timeOfDay
            )
        }

        let kartZ = 2.4 + sin(elapsedTime * 3.0) * 0.035
        let kartSteer = sin(elapsedTime * 0.9) * 0.08
        let kartBase = simd_mul(Self.translation(kartSteer, 0.48, kartZ), Self.rotationY(kartSteer))

        Self.drawCube(
            encoder: encoder,
            model: simd_mul(kartBase, Self.scale(1.25, 0.38, 1.65)),
            color: SIMD3<Float>(0.08, 0.40, 0.78),
            projection: projection, viewMatrix: viewMatrix, lightDirection: light,
            timeOfDay: timeOfDay
        )

        Self.drawCube(
            encoder: encoder,
            model: simd_mul(kartBase, simd_mul(Self.translation(0, 0.48, -0.15), Self.scale(0.72, 0.42, 0.72))),
            color: SIMD3<Float>(0.13, 0.16, 0.20),
            projection: projection, viewMatrix: viewMatrix, lightDirection: light,
            timeOfDay: timeOfDay
        )

        for x in [-1.05, 1.05] {
            for z in [-1.0, 1.0] {
                Self.drawCube(
                    encoder: encoder,
                    model: simd_mul(kartBase, simd_mul(Self.translation(x, -0.20, z), Self.scale(0.28, 0.45, 0.38))),
                    color: SIMD3<Float>(0.018, 0.022, 0.026),
                    projection: projection, viewMatrix: viewMatrix, lightDirection: light,
                    timeOfDay: timeOfDay
                )
            }
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
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
