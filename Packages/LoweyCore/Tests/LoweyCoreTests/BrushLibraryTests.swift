import Foundation
@testable import LoweyCore
import XCTest

final class BrushLibraryTests: XCTestCase {
    func testTheStandardLibraryHoldsEveryBuiltInOnce() {
        let ids = BrushLibrary.standard.sets.flatMap(\.brushes)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(Set(ids), Set(BuiltInBrushes.all.map(\.id)))
        XCTAssertEqual(BrushLibrary.standard.brush(BuiltInBrushes.inkPenID)?.name, "Ink Pen")
        XCTAssertTrue(BuiltInBrushes.all.allSatisfy { $0 == $0.clamped }, "built-ins are already in range")
    }

    func testDuplicateLandsBesideTheOriginalWithAFreshName() {
        var library = BrushLibrary.standard
        let copy = library.duplicate("builtin.pencil", as: "mine-1")
        XCTAssertEqual(copy?.name, "Pencil copy")
        XCTAssertEqual(library.duplicate("builtin.pencil", as: "mine-2")?.name, "Pencil copy 2")
        let sketching = library.set("builtin.sketching")?.brushes ?? []
        XCTAssertEqual(Array(sketching.prefix(3)), ["builtin.pencil", "mine-2", "mine-1"])
        XCTAssertEqual(library.brush("mine-1")?.about.origin, .made)
    }

    func testResetBringsBackTheBuiltInOrTheImport() {
        var library = BrushLibrary.standard
        XCTAssertNil(library.resetTarget("builtin.marker"), "nothing to reset yet")
        var edited = BuiltInBrushes.marker
        edited.stroke.spacing = 1
        library.update(edited)
        XCTAssertEqual(library.resetTarget("builtin.marker"), BuiltInBrushes.marker)
        library.reset("builtin.marker")
        XCTAssertNil(library.brushes["builtin.marker"])

        library.duplicate("builtin.marker", as: "copy")
        var copy = library.brush("copy") ?? edited
        copy.rendering.flow = 0.1
        library.update(copy)
        let reset = library.reset("copy")
        XCTAssertEqual(reset?.rendering.flow, BuiltInBrushes.marker.rendering.flow)
        XCTAssertEqual(reset?.name, "Marker copy", "a copy keeps its own name")

        let imported = Brush(id: "imp", name: "From Procreate", about: BrushAbout(origin: .procreate))
        library.add([imported], toSet: "set-1", named: "Imported")
        var changed = imported
        changed.stroke.jitter = 1
        library.update(changed)
        XCTAssertEqual(library.reset("imp"), imported.clamped)
    }

    func testBuiltInsCannotBeDeletedButOthersCan() {
        var library = BrushLibrary.standard
        library.delete(BuiltInBrushes.inkPenID)
        XCTAssertNotNil(library.set(containing: BuiltInBrushes.inkPenID))
        library.duplicate(BuiltInBrushes.inkPenID, as: "pen-2")
        library.delete("pen-2")
        XCTAssertNil(library.brush("pen-2"))
        XCTAssertNil(library.set(containing: "pen-2"))
    }

    func testSetsAreMadeMovedAndDeleted() {
        var library = BrushLibrary.standard
        library.addSet(id: "mine", name: "  ")
        library.renameSet("mine", to: "My Set")
        XCTAssertEqual(library.sets.first?.name, "My Set")
        library.duplicate("builtin.charcoal", as: "char-2")
        library.move("char-2", to: "mine")
        library.move("builtin.pencil", to: "mine", at: 0)
        XCTAssertEqual(library.set("mine")?.brushes, ["builtin.pencil", "char-2"])
        XCTAssertFalse(library.set("builtin.sketching")?.brushes.contains("builtin.pencil") ?? true)
        library.moveSet("mine", to: 99)
        XCTAssertEqual(library.sets.last?.id, "mine")
        library.deleteSet("builtin.inking")
        XCTAssertNotNil(library.set("builtin.inking"), "built-in sets stay")
        library.deleteSet("mine")
        XCTAssertNil(library.brush("char-2"), "a made brush only that set held goes with it")
        XCTAssertNotNil(library.brush("builtin.pencil"))
        XCTAssertNil(library.set(containing: "builtin.pencil"), "until merged() puts it back")
        XCTAssertEqual(library.merged().set(containing: "builtin.pencil")?.id, "builtin.sketching")
    }

    func testANewerAppAddsItsBuiltInsWithoutMovingYours() {
        var old = BrushLibrary.standard
        old.sets.removeAll { $0.id == "builtin.painting" }
        old.sets[0].brushes.removeLast()
        old.move("builtin.pencil", to: "builtin.inking")
        let merged = old.merged()
        XCTAssertEqual(merged.set(containing: "builtin.pencil")?.id, "builtin.inking")
        XCTAssertEqual(merged.set(containing: "builtin.marker")?.id, "builtin.inking")
        XCTAssertNotNil(merged.set("builtin.painting"))
    }

    func testTheStoreKeepsTheLibraryAndItsPictures() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("brushes-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BrushLibraryStore(root: root)
        XCTAssertEqual(store.load(), BrushLibrary.standard.merged())
        let png = GreyPNG.encode(BrushImages.image(.chalkTip))
        let key = try store.store(image: png)
        XCTAssertEqual(try store.store(image: png), key)
        XCTAssertEqual(try Data(contentsOf: store.imageURL(key)), png)
        var library = BrushLibrary.standard
        library.add([Brush(id: "x", name: "Chalky", shape: BrushShape(source: .image(key)), about: BrushAbout(origin: .photoshop))],
                    toSet: "s", named: "Mine")
        try store.save(library)
        XCTAssertEqual(store.load(), library.merged())
    }
}
