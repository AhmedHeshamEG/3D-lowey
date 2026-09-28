import CoreImage
import Foundation
import LoweyCore
import Metal
import RealityKit
import UIKit

/// What the live stage post-processes this frame (set by the editor after every display update).
public struct StagePost: @unchecked Sendable {
    public var look: FrameLook
    /// The export frame inside the view, in points (overlays, captions, screen effects and film look live here).
    public var frameRect: CGRect
    public var overlays: [OverlayPlacement]
    public var caption: (page: CaptionPage, word: Int?, settings: CaptionSettings)?
    /// Skip depth effects (thermal pressure).
    public var reduced: Bool
    /// Overlay images, loaded on the main thread (the render thread only reads them).
    public var images: [String: CGImage]
    /// Stage size in points and the camera's depth range (for the render thread).
    public var viewSize: CGSize = .zero
    public var near: Float = 0.02
    public var far: Float = 3000

    public init(
        look: FrameLook,
        frameRect: CGRect,
        overlays: [OverlayPlacement] = [],
        caption: (page: CaptionPage, word: Int?, settings: CaptionSettings)? = nil,
        reduced: Bool = false,
        images: [String: CGImage] = [:]
    ) {
        self.look = look
        self.frameRect = frameRect
        self.overlays = overlays
        self.caption = caption
        self.reduced = reduced
        self.images = images
    }

    /// Nothing to draw: the stage skips the post-process pass entirely.
    public var isEmpty: Bool {
        look.post.isNeutral && !needsDepth && look.screen.isEmpty && overlays.isEmpty && caption == nil && look.glow == 0
    }

    var needsDepth: Bool {
        !reduced && (look.post.outline > 0 || (look.post.depthOfField && (look.lens?.aperture ?? 0) > 0))
    }
}

/// Runs the frame compositor inside ARView's post-process pass. RealityKit calls it on its RENDER thread, so it never
/// touches main-actor state: the editor hands it an immutable snapshot (`update`), guarded by a lock.
final class StagePostProcessor: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: StagePost?
    private let library: MTLLibrary?
    private let compositor = FrameCompositor()
    private var depthPipeline: MTLComputePipelineState?
    private var depthTexture: MTLTexture?
    private var overlayKey: OverlayKey?
    private var overlayImage: CIImage?

    private struct OverlayKey: Equatable {
        var overlays: [OverlayPlacement]
        var caption: String
        var word: Int?
        var size: CGSize
    }

    init(library: MTLLibrary?) {
        self.library = library
    }

    /// Main thread: the latest state to draw.
    func update(_ post: StagePost?) {
        lock.lock()
        snapshot = post
        lock.unlock()
    }

    /// Render thread.
    func process(_ context: ARView.PostProcessContext) {
        lock.lock()
        let current = snapshot
        lock.unlock()
        guard let post = current, !post.isEmpty else {
            Self.copy(context)
            return
        }
        render(context, post: post, viewSize: post.viewSize, near: post.near, far: post.far)
    }

    static func copy(_ context: ARView.PostProcessContext) {
        guard let blit = context.commandBuffer.makeBlitCommandEncoder() else { return }
        blit.copy(from: context.sourceColorTexture, to: context.targetColorTexture)
        blit.endEncoding()
    }

    private func render(_ context: ARView.PostProcessContext, post: StagePost, viewSize: CGSize, near: Float, far: Float) {
        let source = context.sourceColorTexture
        let width = CGFloat(source.width)
        let height = CGFloat(source.height)
        guard let raw = CIImage(mtlTexture: source, options: [.colorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any]) else { return }
        // Metal rows run top-down; flip so Core Image's y-up matches the picture (flipped back on output).
        let image = raw.transformed(by: CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -height))
        var depth: CIImage?
        if post.needsDepth, let texture = inverseDepth(context, near: near, far: far) {
            depth = CIImage(mtlTexture: texture, options: [.colorSpace: NSNull()])?
                .transformed(by: CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -CGFloat(texture.height)))
        }
        var picture = compositor.shot(image, depth: depth, look: post.look)
        // The frame region (y-up pixels).
        let scale = width / max(viewSize.width, 1)
        let rect = CGRect(x: post.frameRect.minX * scale, y: height - post.frameRect.maxY * scale,
                          width: post.frameRect.width * scale, height: post.frameRect.height * scale).integral
            .intersection(CGRect(x: 0, y: 0, width: width, height: height))
        if rect.width > 4, rect.height > 4 {
            let region = picture.cropped(to: rect)
            let overlays = overlayLayer(post, size: rect.size, pixelScale: scale)
            let finished = compositor.finish(region, look: post.look, overlays: overlays)
            picture = finished.composited(over: picture)
        }
        compositor.render(picture.cropped(to: CGRect(x: 0, y: 0, width: width, height: height)), to: context.targetColorTexture,
                          commandBuffer: context.commandBuffer)
    }

    /// Overlays are redrawn only when they change (cheap while nothing moves).
    private func overlayLayer(_ post: StagePost, size: CGSize, pixelScale: CGFloat) -> CIImage? {
        guard !post.overlays.isEmpty || post.caption != nil else { return nil }
        let key = OverlayKey(overlays: post.overlays, caption: post.caption?.page.text ?? "", word: post.caption?.word, size: size)
        if key == overlayKey { return overlayImage }
        overlayKey = key
        // Placements were computed in points for the frame rect; scale them to pixels.
        let placements = post.overlays.map { placement -> OverlayPlacement in
            var scaled = placement
            scaled.center = placement.center * Double(pixelScale)
            scaled.unit = placement.unit * Double(pixelScale)
            return scaled
        }
        overlayImage = compositor.overlayImage(size: size) { context in
            OverlayRenderer.draw(placements, in: context, size: size) { post.images[$0] }
            if let caption = post.caption {
                OverlayRenderer.drawCaption(caption.page, activeWord: caption.word, settings: caption.settings, in: context, size: size)
            }
        }
        return overlayImage
    }

    /// Converts RealityKit's depth buffer to v = 0.5 / distance (half resolution).
    private func inverseDepth(_ context: ARView.PostProcessContext, near: Float, far: Float) -> MTLTexture? {
        guard let depth = context.sourceDepthTexture as MTLTexture? else { return nil }
        if depthPipeline == nil, let library, let function = library.makeFunction(name: "loweyInverseDepth") {
            depthPipeline = try? context.device.makeComputePipelineState(function: function)
        }
        guard let pipeline = depthPipeline else { return nil }
        let width = max(depth.width / 2, 1)
        let height = max(depth.height / 2, 1)
        if depthTexture?.width != width || depthTexture?.height != height {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
            descriptor.usage = [.shaderRead, .shaderWrite]
            descriptor.storageMode = .private
            depthTexture = context.device.makeTexture(descriptor: descriptor)
        }
        guard let output = depthTexture, let encoder = context.commandBuffer.makeComputeCommandEncoder() else { return nil }
        var params = SIMD2<Float>(near, far)
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(depth, index: 0)
        encoder.setTexture(output, index: 1)
        encoder.setBytes(&params, length: MemoryLayout<SIMD2<Float>>.size, index: 0)
        let threads = MTLSize(width: 16, height: 16, depth: 1)
        encoder.dispatchThreadgroups(MTLSize(width: (width + 15) / 16, height: (height + 15) / 16, depth: 1), threadsPerThreadgroup: threads)
        encoder.endEncoding()
        return output
    }
}

extension StageView {
    /// Near/far planes the stage camera uses (for depth conversion).
    var depthRange: (near: Float, far: Float) {
        if lookThrough != nil { return (0.02, 3000) }
        return viewpoint.projection == .orthographic ? (1, 60000) : (0.02, 3000)
    }
}
