import CoreVideo
import Foundation
import Metal
import QuartzCore
import os

private struct VertexUniforms {
    var letterboxScale: SIMD2<Float>
    var zoom: Float
    var pad0: Float
    var zoomOffset: SIMD2<Float>
    var pad1: SIMD2<Float>
}

public final class MetalRenderer: @unchecked Sendable {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private var textureCache: CVMetalTextureCache?
    private weak var metalLayer: CAMetalLayer?
    private let logger = Logger(subsystem: "app.peekix.mac", category: "MetalRenderer")

    public var zoomScale: Float = 1.0
    public var zoomOffset: SIMD2<Float> = SIMD2<Float>(0, 0)
    public var isSuspended: Bool = false

    public var onVideoSizeChange: ((CGSize) -> Void)?
    private var lastVideoSize: CGSize = .zero

    // Mipmapped private textures used as the actual sampling source. CV-derived
    // textures aren't mipmapped, so without this we get bilinear-only minification
    // and noticeable aliasing when the window is shrunk well below the source size.
    private var yMipTexture: MTLTexture?
    private var cbcrMipTexture: MTLTexture?

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

    public func resetZoom() {
        zoomScale = 1.0
        zoomOffset = SIMD2<Float>(0, 0)
    }

    public func render(pixelBuffer: CVPixelBuffer) {
        guard !isSuspended else { return }
        guard let layer = metalLayer, let cache = textureCache else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0 else { return }

        let size = CGSize(width: width, height: height)
        if size != lastVideoSize {
            lastVideoSize = size
            onVideoSizeChange?(size)
        }

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

        ensureMipTextures(width: width, height: height)
        guard let yMip = yMipTexture, let cbcrMip = cbcrMipTexture else { return }

        guard let drawable = layer.nextDrawable() else { return }

        // The window is normally constrained to the video aspect ratio, but in
        // native fullscreen on a non-16:9 display the drawable matches the
        // screen and no longer matches the video. Compute a letterbox scale
        // here so the video keeps its source aspect in any drawable shape.
        var letterbox = SIMD2<Float>(1, 1)
        let drawableW = Float(layer.drawableSize.width)
        let drawableH = Float(layer.drawableSize.height)
        if drawableW > 0, drawableH > 0 {
            let videoAspect = Float(width) / Float(height)
            let drawableAspect = drawableW / drawableH
            if drawableAspect > videoAspect {
                letterbox.x = videoAspect / drawableAspect
            } else if drawableAspect < videoAspect {
                letterbox.y = drawableAspect / videoAspect
            }
        }
        var uniforms = VertexUniforms(
            letterboxScale: letterbox,
            zoom: max(zoomScale, 0.0001),
            pad0: 0,
            zoomOffset: zoomOffset,
            pad1: SIMD2<Float>(0, 0)
        )

        let passDesc = MTLRenderPassDescriptor()
        passDesc.colorAttachments[0].texture = drawable.texture
        passDesc.colorAttachments[0].loadAction = .clear
        passDesc.colorAttachments[0].storeAction = .store
        passDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        guard let cmdBuf = commandQueue.makeCommandBuffer() else { return }

        if let blit = cmdBuf.makeBlitCommandEncoder() {
            blit.copy(from: yTexture,
                      sourceSlice: 0, sourceLevel: 0,
                      sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                      sourceSize: MTLSize(width: width, height: height, depth: 1),
                      to: yMip,
                      destinationSlice: 0, destinationLevel: 0,
                      destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
            blit.copy(from: cbcrTexture,
                      sourceSlice: 0, sourceLevel: 0,
                      sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                      sourceSize: MTLSize(width: width / 2, height: height / 2, depth: 1),
                      to: cbcrMip,
                      destinationSlice: 0, destinationLevel: 0,
                      destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
            if yMip.mipmapLevelCount > 1 { blit.generateMipmaps(for: yMip) }
            if cbcrMip.mipmapLevelCount > 1 { blit.generateMipmaps(for: cbcrMip) }
            blit.endEncoding()
        }

        guard let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: passDesc) else {
            return
        }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<VertexUniforms>.size, index: 0)
        encoder.setFragmentTexture(yMip, index: 0)
        encoder.setFragmentTexture(cbcrMip, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        cmdBuf.present(drawable)
        cmdBuf.commit()

        CVMetalTextureCacheFlush(cache, 0)
    }

    private func ensureMipTextures(width: Int, height: Int) {
        if let y = yMipTexture, y.width == width, y.height == height,
           let c = cbcrMipTexture, c.width == width / 2, c.height == height / 2 {
            return
        }
        let yLevels = max(1, Int(floor(log2(Double(max(width, height))))) + 1)
        let cLevels = max(1, Int(floor(log2(Double(max(width / 2, height / 2))))) + 1)

        let yDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm, width: width, height: height, mipmapped: yLevels > 1)
        yDesc.mipmapLevelCount = yLevels
        yDesc.usage = [.shaderRead, .renderTarget]
        yDesc.storageMode = .private

        let cDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rg8Unorm, width: width / 2, height: height / 2, mipmapped: cLevels > 1)
        cDesc.mipmapLevelCount = cLevels
        cDesc.usage = [.shaderRead, .renderTarget]
        cDesc.storageMode = .private

        yMipTexture = device.makeTexture(descriptor: yDesc)
        cbcrMipTexture = device.makeTexture(descriptor: cDesc)
    }

    fileprivate static let shaderSource: String = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float2 texCoord;
    };

    struct VertexUniforms {
        float2 letterboxScale;
        float zoom;
        float pad0;
        float2 zoomOffset;
        float2 pad1;
    };

    vertex VertexOut vertexShader(uint vid [[vertex_id]],
                                  constant VertexUniforms &u [[buffer(0)]]) {
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
        out.position = float4(positions[vid] * u.letterboxScale, 0.0, 1.0);
        float2 tc = texCoords[vid];
        tc = u.zoomOffset + (tc - 0.5) / u.zoom + 0.5;
        out.texCoord = tc;
        return out;
    }

    fragment float4 fragmentShader(VertexOut in [[stage_in]],
                                   texture2d<float, access::sample> yTex [[texture(0)]],
                                   texture2d<float, access::sample> cbcrTex [[texture(1)]]) {
        constexpr sampler s(address::clamp_to_edge,
                            filter::linear,
                            mip_filter::linear,
                            max_anisotropy(4));
        float  y  = yTex.sample(s, in.texCoord).r - (16.0 / 255.0);
        float2 cc = cbcrTex.sample(s, in.texCoord).rg - float2(0.5, 0.5);
        float cb = cc.x;
        float cr = cc.y;
        float3 rgb;
        rgb.r = 1.164384 * y                       + 1.792741 * cr;
        rgb.g = 1.164384 * y - 0.213249 * cb       - 0.532909 * cr;
        rgb.b = 1.164384 * y + 2.112402 * cb;
        return float4(saturate(rgb), 1.0);
    }
    """
}
