#if canImport(UIKit) && canImport(Metal)
    import Foundation
    import HmmBoard
    @testable import HmmBoardUI
    import HmmBrush
    import HmmDesign
    import XCTest

    @MainActor
    final class BoardModelTests: XCTestCase {
        private func temporaryStore() -> BoardStore {
            BoardStore(folder: FileManager.default.temporaryDirectory.appendingPathComponent("board-\(UUID().uuidString)"), appName: "Tests")
        }

        private func drawLine(_ model: BoardModel, y: Double) {
            model.mutate { session in
                session.tool = .draw
                session.begin(BrushInput(point: Vec2(0, y), pressure: 1, time: 0), slack: 6)
                session.move(BrushInput(point: Vec2(100, y), pressure: 1, time: 0.2))
                session.end(BrushInput(point: Vec2(100, y), pressure: 1, time: 0.2), slack: 6)
            }
        }

        /// A 2 × 1 red PNG, made by the board's own picture code.
        private func tinyPNG() throws -> Data {
            let renderer = try BoardRenderer()
            var board = Board()
            board.paper.color = try XCTUnwrap(BoardColor(hex: "#FF0000"))
            let image = try XCTUnwrap(renderer.snapshot(of: board, region: BoardRect(x: 0, y: 0, width: 2, height: 1), pixelsPerUnit: 1))
            return try XCTUnwrap(BoardModel.png(image))
        }

        func testABoardIsWrittenAsItChangesAndComesBackWithItsUndo() async throws {
            let store = temporaryStore()
            defer { try? FileManager.default.removeItem(at: store.folder) }
            let model = BoardModel(store: store, defaults: UserDefaults(suiteName: "board-tests-\(UUID().uuidString)") ?? .standard)
            XCTAssertFalse(model.isLoaded)
            await model.load()
            XCTAssertTrue(model.isLoaded)
            drawLine(model, y: 10)
            drawLine(model, y: 30)
            model.undo()
            XCTAssertEqual(model.session.board.items.count, 1)
            model.close()

            let again = BoardModel(store: store)
            await again.load()
            XCTAssertEqual(again.session.board.items.count, 1)
            XCTAssertTrue(again.session.canRedo, "undo and redo survive closing the board")
            again.redo()
            XCTAssertEqual(again.session.board.items.count, 2)
            again.close()
            XCTAssertTrue(store.exists)
            XCTAssertEqual(try store.load().items.count, 2)
        }

        func testPinsPicturesAndTheHoldMenu() async throws {
            let store = temporaryStore()
            defer { try? FileManager.default.removeItem(at: store.folder) }
            let model = BoardModel(store: store)
            await model.load()
            XCTAssertFalse(model.canPin, "nothing to pin to yet")
            var pins: [BoardPin] = []
            model.pin = { pins.append($0) }
            XCTAssertFalse(model.canPin, "an empty board has nothing to pin")

            try model.addPicture(tinyPNG(), at: Vec2(300, 300))
            XCTAssertEqual(model.session.board.items.first?.picture?.rect, BoardRect(x: 296, y: 296, width: 8, height: 8))
            XCTAssertEqual(model.session.tool, .select)
            model.addPicture(Data([1, 2, 3]))
            XCTAssertNotNil(model.message)
            XCTAssertEqual(BoardModel.fileExtension(of: Data([0xFF, 0xD8, 0xFF])), "jpg")
            XCTAssertEqual(BoardModel.fileExtension(of: Data([0x47, 0x49, 0x46, 0x38])), "gif")
            XCTAssertEqual(BoardModel.fileExtension(of: Data([0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63])), "heic")
            XCTAssertEqual(BoardModel.fileExtension(of: Data([9])), "img")

            drawLine(model, y: 10)
            model.setTool(.select)
            XCTAssertNil(model.holdMenu(at: Vec2(900, 900), slack: 10), "nothing there, nothing copied")
            let menu = try XCTUnwrap(model.holdMenu(at: Vec2(50, 10), slack: 10))
            XCTAssertEqual(model.session.selection.count, 1, "holding a thing picks it")
            XCTAssertNil(menu.rename, "only frames have names")
            XCTAssertEqual(menu.extras.map(\.id), ["board-pin", "Bring to the front", "Send to the back"])
            menu.extras[0].action()
            XCTAssertEqual(pins.count, 1)
            XCTAssertEqual(pins.first?.png.prefix(4), Data([0x89, 0x50, 0x4E, 0x47]))
            menu.copy?()
            XCTAssertNotNil(model.holdMenu(at: Vec2(900, 900), slack: 10)?.paste, "empty space offers Paste once something is copied")
            menu.duplicate?()
            XCTAssertEqual(model.session.board.items.count, 3)
            menu.delete?()
            XCTAssertEqual(model.session.board.items.count, 2)
            model.paste(at: Vec2(500, 500))
            XCTAssertEqual(model.session.board.items.count, 3)
            XCTAssertNotNil(model.sharedPNG())
            model.mutate { $0.selection = [] }
            XCTAssertNotNil(model.sharedPNG())
            model.pinExcerpt(of: nil)
            XCTAssertEqual(pins.count, 2)
            model.setTool(.draw)
            XCTAssertNil(model.holdMenu(at: Vec2(50, 10), slack: 10), "the hold menu is the Select tool's")
            BoardModel.clipboard = nil
            model.close()
        }

        func testTheFrameToDrawFollowsTheToolAndThePencil() async {
            let model = BoardModel(store: nil, defaults: UserDefaults(suiteName: "board-tests-\(UUID().uuidString)") ?? .standard)
            await model.load()
            XCTAssertTrue(model.pencilOrHand.fingerMakes)
            model.pencilTouched()
            XCTAssertFalse(model.pencilOrHand.fingerMakes)
            model.sized(Vec2(800, 600))
            model.hover = Vec2(5, 5)
            var scene = model.scene(size: Vec2(800, 600), contentScale: 2, showsHover: true)
            XCTAssertEqual(scene.overlay.hover, Vec2(5, 5))
            XCTAssertNil(model.scene(size: Vec2(800, 600), contentScale: 2, showsHover: false).overlay.hover)
            model.setTool(.erase)
            model.eraserAt = Vec2(1, 1)
            scene = model.scene(size: Vec2(800, 600), contentScale: 2, showsHover: true)
            XCTAssertEqual(scene.overlay.eraser, Vec2(1, 1))
            XCTAssertNil(scene.overlay.hover)
            drawLine(model, y: 10)
            XCTAssertEqual(model.scene(size: Vec2(800, 600), contentScale: 2, showsHover: true).changes.appended.count, 1)
            XCTAssertTrue(model.scene(size: Vec2(800, 600), contentScale: 2, showsHover: true).changes.isEmpty, "changes are handed over once")
            model.mutate { $0.viewport = BoardViewport(center: Vec2(999, 999), scale: 4) }
            model.showEverything()
            XCTAssertEqual(model.session.viewport.scale, 1)
            model.save()
            model.close()
        }
    }
#endif
