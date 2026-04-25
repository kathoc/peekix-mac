import CoreVideo
import Foundation
import Metal
import QuartzCore
import os

public final class MetalRenderer: @unchecked Sendable {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private var textureCache: CVMetalTextureCache?
    private weak var metalLayer: CAMetalLayer?
    private let logger = Logger(subsystem: "app.peekix.mac", category: "MetalRenderer")

    public init?() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            os_log(.error, "MTLCreateSystemDefaultDevice returned nil")
            return nil
        }
        guard let queue = device.makeCommandQueue() else { return nil }

        let logger = Logger(subsystem: "app.peekix.mac", category: "MetalRenderer")
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: MetalRenderer.shaderSource, options: nil)
        } catch {
            logger.error("makeLibrary failed: \(String(describing: error), privacy: .public)")
            return nil
        }

        guard let vertFn = library.makeFunction(name: "vertexShader"),
              let fragFn = library.makeFunction(name: "fragmentShader") else {
            logger.error("missing shader functions")
            return nil
        }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertFn
        desc.fragmentFunction = fragFn
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm

        let pipelineState: MTLRenderPipelineState
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            logger.error("makeRenderPipelineState failed: \(String(describing: error), privacy: .public)")
            return nil
        }

        var cache: CVMetalTextureCache?
        let cacheStatus = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        guard cacheStatus == kCVReturnSuccess, let cache else {
            logger.error("CVMetalTextureCacheCreate failed: \(cacheStatus)")
            return nil
        }

        self.device = device
        self.commandQueue = queue
        self.pipelineState = pipelineState
        self.textureCache = cache
    }

    public func attach(to layer: CAMetalLayer) {
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = true
        self.metalLayer = layer
    }

    public func render(pixelBuffer: CVPixelBuffer) {
        guard let layer = metalLayer, let cache = textureCache else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0 else { return }

        var yMetal: CVMetalTexture?
        var cbcrMetal: CVMetalTexture?
        let s1 = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, cache, pixelBuffer, nil,
            .r8Unorm, width, height, 0, &yMetal)
        let s2 = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, cache, pixelBuffer, nil,
            .rg8Unorm, width / 2, height / 2, 1, &cbcrMetal)
        guard s1 == kCVReturnSuccess, s2 == kCVReturnSuccess,
              let yMetal, let cbcrMetal,
              let yTexture = CVMetalTextureGetTexture(yMetal),
              let cbcrTexture = CVMetalTextureGetTexture(cbcrMetal) else {
            return
        }

        guard let drawable = layer.nextDrawable() else { return }

        let drawSize = layer.drawableSize
        var scale = SIMD2<Float>(1, 1)
        if drawSize.width > 0 && drawSize.height > 0 {
            let videoAspect = Float(width) / Float(height)
            let drawAspect = Float(drawSize.width / drawSize.height)
            if videoAspect > drawAspect {
                scale = SIMD2<Float>(1.0, drawAspect / videoAspect)
            } else {
                scale = SIMD2<Float>(videoAspect / drawAspect, 1.0)
            }
        }

        let passDesc = MTLRenderPassDescriptor()
        passDesc.colorAttachments[0].texture = drawable.texture
        passDesc.colorAttachments[0].loadAction = .clear
        passDesc.colorAttachments[0].storeAction = .store
        passDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        guard let cmdBuf = commandQueue.makeCommandBuffer(),
              let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: passDesc) else {
            return
        }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBytes(&scale, length: MemoryLayout<SIMD2<Float>>.size, index: 0)
        encoder.setFragmentTexture(yTexture, index: 0)
        encoder.setFragmentTexture(cbcrTexture, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        cmdBuf.present(drawable)
        cmdBuf.commit()

        CVMetalTextureCacheFlush(cache, 0)
    }

    // Shader source mirrors Shaders.metal in the same directory. The .metal
    // file is excluded from the build (no Metal toolchain dependency); we
    // compile the source at runtime via MTLDevice.makeLibrary(source:).
    fileprivate static let shaderSource: String = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float2 texCoord;
    };

    struct LetterboxUniforms {
        float2 scale;
    };

    vertex VertexOut vertexShader(uint vid [[vertex_id]],
                                  constant LetterboxUniforms &u [[buffer(0)]]) {
        const float2 positions[4] = {
            float2(-1.0, -1.0),
            float2( 1.0, -1.0),
            float2(-1.0,  1.0),
            float2( 1.0,  1.0)
        };
        const float2 texCoords[4] = {
            float2(0.0, 1.0),
            float2(1.0, 1.0),
            float2(0.0, 0.0),
            float2(1.0, 0.0)
        };
        VertexOut out;
        out.position = float4(positions[vid] * u.scale, 0.0, 1.0);
        out.texCoord = texCoords[vid];
        return out;
    }

    fragment float4 fragmentShader(VertexOut in [[stage_in]],
                                   texture2d<float, access::sample> yTex [[texture(0)]],
                                   texture2d<float, access::sample> cbcrTex [[texture(1)]]) {
        constexpr sampler s(address::clamp_to_edge, filter::linear);
        float y = yTex.sample(s, in.texCoord).r;
        float2 cbcr = cbcrTex.sample(s, in.texCoord).rg;
        float3 ycbcr = float3(y, cbcr.r, cbcr.g);
        const float3x3 m = float3x3(
            float3(1.164383561,  1.164383561,  1.164383561),
            float3(0.0,         -0.391762290,  2.017232142),
            float3(1.596026785, -0.812967647,  0.0)
        );
        const float3 bias = float3(-0.0729, 0.5316, -1.0856);
        float3 rgb = m * ycbcr + bias;
        return float4(rgb, 1.0);
    }
    """
}
