@testable import LoweyCore
import XCTest

final class TimelineOutlineTests: XCTestCase {
    /// root "A" (group) ▸ child "B"; "C" on its own.
    private let scene = makeDocument().scene

    func testAnimatedChildrenShowUnderTheirGroup() {
        let entries = TimelineOutline.entries(scene: scene, include: ["b", "c"], collapsed: [])
        XCTAssertEqual(entries.map(\.id), ["a", "b", "c"], "the group comes first, its child under it")
        XCTAssertEqual(entries.map(\.depth), [0, 1, 0])
        XCTAssertEqual(entries.map(\.isGroup), [true, false, false])
    }

    func testCollapsingAGroupHidesItsRows() {
        let entries = TimelineOutline.entries(scene: scene, include: ["b", "c"], collapsed: ["a"])
        XCTAssertEqual(entries.map(\.id), ["a", "c"])
        XCTAssertTrue(entries[0].isCollapsed)
    }

    func testObjectsWithNothingAnimatedStayOut() {
        XCTAssertEqual(TimelineOutline.entries(scene: scene, include: ["c"], collapsed: []).map(\.id), ["c"])
        XCTAssertTrue(TimelineOutline.entries(scene: scene, include: [], collapsed: []).isEmpty)
    }

    func testAGroupStandsForEverythingAnimatedInside() {
        XCTAssertEqual(TimelineOutline.members(of: "a", scene: scene, animated: ["a", "b", "c"]), ["a", "b"])
        XCTAssertEqual(TimelineOutline.members(of: "a", scene: scene, animated: ["b"]), ["b"])
        XCTAssertEqual(TimelineOutline.members(of: "c", scene: scene, animated: ["b"]), [])
    }
}
