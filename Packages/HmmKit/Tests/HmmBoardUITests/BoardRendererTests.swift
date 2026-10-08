#if canImport(UIKit) && canImport(Metal)
    import CoreGraphics
    import Foundation
    import HmmBoard
    @testable import HmmBoardUI
    import HmmBrush
    import Metal
    import XCTest

    /// The board drawn for real on the simulator's GPU: the brush engine's stamps, a note with its words, an arrow.
    @MainActor
    final class BoardRendererTests: XCTestCase {
        private struct Pixels {
            let width: Int
            let height: Int
            let bytes: [UInt8]

            /// Red, green, blue at a pixel (0…255).
            func color(_ x: Int, _ y: Int) -> (Int, Int, Int) {
                let index = (y * width + x) * 4
                return (Int(bytes[index]), Int(bytes[index + 1]), Int(bytes[index + 2]))
            }
        }

        private func pixels(_ image: CGImage) throws -> Pixels {
            let width = image.width, height = image.height
            let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let data = try XCTUnwrap(context.data)
            let bytes = [UInt8](UnsafeRawBufferPointer(start: data, count: width * height * 4))
            return Pixels(width: width, height: height, bytes: bytes)
        }

        private func touch(_ x: Double, _ y: Double, time: Double = 0) -> BrushInput<Vec2> {
            BrushInput(point: Vec2(x, y), pressure: 1, time: time)
        }

        /// A red line across the top, a note with a word under it, an arrow at the bottom.
        private func plannedBoard() throws -> BoardSession {
            var session = BoardSession()
            session.ids = BoardIDs(counted: true)
            session.color = try XCTUnwrap(BoardColor(hex: "#FF2020"))
            session.size = 6
            session.begin(touch(20, 40), slack: 6)
            session.move(touch(100, 40, time: 0.2))
            session.move(touch(180, 40, time: 0.4))
            session.end(touch(180, 40, time: 0.4), slack: 6)
            session.tool = .note
            session.begin(touch(100, 150), slack: 6)
            session.end(touch(100, 150), slack: 6)
            session.setText("Lamp", ofNote: "item-2")
            session.finishEditing()
            session.tool = .arrow
            session.color = try XCTUnwrap(BoardColor(hex: "#20FF20"))
            session.begin(touch(20, 235), slack: 6)
            session.move(touch(180, 235))
            session.end(touch(180, 235), slack: 6)
            XCTAssertEqual(session.board.items.count, 3)
            return session
        }

        private func check(_ picture: Pixels, scale: Int, file: StaticString = #filePath, line: UInt = #line) {
            let paper = picture.color(4 * scale, 4 * scale)
            XCTAssertLessThan(max(paper.0, paper.1, paper.2), 60, "the dark paper", file: file, line: line)
            let ink = picture.color(100 * scale, 40 * scale)
            XCTAssertGreaterThan(ink.0, ink.1 + 80, "the red stroke \(ink)", file: file, line: line)
            let slip = picture.color(170 * scale, 200 * scale)
            XCTAssertGreaterThan(slip.0, 200, "the note's amber slip \(slip)", file: file, line: line)
            XCTAssertLessThan(slip.2, 170, "the note's amber slip \(slip)", file: file, line: line)
            var darkest = 255
            for y in stride(from: 94 * scale, to: 118 * scale, by: 1) {
                for x in stride(from: 14 * scale, to: 70 * scale, by: 1) {
                    darkest = min(darkest, picture.color(x, y).0)
                }
            }
            XCTAssertLessThan(darkest, 140, "the note's words are written on it", file: file, line: line)
            let arrow = picture.color(80 * scale, 235 * scale)
            XCTAssertGreaterThan(arrow.1, arrow.0 + 80, "the green arrow \(arrow)", file: file, line: line)
        }

        func testAPictureOfTheBoardShowsInkWordsAndArrows() throws {
            let renderer = try BoardRenderer()
            let session = try plannedBoard()
            let region = BoardRect(x: 0, y: 0, width: 200, height: 250)
            let image = try XCTUnwrap(renderer.snapshot(of: session.board, region: region, pixelsPerUnit: 2))
            XCTAssertEqual(image.width, 400)
            XCTAssertEqual(image.height, 500)
            try check(pixels(image), scale: 2)
            // Only the picked items, and never larger than asked.
            let small = try XCTUnwrap(renderer.snapshot(of: session.board, items: ["item-2"], region: region, pixelsPerUnit: 2, maximumSide: 250))
            XCTAssertEqual(small.height, 250)
            let alone = try pixels(small)
            let whereTheStrokeWas = alone.color(100, 40)
            XCTAssertLessThan(whereTheStrokeWas.0, 60, "the stroke wasn't picked")
            XCTAssertNil(renderer.snapshot(of: session.board, region: BoardRect(x: 0, y: 0, width: 0, height: 0), pixelsPerUnit: 2))
        }

        func testAFrameOnScreenIsTheLayerPlusWhatMoves() throws {
            let renderer = try BoardRenderer()
            var session = try plannedBoard()
            // What made the board has been drawn by the first frame; from here on only new changes count.
            _ = session.takeChanges()
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: BoardRenderer.format, width: 200, height: 250, mipmapped: false)
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = .shared
            let target = try XCTUnwrap(renderer.device.makeTexture(descriptor: descriptor))
            let overlay = BoardDrawList.Overlay(accent: .paper, ink: .ink)
            var scene = BoardScene(board: session.board, viewport: BoardViewport(center: Vec2(100, 125), scale: 1), size: Vec2(200, 250),
                                   contentScale: 1, overlay: overlay)
            func drawn() throws -> Pixels {
                let commandBuffer = try XCTUnwrap(renderer.queue.makeCommandBuffer())
                renderer.draw(scene, to: target, commandBuffer: commandBuffer)
                commandBuffer.commit()
                commandBuffer.waitUntilCompleted()
                return try pixels(XCTUnwrap(BoardRenderer.image(from: target)))
            }
            try check(drawn(), scale: 1)

            // A new stroke is laid on the layer it already has; the stroke under the Pencil is drawn over it.
            session.tool = .draw
            session.color = try XCTUnwrap(BoardColor(hex: "#2020FF"))
            session.begin(touch(20, 60), slack: 6)
            session.move(touch(180, 60, time: 0.3))
            session.end(touch(180, 60, time: 0.3), slack: 6)
            scene.board = session.board
            scene.changes = session.takeChanges()
            XCTAssertEqual(scene.changes.appended.count, 1)
            session.begin(touch(20, 75), slack: 6)
            session.move(touch(180, 75, time: 0.3))
            scene.liveStroke = session.liveStroke()
            scene.liveBrush = session.brush
            let second = try drawn()
            let kept = second.color(100, 60), live = second.color(100, 75)
            XCTAssertGreaterThan(kept.2, kept.0 + 80, "the new stroke \(kept)")
            XCTAssertGreaterThan(live.2, live.0 + 80, "the stroke being drawn \(live)")
            check(second, scale: 1)

            // Panned while fingers move: the same layer, shifted.
            scene.changes = BoardChanges()
            scene.liveStroke = nil
            scene.interacting = true
            scene.viewport = BoardViewport(center: Vec2(110, 125), scale: 1)
            let moved = try drawn().color(90, 60)
            XCTAssertGreaterThan(moved.2, moved.0 + 80, "the layer follows the view \(moved)")
        }
    }
#endif
