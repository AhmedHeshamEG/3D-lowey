#if canImport(CoreGraphics) && canImport(CoreText)
    import CoreGraphics
    @testable import HmmPerception
    import XCTest

    final class DrawingTests: XCTestCase {
        private func frame(_ gray: CGFloat) -> CGImage? {
            let context = CGContext(data: nil, width: 160, height: 90, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.setFillColor(CGColor(red: gray, green: gray, blue: gray, alpha: 1))
            context?.fill(CGRect(x: 0, y: 0, width: 160, height: 90))
            return context?.makeImage()
        }

        func testContactSheetHasTheLayoutSize() throws {
            let frames = try (0 ..< 6).map { index in
                try ContactSheetFrame(image: XCTUnwrap(frame(CGFloat(index) / 6)), timecode: "00:0\(index).00", note: "#1 moves")
            }
            let sheet = try XCTUnwrap(PerceptionDrawing.contactSheet(frames, maxWidth: 1200))
            let layout = ContactSheetLayout(count: 6, aspect: 16.0 / 9.0, maxWidth: 1200)
            XCTAssertEqual(sheet.width, Int(layout.width))
            XCTAssertEqual(sheet.height, Int(layout.height))
        }

        func testMarksAndValueView() throws {
            let image = try XCTUnwrap(frame(0.5))
            let marks = MarkLayout.place([PerceptionRect(x: 0.2, y: 0.2, width: 0.2, height: 0.2)])
            let marked = try XCTUnwrap(PerceptionDrawing.marked(image, marks: marks))
            XCTAssertEqual(marked.width, 160)
            let pixels = try XCTUnwrap(PerceptionDrawing.rgbaPixels(image, maxSide: 64))
            let value = ValueImage(pixels: pixels.pixels, width: pixels.width, height: pixels.height)
            XCTAssertEqual(value.lightness[0], 53.4, accuracy: 1.5)
            XCTAssertNotNil(PerceptionDrawing.valueImage(value.blurred(radius: 2)))
        }
    }
#endif
