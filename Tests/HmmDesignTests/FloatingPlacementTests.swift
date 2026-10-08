@testable import HmmDesign
import XCTest

final class FloatingPlacementTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1200, height: 800)
    private let panel = CGSize(width: 330, height: 400)

    func testSitsToTheRightOfTheTargetWithoutCoveringIt() {
        let target = CGRect(x: 300, y: 300, width: 200, height: 150)
        let result = HmmFloatingPlacement.place(panel, beside: target, in: screen)
        XCTAssertEqual(result.side, .right)
        XCTAssertEqual(result.frame.minX, 512)
        XCTAssertEqual(result.frame.midY, target.midY)
        XCTAssertEqual(result.coverage, 0)
    }

    func testFlipsLeftAtTheRightEdge() {
        let target = CGRect(x: 900, y: 300, width: 200, height: 150)
        let result = HmmFloatingPlacement.place(panel, beside: target, in: screen)
        XCTAssertEqual(result.side, .left)
        XCTAssertEqual(result.frame.maxX, 888)
        XCTAssertEqual(result.coverage, 0)
    }

    func testKeepsItsSideWhileItFits() {
        let target = CGRect(x: 600, y: 300, width: 100, height: 100)
        XCTAssertEqual(HmmFloatingPlacement.place(panel, beside: target, in: screen, current: .left).side, .left)
        XCTAssertEqual(HmmFloatingPlacement.place(panel, beside: target, in: screen, current: .right).side, .right)
    }

    func testAHugeTargetGetsTheRoomierSideAndLeastCover() {
        let target = CGRect(x: 100, y: 100, width: 900, height: 600)
        let result = HmmFloatingPlacement.place(panel, beside: target, in: screen)
        XCTAssertEqual(result.side, .right)
        XCTAssertEqual(result.frame.maxX, screen.maxX)
        XCTAssertGreaterThan(result.coverage, 0)
        XCTAssertLessThan(result.coverage, 0.25)
    }

    func testStaysInsideTheBoundsVertically() {
        let top = HmmFloatingPlacement.place(panel, beside: CGRect(x: 100, y: 0, width: 50, height: 50), in: screen)
        XCTAssertEqual(top.frame.minY, 0)
        let bottom = HmmFloatingPlacement.place(panel, beside: CGRect(x: 100, y: 780, width: 50, height: 50), in: screen)
        XCTAssertEqual(bottom.frame.maxY, screen.maxY)
    }

    func testAPanelTallerThanTheScreenShrinksToIt() {
        let result = HmmFloatingPlacement.place(CGSize(width: 300, height: 2000), beside: CGRect(x: 100, y: 100, width: 10, height: 10), in: screen)
        XCTAssertEqual(result.frame.height, screen.height)
    }

    func testDockedAndBounds() {
        XCTAssertEqual(HmmFloatingPlacement.docked(panel, in: screen), CGRect(x: 870, y: 0, width: 330, height: 400))
        XCTAssertEqual(HmmFloatingPlacement.docked(panel, in: screen, side: .left).minX, 0)
        XCTAssertNil(HmmFloatingPlacement.bounds(of: []))
        XCTAssertEqual(HmmFloatingPlacement.bounds(of: [CGPoint(x: 10, y: 40), CGPoint(x: 30, y: 5)]), CGRect(x: 10, y: 5, width: 20, height: 35))
        XCTAssertEqual(HmmFloatingSide.left.flipped, .right)
    }

    func testAPointTargetIsCoveredOnlyWhenThePanelHoldsIt() {
        let point = CGRect(x: 600, y: 400, width: 0, height: 0)
        XCTAssertEqual(HmmFloatingPlacement.place(panel, beside: point, in: screen).coverage, 0)
        let tiny = CGRect(x: 0, y: 0, width: 400, height: 300)
        let centre = CGRect(x: 200, y: 150, width: 0, height: 0)
        XCTAssertEqual(HmmFloatingPlacement.place(CGSize(width: 400, height: 300), beside: centre, in: tiny).coverage, 1)
    }
}
