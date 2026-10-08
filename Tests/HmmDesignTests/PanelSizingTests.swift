@testable import HmmDesign
import XCTest

final class PanelSizingTests: XCTestCase {
    private let sizing = HmmPanelSizing(id: "test", minimum: CGSize(width: 280, height: 200), maximum: CGSize(width: 600, height: 900))

    func testRemembersAClampedSize() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "hmm.panel.tests"))
        sizing.reset(in: defaults)
        XCTAssertNil(sizing.load(from: defaults))
        sizing.save(HmmPanelSize(width: 9000, height: 10), to: defaults)
        XCTAssertEqual(sizing.load(from: defaults), HmmPanelSize(width: 600, height: 200))
        sizing.reset(in: defaults)
        XCTAssertNil(sizing.load(from: defaults))
        XCTAssertEqual(sizing.key, "hmm.panel.test")
    }

    func testTheGripGrowsTowardsItsSide() {
        let start = HmmPanelSize(width: 340)
        XCTAssertEqual(sizing.resized(start, shownHeight: 500, dx: 60, dy: 40, gripOnRight: true), HmmPanelSize(width: 400, height: 540))
        XCTAssertEqual(sizing.resized(start, shownHeight: 500, dx: 60, dy: 0, gripOnRight: false).width, 280)
        XCTAssertEqual(sizing.resized(HmmPanelSize(width: 340, height: 300), shownHeight: 500, dx: 0, dy: -500, gripOnRight: true).height, 200)
    }

    func testAWidthOnlySizeKeepsItsNaturalHeight() {
        XCTAssertNil(sizing.clamped(HmmPanelSize(width: 300)).height)
    }
}
