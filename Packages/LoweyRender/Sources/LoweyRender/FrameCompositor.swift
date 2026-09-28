import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import Foundation
import LoweyCore
import Metal
import UIKit

/// Everything the compositor needs for one frame besides the pictures.
public struct FrameLook: Sendable {
    public var post: PostSettings
    /// The shot camera's lens (depth of field when its aperture > 0).
    public var lens: CameraLens?
    public var screen: ScreenState
    /// Frame number (grain and film texture change per frame, deterministically).
    public var frame: Int

    public init(post: PostSettings, lens: CameraLens? = nil, screen: ScreenState = ScreenState(), frame: Int = 0) {
        self.post = post
        self.lens = lens
        self.screen = screen
        self.frame = frame
    }
}

/// Post-processing, transitions, screen effects and overlays, with Core Image. The live stage and the exporter
/// run the same stages in the same order, so the preview is the export:
///
///  1. shot:        lens blur → ink outlines → bloom → grade → chromatic aberration → retro
///  2. transition:  two finished shots blended (fade, dip, wipe, zoom through)
///  3. screen:      shake → zoom blur → glitch → speed lines → flash
///  4. film:        texture (paper, collage, old film) → vignette → grain
///  5. overlays:    titles, labels, arrows, the X… and captions, crisp on top
public final class FrameCompositor: @unchecked Sendable {
    public let context: CIContext
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    private var paperCache: [String: CIImage] = [:]

    public init(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        if let device {
            context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false, .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
        } else {
            context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
        }
    }

    // MARK: 1. Shot

    /// Post-processes one rendered shot. `depth` holds v = 0.5 / distance in its red channel (any size).
    public func shot(_ image: CIImage, depth: CIImage?, look: FrameLook) -> CIImage {
        let post = look.post
        let extent = image.extent
        let height = extent.height
        var result = image
        let scaledDepth = depth.map { fit($0, to: extent) }
        if post.depthOfField, let lens = look.lens, lens.aperture > 0, let scaledDepth {
            result = lensBlur(result, depth: scaledDepth, lens: lens, height: height)
        }
        if post.outline > 0, let scaledDepth {
            result = outline(result, depth: scaledDepth, strength: post.outline, color: post.outlineColor, height: height)
        }
        if post.bloom > 0 {
            let bloom = CIFilter.bloom()
            bloom.inputImage = result.clampedToExtent()
            bloom.radius = Float(height * 0.025 * (0.5 + post.bloom))
            bloom.intensity = Float(post.bloom * 1.1)
            result = bloom.outputImage?.cropped(to: extent) ?? result
        }
        if post.exposure != 0 {
            let exposure = CIFilter.exposureAdjust()
            exposure.inputImage = result
            exposure.ev = Float(post.exposure)
            result = exposure.outputImage ?? result
        }
        if post.contrast != 0 || post.saturation != 0 {
            let controls = CIFilter.colorControls()
            controls.inputImage = result
            controls.contrast = Float(1 + post.contrast * 0.5)
            controls.saturation = Float(max(1 + post.saturation, 0))
            controls.brightness = 0
            result = controls.outputImage ?? result
        }
        if post.temperature != 0 {
            let temperature = CIFilter.temperatureAndTint()
            temperature.inputImage = result
            temperature.neutral = CIVector(x: 6500, y: 0)
            temperature.targetNeutral = CIVector(x: CGFloat(6500 + post.temperature * 2000), y: 0)
            result = temperature.outputImage ?? result
        }
        if post.chromaticAberration > 0 {
            result = chromatic(result, amount: post.chromaticAberration)
        }
        if post.retro > 0 {
            let pixellate = CIFilter.pixellate()
            pixellate.inputImage = result.clampedToExtent()
            pixellate.scale = Float(max(2, height / 540 * (2 + post.retro * 6)))
            pixellate.center = CGPoint(x: extent.midX, y: extent.midY)
            let posterize = CIFilter.colorPosterize()
            posterize.inputImage = pixellate.outputImage?.cropped(to: extent)
            posterize.levels = Float(max(4, 24 - post.retro * 18))
            result = posterize.outputImage ?? result
        }
        return result.cropped(to: extent)
    }

    /// Circle of confusion in pixels per unit of |1/focus − 1/distance| (1/m): thin lens, 35 mm-equivalent.
    public static func cocScale(lens: CameraLens, frameHeight: Double) -> Double {
        let focal = lens.focalLength / 1000
        let fNumber = max(lens.aperture, 0.7)
        return focal * focal / fNumber * frameHeight / 0.024
    }

    private func lensBlur(_ image: CIImage, depth: CIImage, lens: CameraLens, height: CGFloat) -> CIImage {
        let maxRadius = Double(height) * 0.03
        let scale = Self.cocScale(lens: lens, frameHeight: Double(height))
        // v = 0.5/d, so 1/d = 2v: mask = |1/focus − 2v| × scale / maxRadius, both signs, then max.
        let vFocus = 1 / max(lens.focusDistance, 0.05)
        let k = 2 * scale / maxRadius
        let positive = colorMatrix(depth, gain: k, bias: -vFocus * scale / maxRadius)
        let negative = colorMatrix(depth, gain: -k, bias: vFocus * scale / maxRadius)
        let maximum = CIFilter.maximumCompositing()
        maximum.inputImage = positive
        maximum.backgroundImage = negative
        let clamp = CIFilter.colorClamp()
        clamp.inputImage = maximum.outputImage
        clamp.minComponents = CIVector(x: 0, y: 0, z: 0, w: 1)
        clamp.maxComponents = CIVector(x: 1, y: 1, z: 1, w: 1)
        guard let mask = clamp.outputImage else { return image }
        let blur = CIFilter.maskedVariableBlur()
        blur.inputImage = image.clampedToExtent()
        blur.mask = mask
        blur.radius = Float(maxRadius)
        return blur.outputImage?.cropped(to: image.extent) ?? image
    }

    /// Grey image: every channel = r × gain + bias (alpha 1).
    private func colorMatrix(_ image: CIImage, gain: Double, bias: Double) -> CIImage {
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = image
        let row = CIVector(x: CGFloat(gain), y: 0, z: 0, w: 0)
        matrix.rVector = row
        matrix.gVector = row
        matrix.bVector = row
        matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        matrix.biasVector = CIVector(x: CGFloat(bias), y: CGFloat(bias), z: CGFloat(bias), w: 1)
        return matrix.outputImage ?? image
    }

    private func outline(_ image: CIImage, depth: CIImage, strength: Double, color: RGBA, height: CGFloat) -> CIImage {
        // Depth discontinuities in 1/distance: strong at silhouettes, quiet across surfaces.
        let edges = CIFilter.edges()
        edges.inputImage = depth
        edges.intensity = Float(6 + strength * 30)
        let thicken = CIFilter.morphologyMaximum()
        thicken.inputImage = edges.outputImage
        thicken.radius = Float(max(height / 1080 * (0.6 + strength * 1.6), 0.5))
        guard let lines = thicken.outputImage.map({ colorMatrix($0, gain: 1.6, bias: -0.12) }) else { return image }
        let blend = CIFilter.blendWithMask()
        blend.inputImage = CIImage(color: CIColor(red: color.r, green: color.g, blue: color.b)).cropped(to: image.extent)
        blend.backgroundImage = image
        blend.maskImage = lines.cropped(to: image.extent)
        return blend.outputImage ?? image
    }

    private func chromatic(_ image: CIImage, amount: Double) -> CIImage {
        let extent = image.extent
        let center = CGPoint(x: extent.midX, y: extent.midY)
        func channel(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, scale: CGFloat) -> CIImage {
            let matrix = CIFilter.colorMatrix()
            matrix.inputImage = image.clampedToExtent()
            matrix.rVector = CIVector(x: r, y: 0, z: 0, w: 0)
            matrix.gVector = CIVector(x: 0, y: g, z: 0, w: 0)
            matrix.bVector = CIVector(x: 0, y: 0, z: b, w: 0)
            matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
            let transform = CGAffineTransform(translationX: center.x, y: center.y).scaledBy(x: scale, y: scale)
                .translatedBy(x: -center.x, y: -center.y)
            return (matrix.outputImage ?? image).transformed(by: transform)
        }
        let spread = CGFloat(amount) * 0.008
        let red = channel(1, 0, 0, scale: 1 + spread)
        let green = channel(0, 1, 0, scale: 1)
        let blue = channel(0, 0, 1, scale: 1 - spread)
        // Each channel image is zero in the other channels, so a per-channel maximum puts them back together
        // (the addition-compositing version rendered black in CI).
        let first = CIFilter.maximumCompositing()
        first.inputImage = red
        first.backgroundImage = green
        let second = CIFilter.maximumCompositing()
        second.inputImage = blue
        second.backgroundImage = first.outputImage
        return second.outputImage?.cropped(to: extent) ?? image
    }

    // MARK: 2. Transition

    public func transition(from: CIImage, to: CIImage, kind: TransitionSpec.Kind, progress: Double) -> CIImage {
        let extent = from.extent
        let p = min(max(progress, 0), 1)
        let eased = Easing.easeInOut.apply(p)
        switch kind {
        case .cut:
            return p < 0.5 ? from : to
        case .fade:
            let dissolve = CIFilter.dissolveTransition()
            dissolve.inputImage = from
            dissolve.targetImage = to
            dissolve.time = Float(eased)
            return dissolve.outputImage?.cropped(to: extent) ?? to
        case .dipToBlack:
            let image = p < 0.5 ? from : to
            let darkness = p < 0.5 ? p * 2 : (1 - p) * 2
            let black = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: CGFloat(Easing.easeInOut.apply(darkness)))).cropped(to: extent)
            return black.composited(over: image)
        case .wipe:
            let edge = extent.minX + extent.width * CGFloat(eased)
            let soft = extent.width * 0.02
            let gradient = CIFilter.linearGradient()
            gradient.point0 = CGPoint(x: edge - soft, y: extent.midY)
            gradient.point1 = CGPoint(x: edge + soft, y: extent.midY)
            gradient.color0 = CIColor.white
            gradient.color1 = CIColor.black
            let blend = CIFilter.blendWithMask()
            blend.inputImage = to
            blend.backgroundImage = from
            blend.maskImage = gradient.outputImage?.cropped(to: extent)
            return blend.outputImage?.cropped(to: extent) ?? to
        case .zoomThrough:
            let center = CGPoint(x: extent.midX, y: extent.midY)
            func zoom(_ image: CIImage, _ scale: CGFloat, blur: Double) -> CIImage {
                let transform = CGAffineTransform(translationX: center.x, y: center.y).scaledBy(x: scale, y: scale)
                    .translatedBy(x: -center.x, y: -center.y)
                let zoomBlur = CIFilter.zoomBlur()
                zoomBlur.inputImage = image.clampedToExtent().transformed(by: transform)
                zoomBlur.center = center
                zoomBlur.amount = Float(blur)
                return zoomBlur.outputImage?.cropped(to: extent) ?? image
            }
            let outgoing = zoom(from, 1 + CGFloat(eased) * 1.5, blur: Double(extent.height) * 0.06 * sin(p * .pi))
            let incoming = zoom(to, 0.6 + 0.4 * CGFloat(eased), blur: Double(extent.height) * 0.06 * sin(p * .pi))
            let dissolve = CIFilter.dissolveTransition()
            dissolve.inputImage = outgoing
            dissolve.targetImage = incoming
            dissolve.time = Float(min(max((p - 0.35) / 0.3, 0), 1))
            return dissolve.outputImage?.cropped(to: extent) ?? to
        }
    }

    // MARK: 3. Screen effects

    public func screen(_ image: CIImage, state: ScreenState) -> CIImage {
        guard !state.isEmpty else { return image }
        let extent = image.extent
        let center = CGPoint(x: extent.midX, y: extent.midY)
        var result = image
        if state.shake != .zero {
            let transform = CGAffineTransform(translationX: center.x + CGFloat(state.shake.x) * extent.height,
                                              y: center.y + CGFloat(state.shake.y) * extent.height)
                .rotated(by: CGFloat(state.shake.z))
                .scaledBy(x: 1.04, y: 1.04)
                .translatedBy(x: -center.x, y: -center.y)
            result = result.clampedToExtent().transformed(by: transform).cropped(to: extent)
        }
        if state.zoomBlur > 0 {
            let zoom = CIFilter.zoomBlur()
            zoom.inputImage = result.clampedToExtent()
            zoom.center = center
            zoom.amount = Float(state.zoomBlur * Double(extent.height) * 0.05)
            result = zoom.outputImage?.cropped(to: extent) ?? result
        }
        if state.glitch > 0 {
            result = glitch(result, amount: state.glitch, seed: state.glitchSeed)
        }
        if state.speedLines > 0, let lines = speedLines(size: extent.size, amount: state.speedLines, seed: state.lineSeed) {
            result = lines.transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY)).composited(over: result)
        }
        if state.flash > 0 {
            let color = state.flashColor
            let flash = CIImage(color: CIColor(red: color.r, green: color.g, blue: color.b, alpha: CGFloat(min(state.flash, 1)))).cropped(to: extent)
            result = flash.composited(over: result)
        }
        return result.cropped(to: extent)
    }

    private func glitch(_ image: CIImage, amount: Double, seed: UInt64) -> CIImage {
        let extent = image.extent
        var result = chromatic(image, amount: amount * 3)
        var random = SeededRandom(seed: seed)
        for _ in 0 ..< 7 {
            let height = extent.height * CGFloat(random.range(0.02, 0.12))
            let y = extent.minY + extent.height * CGFloat(random.range(0, 1))
            let shift = extent.width * CGFloat(random.range(-0.08, 0.08) * amount)
            let strip = image.clampedToExtent().transformed(by: CGAffineTransform(translationX: shift, y: 0))
                .cropped(to: CGRect(x: extent.minX, y: y, width: extent.width, height: height))
            result = strip.composited(over: result)
        }
        return result.cropped(to: extent)
    }

    private func speedLines(size: CGSize, amount: Double, seed: UInt64) -> CIImage? {
        let width = Int(size.width / 2)
        let height = Int(size.height / 2)
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        var random = SeededRandom(seed: seed)
        let center = CGPoint(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
        let reach = hypot(CGFloat(width), CGFloat(height)) / 2
        for _ in 0 ..< Int(60 * amount) {
            let angle = CGFloat(random.range(0, 2 * .pi))
            let inner = reach * CGFloat(random.range(0.45, 0.8))
            let thickness = CGFloat(random.range(0.004, 0.012)) * reach * CGFloat(amount)
            let direction = CGPoint(x: cos(angle), y: sin(angle))
            let normal = CGPoint(x: -direction.y, y: direction.x)
            context.setFillColor(UIColor.white.withAlphaComponent(CGFloat(random.range(0.4, 0.85))).cgColor)
            context.move(to: CGPoint(x: center.x + direction.x * inner, y: center.y + direction.y * inner))
            context.addLine(to: CGPoint(x: center.x + direction.x * reach * 1.1 + normal.x * thickness,
                                        y: center.y + direction.y * reach * 1.1 + normal.y * thickness))
            context.addLine(to: CGPoint(x: center.x + direction.x * reach * 1.1 - normal.x * thickness,
                                        y: center.y + direction.y * reach * 1.1 - normal.y * thickness))
            context.closePath()
            context.fillPath()
        }
        guard let image = context.makeImage() else { return nil }
        return CIImage(cgImage: image).transformed(by: CGAffineTransform(scaleX: 2, y: 2))
    }

    // MARK: 4. Film

    public func film(_ image: CIImage, post: PostSettings, frame: Int) -> CIImage {
        let extent = image.extent
        var result = image
        if post.texture != .none, post.textureStrength > 0 {
            result = texture(result, kind: post.texture, strength: post.textureStrength, frame: frame)
        }
        if post.vignette > 0 {
            let vignette = CIFilter.vignette()
            vignette.inputImage = result
            vignette.intensity = Float(post.vignette * 1.6)
            vignette.radius = Float(1.2)
            result = vignette.outputImage?.cropped(to: extent) ?? result
        }
        if post.grain > 0 {
            result = grain(result, amount: post.grain, frame: frame)
        }
        return result
    }

    private func noise(_ extent: CGRect, frame: Int, scale: CGFloat = 1) -> CIImage {
        let offsetX = CGFloat((frame &* 173) % 997)
        let offsetY = CGFloat((frame &* 389) % 991)
        // CIRandomGenerator's alpha is random too; Core Image un-premultiplies before colour matrices, so a tiny alpha
        // would blow a pixel up to pure white. Opaque noise only.
        let random = (CIFilter.randomGenerator().outputImage ?? CIImage(color: .gray)).settingAlphaOne(in: .infinite)
        return random.transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY).scaledBy(x: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY)).cropped(to: extent)
    }

    private func grain(_ image: CIImage, amount: Double, frame: Int) -> CIImage {
        let extent = image.extent
        let grainScale = max(extent.height / 1080, 1)
        // Soft-light a mid-grey noise: brightens and darkens without shifting the average.
        let gray = colorMatrix(noise(extent, frame: frame, scale: grainScale), gain: amount * 0.55, bias: 0.5 - amount * 0.275)
        let blend = CIFilter.softLightBlendMode()
        blend.inputImage = gray
        blend.backgroundImage = image
        return blend.outputImage?.cropped(to: extent) ?? image
    }

    private func texture(_ image: CIImage, kind: PostSettings.Texture, strength: Double, frame: Int) -> CIImage {
        let extent = image.extent
        var result = image
        // Paper: blotchy fibres (blurred noise at two scales), multiplied in. Static for paper/collage, flickering for film.
        let paperFrame = kind == .film ? frame : 7
        let blotches = CIFilter.gaussianBlur()
        blotches.inputImage = noise(extent, frame: paperFrame, scale: max(extent.height / 180, 1)).clampedToExtent()
        blotches.radius = Float(extent.height / 90)
        let fibres = noise(extent, frame: paperFrame + 1, scale: max(extent.height / 900, 1))
        let paperTone = colorMatrix(blotches.outputImage?.cropped(to: extent) ?? fibres, gain: 0.35 * strength, bias: 1 - 0.3 * strength)
        let fibreTone = colorMatrix(fibres, gain: 0.12 * strength, bias: 1 - 0.1 * strength)
        let multiply = CIFilter.multiplyCompositing()
        multiply.inputImage = paperTone
        multiply.backgroundImage = fibreTone
        let paper = multiply.outputImage ?? paperTone
        let tint = CIFilter.colorMatrix()
        tint.inputImage = paper
        // Warm the paper slightly (cream, not grey).
        tint.rVector = CIVector(x: 1, y: 0, z: 0, w: 0)
        tint.gVector = CIVector(x: 0, y: 0.97, z: 0, w: 0)
        tint.bVector = CIVector(x: 0, y: 0, z: 0.9, w: 0)
        tint.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        let onPaper = CIFilter.multiplyBlendMode()
        onPaper.inputImage = tint.outputImage?.cropped(to: extent)
        onPaper.backgroundImage = result
        result = onPaper.outputImage?.cropped(to: extent) ?? result
        if kind == .collage {
            // Cut-out look: fewer colours, harder light.
            let posterize = CIFilter.colorPosterize()
            posterize.inputImage = result
            posterize.levels = Float(max(5, 12 - strength * 6))
            result = posterize.outputImage ?? result
        }
        if kind == .film {
            // Flicker and a couple of scratches per frame.
            var random = SeededRandom(seed: UInt64(frame) &* 2_246_822_519 &+ 3)
            let exposure = CIFilter.exposureAdjust()
            exposure.inputImage = result
            exposure.ev = Float(random.range(-0.12, 0.12) * strength)
            result = exposure.outputImage ?? result
            for _ in 0 ..< 2 where random.range(0, 1) < 0.6 {
                let x = extent.minX + extent.width * CGFloat(random.range(0, 1))
                let scratch = CIImage(color: CIColor(red: 1, green: 1, blue: 0.95, alpha: CGFloat(0.35 * strength)))
                    .cropped(to: CGRect(x: x, y: extent.minY, width: max(extent.width / 900, 1), height: extent.height))
                result = scratch.composited(over: result)
            }
        }
        return result
    }

    // MARK: Helpers

    /// Scales `image` to fill `extent` exactly (depth rendered at a lower resolution).
    private func fit(_ image: CIImage, to extent: CGRect) -> CIImage {
        let source = image.extent
        guard source.width > 0, source.height > 0 else { return image }
        let transform = CGAffineTransform(translationX: extent.minX, y: extent.minY)
            .scaledBy(x: extent.width / source.width, y: extent.height / source.height)
            .translatedBy(x: -source.minX, y: -source.minY)
        return image.transformed(by: transform).cropped(to: extent)
    }

    /// A CGImage of overlays and captions (y-down drawing) as a CIImage over `extent`.
    public func overlayImage(size: CGSize, draw: (CGContext) -> Void) -> CIImage? {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        draw(context)
        return context.makeImage().map { CIImage(cgImage: $0) }
    }

    /// Stages 3–5 on a finished shot (or transition): screen effects, film look, overlays.
    public func finish(_ image: CIImage, look: FrameLook, overlays: CIImage?) -> CIImage {
        var result = screen(image, state: look.screen)
        result = film(result, post: look.post, frame: look.frame)
        if let overlays {
            result = overlays.transformed(by: CGAffineTransform(translationX: image.extent.minX, y: image.extent.minY)).composited(over: result)
        }
        return result.cropped(to: image.extent)
    }

    // MARK: Output

    /// Renders into BGRA bytes (premultiplied), row-major, top row first.
    public func bytes(_ image: CIImage, width: Int, height: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let flipped = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        context.render(flipped, toBitmap: &bytes, rowBytes: width * 4, bounds: CGRect(x: 0, y: 0, width: width, height: height),
                       format: .BGRA8, colorSpace: colorSpace)
        return bytes
    }

    /// CIImage from BGRA bytes (top row first).
    public func image(bytes: [UInt8], width: Int, height: Int) -> CIImage {
        CIImage(bitmapData: Data(bytes), bytesPerRow: width * 4, size: CGSize(width: width, height: height), format: .BGRA8,
                colorSpace: colorSpace)
    }

    /// Renders into a Metal texture (the live stage's post-process pass).
    public func render(_ image: CIImage, to texture: MTLTexture, commandBuffer: MTLCommandBuffer) {
        let destination = CIRenderDestination(mtlTexture: texture, commandBuffer: commandBuffer)
        destination.isFlipped = true
        _ = try? context.startTask(toRender: image, to: destination)
    }
}
