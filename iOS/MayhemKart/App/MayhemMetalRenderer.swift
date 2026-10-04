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
        var lightDirection: SIMD3<Float>
        var baseColor: SIMD3<Float>
        var padding: Float = 0
    }

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let vertexBuffer: MTLBuffer

    private var viewportSize = SIMD2<Float>(1, 1)
    private var elapsedTime: Float = 0
    private var lastTimestamp: CFTimeInterval = CACurrentMediaTime()

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
            float3 lightDirection;
            float3 baseColor;
            float padding;
        };

        struct VertexOut {
            float4 position [[position]];
            float3 normal;
        };

        vertex VertexOut mayhem_vertex(
            const device Vertex *vertices [[buffer(0)]],
            constant FrameUniforms &uniforms [[buffer(1)]],
            uint vertexID [[vertex_id]]
        ) {
            VertexOut out;
            out.position = uniforms.modelViewProjection * float4(vertices[vertexID].position, 1.0);
            out.normal = normalize((uniforms.model * float4(vertices[vertexID].normal, 0.0)).xyz);
            return out;
        }

        fragment float4 mayhem_fragment(
            VertexOut in [[stage_in]],
            constant FrameUniforms &uniforms [[buffer(1)]]
        ) {
            float3 light = normalize(uniforms.lightDirection);
            float diffuse = max(dot(normalize(in.normal), light), 0.0);
            float lighting = 0.20 + diffuse * 0.80;
            return float4(uniforms.baseColor * lighting, 1.0);
        }
        """

        guard let library = try? device.makeLibrary(source: shaderSource, options: nil),
              let vertexFunction = library.makeFunction(name: "mayhem_vertex"),
              let fragmentFunction = library.makeFunction(name: "mayhem_fragment") else { return nil }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        descriptor.depthAttachmentPixelFormat = .depth32Float

        guard let pipelineState = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        self.pipelineState = pipelineState

        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true

        guard let depthState = device.makeDepthStencilState(descriptor: depthDescriptor) else { return nil }
        self.depthState = depthState

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

        encoder.setRenderPipelineState(pipelineState)
        encoder.setDepthStencilState(depthState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

        let light = SIMD3<Float>(-0.45, 1.0, 0.55)

        Self.drawCube(
            encoder: encoder,
            model: simd_mul(Self.translation(0, -0.16, 0), Self.scale(5.2, 0.18, 22)),
            color: SIMD3<Float>(0.055, 0.06, 0.07),
            projection: projection, viewMatrix: viewMatrix, lightDirection: light
        )

        for x in [-6.0, 6.0] {
            Self.drawCube(
                encoder: encoder,
                model: simd_mul(Self.translation(x, -0.22, 0), Self.scale(7.0, 0.12, 22)),
                color: SIMD3<Float>(0.18, 0.24, 0.18),
                projection: projection, viewMatrix: viewMatrix, lightDirection: light
            )
        }

        for x in [-5.55, 5.55] {
            Self.drawCube(
                encoder: encoder,
                model: simd_mul(Self.translation(x, 0.03, 0), Self.scale(0.28, 0.22, 22)),
                color: SIMD3<Float>(0.72, 0.72, 0.67),
                projection: projection, viewMatrix: viewMatrix, lightDirection: light
            )
        }

        for z in stride(from: -18.0, through: 18.0, by: 4.0) {
            Self.drawCube(
                encoder: encoder,
                model: simd_mul(Self.translation(0, 0.03, Float(z)), Self.scale(0.10, 0.03, 0.9)),
                color: SIMD3<Float>(0.86, 0.84, 0.72),
                projection: projection, viewMatrix: viewMatrix, lightDirection: light
            )
        }

        let kartZ = 2.4 + sin(elapsedTime * 3.0) * 0.035
        let kartSteer = sin(elapsedTime * 0.9) * 0.08
        let kartBase = simd_mul(Self.translation(kartSteer, 0.48, kartZ), Self.rotationY(kartSteer))

        Self.drawCube(
            encoder: encoder,
            model: simd_mul(kartBase, Self.scale(1.25, 0.38, 1.65)),
            color: SIMD3<Float>(0.08, 0.40, 0.78),
            projection: projection, viewMatrix: viewMatrix, lightDirection: light
        )

        Self.drawCube(
            encoder: encoder,
            model: simd_mul(kartBase, simd_mul(Self.translation(0, 0.48, -0.15), Self.scale(0.72, 0.42, 0.72))),
            color: SIMD3<Float>(0.13, 0.16, 0.20),
            projection: projection, viewMatrix: viewMatrix, lightDirection: light
        )

        for x in [-1.05, 1.05] {
            for z in [-1.0, 1.0] {
                Self.drawCube(
                    encoder: encoder,
                    model: simd_mul(kartBase, simd_mul(Self.translation(x, -0.20, z), Self.scale(0.28, 0.45, 0.38))),
                    color: SIMD3<Float>(0.018, 0.022, 0.026),
                    projection: projection, viewMatrix: viewMatrix, lightDirection: light
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
        lightDirection: SIMD3<Float>
    ) {
        var uniforms = FrameUniforms(
            modelViewProjection: simd_mul(projection, simd_mul(viewMatrix, model)),
            model: model,
            lightDirection: lightDirection,
            baseColor: color
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
