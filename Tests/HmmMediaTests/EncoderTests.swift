#if canImport(AVFoundation)
    import AVFoundation
    @testable import HmmMedia
    import XCTest

    final class EncoderTests: XCTestCase {
        /// Encodes 12 frames with sound, then checks the file with the same verifier the apps use.
        func testEncodeAndVerify() async throws {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("hmm-encode-\(UUID().uuidString).mp4")
            defer { try? FileManager.default.removeItem(at: url) }
            let settings = EncodeSettings(width: 64, height: 64, fps: 24, codec: .h264)
            let audio = [Float](repeating: 0.1, count: 48000 / 2 * 2)
            let encoder = try VideoEncoder(url: url, settings: settings, audio: audio)
            for frame in 0 ..< 12 {
                let buffer = try encoder.makePixelBuffer()
                CVPixelBufferLockBaseAddress(buffer, [])
                if let base = CVPixelBufferGetBaseAddress(buffer) {
                    memset(base, Int32(frame * 20), CVPixelBufferGetDataSize(buffer))
                }
                CVPixelBufferUnlockBaseAddress(buffer, [])
                try await encoder.append(buffer, frame: frame)
            }
            try await encoder.finish()
            let problems = try await MediaInspector.verify(url, expected: ExportExpectation(duration: 0.5, frameCount: 12, width: 64, height: 64,
                                                                                            audio: true))
            XCTAssertEqual(problems, [])
        }

        func testOddSizesAreRefused() {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("odd.mp4")
            XCTAssertThrowsError(try VideoEncoder(url: url, settings: EncodeSettings(width: 63, height: 64, fps: 24, codec: .h264)))
        }

        func testPNGAndGIF() throws {
            let image = try XCTUnwrap(Self.solid(width: 8, height: 8))
            XCTAssertGreaterThan(try ImageWriters.png(image).count, 20)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("hmm-\(UUID().uuidString).gif")
            defer { try? FileManager.default.removeItem(at: url) }
            let gif = try GIFWriter(url: url, frameCount: 3, fps: 12)
            for _ in 0 ..< 3 {
                gif.append(image)
            }
            try gif.finish()
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        }

        static func solid(width: Int, height: Int) -> CGImage? {
            let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.setFillColor(CGColor(red: 1, green: 0.7, blue: 0.3, alpha: 1))
            context?.fill(CGRect(x: 0, y: 0, width: width, height: height))
            return context?.makeImage()
        }
    }
#endif
