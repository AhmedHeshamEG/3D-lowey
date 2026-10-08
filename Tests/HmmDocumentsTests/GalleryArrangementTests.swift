@testable import HmmDocuments
import XCTest

final class GalleryArrangementTests: XCTestCase {
    private func item(_ id: String, _ name: String, created: Double, modified: Double) -> GalleryItem {
        GalleryItem(id: id, name: name, created: Date(timeIntervalSince1970: created), modified: Date(timeIntervalSince1970: modified))
    }

    private var items: [GalleryItem] {
        [item("a", "Robot", created: 10, modified: 50), item("b", "Café", created: 20, modified: 40),
         item("c", "Room 2", created: 30, modified: 30), item("d", "room 10", created: 40, modified: 60)]
    }

    private func ids(_ entries: [GalleryEntry]) -> [String] {
        entries.map(\.id)
    }

    func testTheTopLevelSortsByRecentFirst() {
        XCTAssertEqual(ids(GalleryArrangement().entries(items)), ["item-d", "item-a", "item-b", "item-c"])
    }

    func testNameAndCreatedOrders() {
        var arrangement = GalleryArrangement(sort: .name)
        XCTAssertEqual(ids(arrangement.entries(items)), ["item-b", "item-a", "item-c", "item-d"], "numbers sort as numbers: Room 2 before room 10")
        arrangement.sort = .created
        XCTAssertEqual(ids(arrangement.entries(items)), ["item-d", "item-c", "item-b", "item-a"])
    }

    func testAStackTakesItsMembersOffTheTopLevelAndSortsByItsNewest() {
        var arrangement = GalleryArrangement()
        let stack = arrangement.stack(["b", "c"], name: "Rooms", id: "s1", now: Date(timeIntervalSince1970: 5))
        XCTAssertEqual(stack, "s1")
        XCTAssertEqual(ids(arrangement.entries(items)), ["item-d", "item-a", "stack-s1"])
        XCTAssertEqual(ids(arrangement.entries(items, in: "s1")), ["item-b", "item-c"])
        XCTAssertEqual(arrangement.stack(containing: "c")?.name, "Rooms")
        XCTAssertNil(arrangement.stack(containing: "a"))
    }

    func testMovingBetweenStacksAndDissolving() {
        var arrangement = GalleryArrangement()
        arrangement.stack(["a", "b"], name: "One", id: "s1")
        arrangement.stack(["c"], name: "Two", id: "s2")
        arrangement.add(["b", "b"], to: "s2")
        XCTAssertEqual(arrangement.stacks.first { $0.id == "s2" }?.members, ["c", "b"])
        arrangement.add(["a"], to: "missing")
        XCTAssertEqual(arrangement.stacks.first { $0.id == "s1" }?.members, ["a"])
        arrangement.remove(["a"])
        XCTAssertNil(arrangement.stacks.first { $0.id == "s1" }, "an emptied stack goes")
        arrangement.rename("s2", to: "  Rooms ")
        arrangement.rename("s2", to: "   ")
        XCTAssertEqual(arrangement.stacks.first?.name, "Rooms")
        arrangement.unstack("s2")
        XCTAssertTrue(arrangement.stacks.isEmpty)
        XCTAssertEqual(arrangement.entries(items).count, 4)
    }

    func testSearchFindsDocumentsInsideStacksAndMatchingStacks() {
        var arrangement = GalleryArrangement()
        arrangement.stack(["c", "d"], name: "Rooms", id: "s1")
        XCTAssertEqual(ids(arrangement.entries(items, query: "room")), ["stack-s1", "item-d", "item-c"])
        XCTAssertEqual(ids(arrangement.entries(items, query: "cafe")), ["item-b"], "accents don't matter")
        XCTAssertEqual(ids(arrangement.entries(items, in: "s1", query: "10")), ["item-d"], "inside a stack, only its documents")
        XCTAssertEqual(arrangement.entries(items, in: "nope"), [])
    }

    func testPruningForgetsMissingDocuments() {
        var arrangement = GalleryArrangement()
        arrangement.stack(["a", "b"], name: "One", id: "s1")
        arrangement.stack(["c"], name: "Two", id: "s2")
        arrangement.prune(keeping: ["a", "d"])
        XCTAssertEqual(arrangement.stacks.map(\.id), ["s1"])
        XCTAssertEqual(arrangement.stacks.first?.members, ["a"])
        let onlyD = [item("d", "room 10", created: 40, modified: 60)]
        XCTAssertEqual(ids(arrangement.entries(onlyD)), ["item-d"], "a stack whose documents aren't listed isn't shown")
    }

    func testSavesAndLoadsBesideTheDocuments() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("gallery-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        XCTAssertEqual(GalleryArrangement.load(from: folder), GalleryArrangement())
        var arrangement = GalleryArrangement(sort: .name)
        arrangement.stack(["a"], name: "One", id: "s1", now: Date(timeIntervalSince1970: 1_000_000))
        try arrangement.save(to: folder)
        XCTAssertEqual(GalleryArrangement.load(from: folder), arrangement)
        try Data("{\"stacks\": [], \"sort\": \"sideways\"}".utf8).write(to: folder.appendingPathComponent(GalleryArrangement.fileName))
        XCTAssertEqual(GalleryArrangement.load(from: folder).sort, .recent, "an unknown sort falls back to Recent")
        XCTAssertEqual(GallerySort.created.title, "Date created")
    }
}
