@testable import HmmPerception
import XCTest

final class PerceptionTests: XCTestCase {
    func testContactSheetLayout() {
        let six = ContactSheetLayout(count: 6, aspect: 16.0 / 9.0, maxWidth: 2048)
        XCTAssertEqual(six.columns, 3)
        XCTAssertEqual(six.rows, 2)
        XCTAssertLessThanOrEqual(six.width, 2048)
        XCTAssertEqual(six.frame(4).x, six.frame(1).x)
        XCTAssertGreaterThan(six.frame(4).y, six.frame(1).y)
        XCTAssertEqual(six.caption(0).y, six.frame(0).maxY)
        let two = ContactSheetLayout(count: 2, aspect: 1, maxWidth: 1000)
        XCTAssertEqual(two.columns, 2)
        XCTAssertEqual(ContactSheetLayout(count: 12, aspect: 1, maxWidth: 1000).columns, 4)
    }

    func testMarksStayInsideAndApart() {
        let boxes = [
            PerceptionRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2),
            PerceptionRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1), // same centre, smaller: moves
            PerceptionRect(x: 0.98, y: 0.98, width: 0.02, height: 0.02) // in the corner: clamped
        ]
        let marks = MarkLayout.place(boxes)
        XCTAssertEqual(marks.map(\.number), [1, 2, 3])
        XCTAssertEqual(marks[0].x, 0.5, accuracy: 1e-9)
        XCTAssertNotEqual(marks[1].x == 0.5 && marks[1].y == 0.5, true)
        for mark in marks {
            XCTAssertTrue((0 ... 1).contains(mark.x) && (0 ... 1).contains(mark.y))
        }
        XCTAssertLessThan(marks[2].x, 0.99)
    }

    func testValueImageMeasuresLightness() {
        XCTAssertEqual(ValueImage.lightness(red: 1, green: 1, blue: 1), 100, accuracy: 0.01)
        XCTAssertEqual(ValueImage.lightness(red: 0, green: 0, blue: 0), 0, accuracy: 0.01)
        XCTAssertEqual(ValueImage.lightness(red: 0.5, green: 0.5, blue: 0.5), 53.4, accuracy: 0.2)
        // Left half white, right half black.
        var pixels: [UInt8] = []
        for _ in 0 ..< 4 {
            pixels += [255, 255, 255, 255, 255, 255, 255, 255, 0, 0, 0, 255, 0, 0, 0, 255]
        }
        let image = ValueImage(pixels: pixels, width: 4, height: 4)
        XCTAssertEqual(image.meanLightness(in: PerceptionRect(x: 0, y: 0, width: 0.5, height: 1)) ?? 0, 100, accuracy: 0.01)
        XCTAssertEqual(image.meanLightness(in: PerceptionRect(x: 0.5, y: 0, width: 0.5, height: 1)) ?? 100, 0, accuracy: 0.01)
        XCTAssertEqual(image.meanLightness { x, _ in x == 0 } ?? 0, 100, accuracy: 0.01)
        let blurred = image.blurred(radius: 1)
        XCTAssertLessThan(blurred.lightness[1], 100)
        XCTAssertGreaterThan(blurred.lightness[2], 0)
        XCTAssertNil(image.meanLightness(in: PerceptionRect(x: 2, y: 2, width: 1, height: 1)))
    }

    func testSafeZones() {
        let centred = PerceptionRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
        XCTAssertEqual(SafeZones.unsafeFraction(centred, shape: .landscape), 0)
        let underCaption = PerceptionRect(x: 0.3, y: 0.85, width: 0.3, height: 0.1)
        XCTAssertGreaterThan(SafeZones.unsafeFraction(underCaption, shape: .vertical), 0.9)
        XCTAssertTrue(SafeZones.covered(.landscape).isEmpty)
        XCTAssertEqual(SafeZones.covered(.vertical).count, 3)
    }

    func testReportPutsTheSummaryFirst() throws {
        struct Numbers: Codable, Sendable { var coverage: Double }
        let report = PerceptionReport(summary: "The lamp fills 12% of the frame.", data: Numbers(coverage: 0.12))
        let text = try String(decoding: report.json(), as: UTF8.self)
        XCTAssertTrue(text.contains("\"summary\":\"The lamp fills 12% of the frame.\""))
    }
}
