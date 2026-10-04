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
        var effects: SIMD4<Float>
        var sunScreen: SIMD4<Float>
        var time: Float
    }

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let skyPipeline: MTLRenderPipelineState
    private let postPipeline: MTLRenderPipelineState
    private let noDepthState: MTLDepthStencilState
    private var hdrTexture: MTLTexture?

    private var viewportSize = SIMD2<Float>(1, 1)
    private var elapsedTime: Float = 0
    private var lastTimestamp: CFTimeInterval = CACurrentMediaTime()
    private var fpsAccumulator: Float = 0
    private var fpsFrameCount = 0
    weak var fpsLabel: UILabel?

    /// Modders can set this directly per track, e.g. 7.5 for 07:30.
    var timeOfDay = MayhemTimeOfDay(hour: 12)

    /// Camera state. Drag orbits; pinch changes field of view.
    var camera = MayhemCamera(
        position: SIMD3(0, 3.2, 8.5),
        target: SIMD3(0, 0.35, 0),
        up: SIMD3(0, 1, 0),
        fieldOfView: 58,
        nearPlane: 0.05,
        farPlane: 250
    )

    /// Lightweight screen-space effects designed to stay cheap on mobile GPUs.
    var effectsEnabled = true
    var vignetteStrength: Float = 0.22
    var filmGrainStrength: Float = 0.012
    var exposure: Float = 1.0

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
            float4 effects;
            float4 sunScreen;
            float time;
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

        float cloudDensity(float3 p, float time) {
            float3 wind = float3(time * 0.7, time * 0.10, -time * 0.35);
            float3 q = (p + wind) * float3(0.021, 0.030, 0.021);

            float base = noise3(q);
            float billows = noise3(q * 1.65 + float3(4.7, 1.9, 8.2));
            float detail = noise3(q * 4.5 + float3(12.0, 5.0, 2.0));

            float n = base * 0.58 + billows * 0.30 + detail * 0.12;

            float height = smoothstep(20.5, 24.5, p.y) *
                           (1.0 - smoothstep(40.5, 46.0, p.y));
            float verticalShape = 1.0 - abs((p.y - 31.0) / 11.0);
            verticalShape = smoothstep(0.0, 0.9, verticalShape);

            // Preserve wispy edges while keeping dense cores.
            return smoothstep(0.42, 0.64, n) * height * verticalShape;
        }

        vertex float4 sky_vertex(uint vertexID [[vertex_id]]) {
            const float2 positions[3] = {
                float2(-1, -1), float2(3, -1), float2(-1, 3)
            };
            return float4(positions[vertexID], 0, 1);
        }

        struct PostUniforms {
            float2 sunUV;
            float2 texel;
            float intensity;
        };

        vertex float4 post_vertex(uint vertexID [[vertex_id]]) {
            const float2 positions[3] = { float2(-1,-1), float2(3,-1), float2(-1,3) };
            return float4(positions[vertexID],0,1);
        }

        fragment float4 post_fragment(
            float4 position [[position]],
            texture2d<float> source [[texture(0)]],
            constant PostUniforms &u [[buffer(0)]]) {
            constexpr sampler s(address::clamp_to_edge, filter::linear);
            float2 uv = position.xy / float2(source.get_width(), source.get_height());
            float3 base = source.sample(s, uv).rgb;
            float3 bloom = float3(0.0);
            const float w[5] = {0.227027,0.194594,0.121621,0.054054,0.016216};
            for (int i=0;i<5;++i) {
                float2 dx=float2(u.texel.x*float(i),0);
                float2 dy=float2(0,u.texel.y*float(i));
                bloom += max(source.sample(s,uv+dx).rgb-1.0,0.0)*w[i];
                bloom += max(source.sample(s,uv-dx).rgb-1.0,0.0)*w[i];
                bloom += max(source.sample(s,uv+dy).rgb-1.0,0.0)*w[i];
                bloom += max(source.sample(s,uv-dy).rgb-1.0,0.0)*w[i];
            }
            float3 hdr = base + bloom * u.intensity;
            hdr = hdr / (1.0 + hdr);
            hdr = pow(max(hdr,0.0), float3(1.0/2.2));
            return float4(hdr,1.0);
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
            float3 horizon = float3(0.43, 0.63, 0.90);
            float3 zenith = float3(0.020, 0.055, 0.15);
            float up = max(ray.y, 0.0);
            float horizonFade = pow(1.0 - up, 0.72);
            float3 skyColor = mix(zenith, horizon, horizonFade);
            float horizonBand = 1.0 - smoothstep(0.0, 0.075, abs(ray.y));
            skyColor = mix(skyColor, horizon, horizonBand * 0.16);

            float daylight = uniforms.sky.x;
            float cloudAccum = 0.0;
            float transmittance = 1.0;
            if (ray.y > 0.025) {
                float cloudBase = 21.0;
                float cloudTop = 46.0;
                float entryT = max((cloudBase - uniforms.cameraPosition.y) / ray.y, 0.0);
                float exitT = (cloudTop - uniforms.cameraPosition.y) / ray.y;
                if (exitT > entryT) {
                    float span = min(exitT - entryT, 46.0);
                    float stepLength = span / 48.0;
                    float3 samplePoint = uniforms.cameraPosition.xyz + ray * (entryT + stepLength * 0.5);

                    for (int i = 0; i < 48; ++i) {
                        float density = cloudDensity(samplePoint, uniforms.time);

                        if (density > 0.008) {
                            // Beer-Lambert-like light attenuation through the volume.
                            float lightProbeA = cloudDensity(samplePoint + sun * 4.0, uniforms.time);
                            float lightProbeB = cloudDensity(samplePoint + sun * 10.0, uniforms.time);
                            float lightTransmittance = exp(-(lightProbeA * 1.7 + lightProbeB * 0.8) * 2.2);
                            float phase = 0.72 + 0.28 * pow(max(dot(ray, sun), 0.0), 3.0);
                            float lit = mix(0.38, 1.0, lightTransmittance) * phase;

                            float contribution = density * 0.24;
                            cloudAccum += contribution * transmittance * lit;
                            transmittance *= exp(-density * 0.38);
                        }

                        if (transmittance < 0.018) break;
                        samplePoint += ray * stepLength;
                    }
                }
            }

            float3 cloudColor = mix(float3(0.12, 0.14, 0.17), float3(1.0, 0.98, 0.92), daylight);
            skyColor = mix(skyColor, cloudColor, clamp(cloudAccum, 0.0, 0.92));

            float sunAlignment = max(dot(ray, sun), 0.0);
            float sunVisibility = 1.0 - clamp(cloudAccum * 2.0, 0.0, 1.0);
            float sunAngle = acos(clamp(dot(ray, sun), -1.0, 1.0));
            float sunDisk = 1.0 - smoothstep(0.0040, 0.0068, sunAngle);
            float corona = pow(sunAlignment, 96.0) * 0.85 * daylight;
            float halo = pow(sunAlignment, 24.0) * 0.24 * daylight;
            float broadGlow = pow(sunAlignment, 5.0) * 0.045 * daylight;

            float3 sunColor = float3(1.0, 0.93, 0.78);
            skyColor += sunColor * sunDisk * sunVisibility * 1.8;
            skyColor += sunColor * (corona + halo + broadGlow) * sunVisibility;

            // Screen-space sun glare / lens flare, tied to the projected sun position.
            if (daylight > 0.02 && sunVisibility > 0.02 && uniforms.sunScreen.w > 0.0) {
                float2 sunUV = uniforms.sunScreen.xy;
                float2 flareVector = uv - sunUV;
                float flareDistance = length(flareVector);
                float centerGlare = exp(-flareDistance * flareDistance / 0.035);
                float ring = exp(-pow((flareDistance - 0.13) / 0.045, 2.0));
                float2 axis = normalize(float2(0.7071, 0.7071));
                float streakCoord = dot(flareVector, axis);
                float crossCoord = dot(flareVector, float2(-axis.y, axis.x));
                float streak = exp(-abs(streakCoord) * 11.0) * exp(-abs(crossCoord) * 70.0);
                float glare = (centerGlare * 0.42 + ring * 0.12 + streak * 0.18)
                              * daylight * sunVisibility;
                skyColor += sunColor * glare;
            }

            // Cheap camera/screen effects. These are applied after sky/cloud lighting
            // so they affect the complete visible image without another full-resolution pass.
            if (uniforms.effects.x > 0.5) {
                float2 centered = uv - 0.5;
                float radial = dot(centered, centered) * 2.0;
                float vignette = 1.0 - smoothstep(0.28, 0.72, radial) * uniforms.effects.y;
                skyColor *= vignette;

                float grainSeed = dot(float3(position.xy, uniforms.effects.w),
                                      float3(12.9898, 78.233, 37.719));
                float grain = fract(sin(grainSeed) * 43758.5453) - 0.5;
                skyColor += grain * uniforms.effects.z;

                // Mild exposure roll-off keeps bright sky/sun detail from hard clipping.
                float exposureValue = max(uniforms.effects.w, 0.01);
                skyColor = 1.0 - exp(-skyColor * exposureValue);
            }

            return float4(clamp(skyColor, 0.0, 1.0), 1.0);
        }
        """

        guard let library = try? device.makeLibrary(source: shaderSource, options: nil),
              let skyVertex = library.makeFunction(name: "sky_vertex"),
              let skyFragment = library.makeFunction(name: "sky_fragment") else { return nil }

        let skyDescriptor = MTLRenderPipelineDescriptor()
        skyDescriptor.vertexFunction = skyVertex
        skyDescriptor.fragmentFunction = skyFragment
        skyDescriptor.colorAttachments[0].pixelFormat = .rgba16Float

        guard let skyPipeline = try? device.makeRenderPipelineState(descriptor: skyDescriptor) else { return nil }
        self.skyPipeline = skyPipeline

        let postDescriptor = MTLRenderPipelineDescriptor()
        postDescriptor.vertexFunction = library.makeFunction(name: "post_vertex")
        postDescriptor.fragmentFunction = library.makeFunction(name: "post_fragment")
        postDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        guard let postPipeline = try? device.makeRenderPipelineState(descriptor: postDescriptor) else { return nil }
        self.postPipeline = postPipeline
        self.hdrTexture = nil

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
        view.framebufferOnly = false
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
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

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

        let sunWorldPoint = camera.position + sun * 100.0
        let sunClip = simd_mul(simd_mul(projection, viewMatrix), SIMD4(sunWorldPoint, 1))
        let sunScreen: SIMD4<Float>
        if sunClip.w > 0.001 {
            let sunNDC = SIMD2(sunClip.x / sunClip.w, sunClip.y / sunClip.w)
            sunScreen = SIMD4(
                sunNDC.x * 0.5 + 0.5,
                1.0 - (sunNDC.y * 0.5 + 0.5),
                0,
                1
            )
        } else {
            sunScreen = SIMD4(-10, -10, 0, -1)
        }

        var skyUniforms = SkyUniforms(
            inverseViewProjection: inverseViewProjection,
            cameraPosition: SIMD4(camera.position, 1),
            sunDirection: SIMD4(sun, 0),
            sky: SIMD4(daylight, timeOfDay.skyBrightness, viewportSize.x, viewportSize.y),
            effects: SIMD4(
                effectsEnabled ? 1 : 0,
                vignetteStrength,
                filmGrainStrength,
                exposure
            ),
            sunScreen: sunScreen,
            time: elapsedTime
        )

        if hdrTexture == nil || hdrTexture?.width != Int(viewportSize.x) || hdrTexture?.height != Int(viewportSize.y) {
            let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: max(Int(viewportSize.x),1), height: max(Int(viewportSize.y),1), mipmapped: false)
            td.usage = [.renderTarget, .shaderRead]
            hdrTexture = device.makeTexture(descriptor: td)
        }
        guard let hdrTexture else { return }

        let hdrPass = MTLRenderPassDescriptor()
        hdrPass.colorAttachments[0].texture = hdrTexture
        hdrPass.colorAttachments[0].loadAction = .clear
        hdrPass.colorAttachments[0].storeAction = .store
        hdrPass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        guard let skyEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: hdrPass) else { return }
        skyEncoder.setRenderPipelineState(skyPipeline)
        skyEncoder.setDepthStencilState(noDepthState)
        skyEncoder.setFragmentBytes(&skyUniforms, length: MemoryLayout<SkyUniforms>.stride, index: 0)
        skyEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        skyEncoder.endEncoding()

        var postUniforms = PostUniformsCPU(sunUV: SIMD2(sunScreen.x, sunScreen.y), texel: SIMD2(1.0 / viewportSize.x, 1.0 / viewportSize.y), intensity: 1.6)
        guard let postEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        postEncoder.setRenderPipelineState(postPipeline)
        postEncoder.setFragmentTexture(hdrTexture, index: 0)
        postEncoder.setFragmentBytes(&postUniforms, length: MemoryLayout<PostUniformsCPU>.stride, index: 0)
        postEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        postEncoder.endEncoding()

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

    func zoomCamera(scale: Float) {
        let clampedScale = min(max(scale, 0.65), 1.55)
        let newFOV = camera.fieldOfView / clampedScale
        camera.fieldOfView = min(max(newFOV, 35), 85)
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
}
