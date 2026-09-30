@testable import HmmDesign
import XCTest

final class TokenTests: XCTestCase {
    func testNeutralsMatchTheSpec() {
        XCTAssertEqual(HmmNeutrals.dark.background, HmmRGB(hex: 0x0E0F11))
        XCTAssertEqual(HmmNeutrals.light.text, HmmRGB(hex: 0x1D1D1F))
        XCTAssertEqual(HmmAccent.lowey.rgb, HmmRGB(hex: 0xFFB847))
    }

    func testTextIsReadableInBothAppearances() {
        for neutrals in [HmmNeutrals.dark, HmmNeutrals.light] {
            XCTAssertGreaterThan(HmmRGB.contrast(neutrals.text, neutrals.background), 12)
            XCTAssertGreaterThan(HmmRGB.contrast(neutrals.text2, neutrals.background), 4.5)
        }
    }

    func testChromeIsNeverMoreSaturatedThanTheAccent() {
        for accent in HmmAccent.allCases {
            for neutrals in [HmmNeutrals.dark, HmmNeutrals.light] {
                for color in [neutrals.background, neutrals.surface, neutrals.surface2, neutrals.line, neutrals.text, neutrals.text2] {
                    XCTAssertLessThan(color.saturation, accent.rgb.saturation)
                }
            }
        }
    }

    func testSpacingIsOnTheFourPointGrid() {
        for value in HmmSpacing.all {
            XCTAssertEqual(value.truncatingRemainder(dividingBy: 4), 0)
        }
    }

    func testMotionTokens() {
        XCTAssertLessThan(HmmSpring.snappy.response, HmmSpring.standard.response)
        XCTAssertLessThan(HmmSpring.standard.response, HmmSpring.gentle.response)
        XCTAssertEqual(HmmSpring.reducedMotionFade, 0.2)
    }

    func testSliderMappingIsRelativeAndClamped() {
        let mapping = HmmSliderMapping(range: 0 ... 1, length: 200)
        XCTAssertEqual(mapping.fraction(of: 0.5), 0.5)
        XCTAssertEqual(mapping.value(start: 0.5, dy: -100, dx: 0), 1, accuracy: 1e-9)
        XCTAssertEqual(mapping.value(start: 0.5, dy: 100, dx: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(mapping.value(start: 0.5, dy: -40, dx: 100), 0.55, accuracy: 1e-9, "sideways = four times finer")
        XCTAssertEqual(mapping.value(start: 0.9, dy: -400, dx: 0), 1)
    }

    func testGestureGuideListsTheSixGestures() {
        XCTAssertEqual(HmmUniversalGesture.allCases.count, 6)
        XCTAssertEqual(HmmUniversalGesture.undo.gesture, "Two-finger tap")
    }
}
