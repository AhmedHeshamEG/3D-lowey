import Foundation
@testable import HmmDesign
import XCTest

final class HoldMenuTests: XCTestCase {
    func testEveryMenuStartsWithTheSameRowsAndEndsWithDelete() {
        let menus = [
            HmmHoldMenu(),
            HmmHoldMenu(duplicate: {}, rename: {}, copy: {}, paste: {}, delete: {}),
            HmmHoldMenu(duplicate: {}, extras: [HmmHoldMenu.Item("Split at playhead"), HmmHoldMenu.Item("Reverse")], delete: {})
        ]
        for menu in menus {
            let sections = menu.sections
            XCTAssertEqual(sections.first?.map(\.title), ["Duplicate", "Rename", "Copy", "Paste"])
            XCTAssertEqual(sections.last?.map(\.title), ["Delete"])
            XCTAssertEqual(sections.last?.first?.isDestructive, true)
        }
    }

    func testARowTheThingCannotDoIsDimmedNotMissing() {
        let menu = HmmHoldMenu(duplicate: {}, delete: {})
        let rows = menu.sections[0]
        XCTAssertEqual(rows.map(\.isEnabled), [true, false, false, false])
        XCTAssertEqual(menu.sections.count, 2, "no extras: no empty section")
        XCTAssertEqual(HmmHoldMenu().sections.last?.first?.isEnabled, false)
    }

    func testExtrasSitBetweenAndStopAtThree() {
        let extras = ["Hide", "Lock", "Group", "Ungroup"].map { HmmHoldMenu.Item($0) }
        let menu = HmmHoldMenu(extras: extras)
        XCTAssertEqual(menu.sections.count, 3)
        XCTAssertEqual(menu.sections[1].map(\.title), ["Hide", "Lock", "Group"])
    }

    @MainActor
    func testRowsRunTheirActions() {
        var ran: [String] = []
        let moves = HmmHoldMenu.Item("Move to", children: [HmmHoldMenu.Item("Inks", isVerbatim: true) { ran.append("move") }])
        let menu = HmmHoldMenu(duplicate: { ran.append("duplicate") }, extras: [moves], delete: { ran.append("delete") })
        menu.sections[0][0].action()
        menu.sections[0][1].action()
        menu.sections[1][0].children[0].action()
        menu.sections[2][0].action()
        XCTAssertEqual(ran, ["duplicate", "move", "delete"])
        XCTAssertTrue(menu.sections[1][0].children[0].isVerbatim)
        XCTAssertEqual(HmmHoldMenu.Item("Group", id: "g2").id, "g2")
        XCTAssertEqual(HmmHoldMenu.Item("Group").id, "Group")
    }
}

final class PencilOrHandTests: XCTestCase {
    func testOneFingerMakesUntilAPencilTouches() {
        var input = HmmPencilOrHand()
        XCTAssertTrue(input.fingerMakes)
        XCTAssertTrue(input.pencilTouched())
        XCTAssertFalse(input.fingerMakes, "from the first Pencil touch, fingers only move the view")
        XCTAssertFalse(input.pencilTouched(), "only the first touch changes the answer")
    }

    func testTheSwitchLetsAFingerMakeWithAPencilAround() {
        var input = HmmPencilOrHand(pencilSeen: true)
        XCTAssertFalse(input.fingerMakes)
        input.fingersAlwaysMake = true
        XCTAssertTrue(input.fingerMakes)
    }

    func testItIsRemembered() throws {
        let name = "hmm.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(HmmPencilOrHand(defaults: defaults), HmmPencilOrHand())
        var input = HmmPencilOrHand(defaults: defaults)
        input.pencilTouched()
        input.fingersAlwaysMake = true
        input.save(to: defaults)
        XCTAssertEqual(HmmPencilOrHand(defaults: defaults), HmmPencilOrHand(pencilSeen: true, fingersAlwaysMake: true))
    }
}
