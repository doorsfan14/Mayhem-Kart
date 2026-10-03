import Foundation
import MetalKit
import simd

final class MayhemMetalRenderer: NSObject, MTKViewDelegate {
    private struct Vertex {
        var position: SIMD3<Float>
        var normal: SIMD3<Float>
    }

    private struct FrameUniforms {
        var modelViewProjection: simd_float4x4
        var model: simd_float4x4
        var lightDirection: SIMD3<Float>
        var padding: Float = 0
    }

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let vertexBuffer: MTLBuffer

    private var viewportSize = SIMD2<Float>(1, 1)
    private var elapsedTime: Float = 0

    var camera = MayhemCamera()

    init?(view: MTKView) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            return nil
        }

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
            float4 worldPosition = uniforms.model * float4(vertices[vertexID].position, 1.0);
            out.position = uniforms.modelViewProjection * float4(vertices[vertexID].position, 1.0);
            out.normal = normalize((uniforms.model * float4(vertices[vertexID].normal, 0.0)).xyz);
            return out;
        }

        fragment float4 mayhem_fragment(VertexOut in [[stage_in]]) {
            float3 light = normalize(float3(-0.4, 1.0, 0.6));
            float diffuse = max(dot(normalize(in.normal), light), 0.0);
            float lighting = 0.22 + diffuse * 0.78;
            return float4(float3(0.22, 0.62, 0.92) * lighting, 1.0);
        }
        """

        guard let library = try? device.makeLibrary(source: shaderSource, options: nil),
              let vertexFunction = library.makeFunction(name: "mayhem_vertex"),
              let fragmentFunction = library.makeFunction(name: "mayhem_fragment") else {
            return nil
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        descriptor.depthAttachmentPixelFormat = .depth32Float

        guard let pipelineState = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            return nil
        }
        self.pipelineState = pipelineState

        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true

        guard let depthState = device.makeDepthStencilState(descriptor: depthDescriptor) else {
            return nil
        }
        self.depthState = depthState

        let vertices = Self.makeCubeVertices()
        guard let vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<Vertex>.stride,
            options: .storageModeShared
        ) else {
            return nil
        }
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
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        let deltaTime = Float(1.0 / Double(max(view.preferredFramesPerSecond, 1)))
        elapsedTime += deltaTime

        let aspect = viewportSize.x / max(viewportSize.y, 1)
        let projection = Self.perspective(
            fovY: camera.fieldOfView * .pi / 180,
            aspect: aspect,
            near: camera.nearPlane,
            far: camera.farPlane
        )
        let viewMatrix = Self.lookAt(
            eye: camera.position,
            target: camera.target,
            up: camera.up
        )

        var model = matrix_identity_float4x4
        model = simd_mul(model, Self.rotationY(elapsedTime * 0.7))
        model = simd_mul(model, Self.rotationX(sin(elapsedTime * 0.5) * 0.15))

        var uniforms = FrameUniforms(
            modelViewProjection: simd_mul(projection, simd_mul(viewMatrix, model)),
            model: model,
            lightDirection: SIMD3(-0.4, 1.0, 0.6)
        )

        encoder.setRenderPipelineState(pipelineState)
        encoder.setDepthStencilState(depthState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<FrameUniforms>.stride, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 36)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
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

    private static func rotationX(_ angle: Float) -> simd_float4x4 {
        let c = cos(angle)
        let s = sin(angle)
        return simd_float4x4(columns: (
            SIMD4(1, 0, 0, 0),
            SIMD4(0, c, s, 0),
            SIMD4(0, -s, c, 0),
            SIMD4(0, 0, 0, 1)
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
