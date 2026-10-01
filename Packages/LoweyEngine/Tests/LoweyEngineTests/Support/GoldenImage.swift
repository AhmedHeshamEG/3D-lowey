import CoreGraphics
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers
import XCTest

/// Golden-image comparison. Each test renders a frame, compares it with `Golden/<name>.png` and attaches the render
/// (always) plus a difference image (on failure). A golden that doesn't exist yet, or a run with
/// `RECORD_GOLDENS=1` (`TEST_RUNNER_RECORD_GOLDENS=1` through xcodebuild), records the render as the new golden
/// and fails, so a new golden is always looked at before it's committed.
@MainActor
struct GoldenImage {
    /// Pixels whose channels differ by more than this count as different.
    var channelTolerance = 24
    /// The share of different pixels allowed.
    var maxDifferentFraction = 0.01

    struct Result {
        var differentFraction: Double
        var meanDifference: Double
        var difference: CGImage?
    }

    static var recording: Bool { ProcessInfo.processInfo.environment["RECORD_GOLDENS"] == "1" }

    /// Where recorded goldens go: `$GOLDEN_OUTPUT` or the temporary folder (CI uploads it).
    static var outputFolder: URL {
        let path = ProcessInfo.processInfo.environment["GOLDEN_OUTPUT"] ?? NSTemporaryDirectory() + "LoweyGoldens"
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    func assertMatches(_ image: CGImage, named name: String, file: StaticString = #filePath, line: UInt = #line) throws {
        attach(image, name: name)
        guard !Self.recording, let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Golden") else {
            let saved = try Self.record(image, name: name)
            XCTFail("Recorded \(name).png at \(saved.path) — check it, then commit it to Tests/LoweyEngineTests/Golden.", file: file, line: line)
            return
        }
        let golden = try XCTUnwrap(Self.load(url), "Golden \(name).png can't be read", file: file, line: line)
        guard golden.width == image.width, golden.height == image.height else {
            XCTFail("\(name): size \(image.width)×\(image.height), golden \(golden.width)×\(golden.height)", file: file, line: line)
            return
        }
        let result = compare(image, golden)
        if result.differentFraction > maxDifferentFraction {
            if let difference = result.difference { attach(difference, name: name + "-difference") }
            _ = try? Self.record(image, name: name)
            XCTFail(String(format: "%@: %.2f%% of pixels differ (allowed %.2f%%), mean difference %.2f", name, result.differentFraction * 100,
                           maxDifferentFraction * 100, result.meanDifference), file: file, line: line)
        }
    }

    func compare(_ image: CGImage, _ golden: CGImage) -> Result {
        let a = Self.rgba(image)
        let b = Self.rgba(golden)
        let count = image.width * image.height
        guard a.count == b.count, count > 0 else { return Result(differentFraction: 1, meanDifference: 255) }
        var different = 0
        var total = 0
        var mask = [UInt8](repeating: 0, count: a.count)
        for pixel in 0 ..< count {
            var worst = 0
            for channel in 0 ..< 3 {
                let delta = abs(Int(a[pixel * 4 + channel]) - Int(b[pixel * 4 + channel]))
                worst = max(worst, delta)
                total += delta
            }
            let base = pixel * 4
            if worst > channelTolerance {
                different += 1
                mask[base] = 255
                mask[base + 3] = 255
            } else {
                let grey = UInt8(Int(a[base]) / 4)
                mask[base] = grey
                mask[base + 1] = grey
                mask[base + 2] = grey
                mask[base + 3] = 255
            }
        }
        return Result(differentFraction: Double(different) / Double(count), meanDifference: Double(total) / Double(count * 3),
                      difference: Self.image(rgba: mask, width: image.width, height: image.height))
    }

    func attach(_ image: CGImage, name: String) {
        let attachment = XCTAttachment(image: UIImage(cgImage: image))
        attachment.name = name
        attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: "Render \(name)") { $0.add(attachment) }
    }

    static func record(_ image: CGImage, name: String) throws -> URL {
        try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
        let url = outputFolder.appendingPathComponent(name + ".png")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return url
    }

    static func load(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// RGBA8 bytes of any image (drawn into an sRGB context, so goldens and renders compare like for like).
    static func rgba(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                          bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        return drawn ? bytes : []
    }

    static func image(rgba bytes: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Mean luminance and the share of pixels unlike the corner colour (a blank frame scores 0).
    static func coverage(_ image: CGImage) -> (luminance: Double, content: Double) {
        let bytes = rgba(image)
        guard bytes.count >= 4 else { return (0, 0) }
        let corner = Array(bytes[0 ..< 3])
        var luminance = 0.0
        var content = 0
        let count = bytes.count / 4
        for pixel in 0 ..< count {
            let r = Double(bytes[pixel * 4]), g = Double(bytes[pixel * 4 + 1]), b = Double(bytes[pixel * 4 + 2])
            luminance += 0.2126 * r + 0.7152 * g + 0.0722 * b
            if abs(Int(bytes[pixel * 4]) - Int(corner[0])) + abs(Int(bytes[pixel * 4 + 1]) - Int(corner[1]))
                + abs(Int(bytes[pixel * 4 + 2]) - Int(corner[2])) > 30 { content += 1 }
        }
        return (luminance / Double(count) / 255, Double(content) / Double(count))
    }
}
