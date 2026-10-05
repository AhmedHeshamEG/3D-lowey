import CoreGraphics
import LoweyCore
@testable import LoweyEngine
import XCTest

/// The section view cuts the stage's frame at a plane (the cut faces drawn flat), and never the export's.
@MainActor
final class SectionViewTests: XCTestCase {
    private static let size = (width: 640, height: 360)

    private func render(section: SectionPlane?) async throws -> CGImage {
        let device = try RenderDevice.sharedDevice()
        let models = ModelLibrary()
        let frames = try FrameRenderer(device: device, models: models)
        let document = TestScenes.lookCheck(look: LookPreset.clay.id, mood: .day)
        let builder = ShotBuilder(document: document, catalog: .empty, models: models)
        var request = builder.request(at: 0, framing: .landscape, size: CGSize(width: Self.size.width, height: Self.size.height), frameIndex: 0)
        var editor = EditorScene()
        editor.showsGrid = false
        editor.section = section
        request.editor = editor
        return try await frames.image(request, width: Self.size.width, height: Self.size.height)
    }

    func testTheCutRemovesWhatsBeyondThePlaneAndLeavesTheRest() async throws {
        let whole = try await render(section: nil)
        // Cut away everything above half a metre: the tops of the shapes go, the ground stays.
        let cut = try await render(section: SectionPlane(axis: .y, through: Vec3(0, 0.5, 0)))
        let changed = GoldenImage().compare(whole, cut).differentFraction
        XCTAssertGreaterThan(changed, 0.01, "the cut shows")
        XCTAssertLessThan(changed, 0.6, "only the part beyond the plane changes")
        let bottom = CGRect(x: 0, y: 0.92, width: 1, height: 0.08)
        XCTAssertEqual(ImageChecks.brightness(whole, in: bottom), ImageChecks.brightness(cut, in: bottom), accuracy: 0.02, "the ground isn't cut")
        // A plane beyond everything cuts nothing.
        let none = try await render(section: SectionPlane(axis: .y, through: Vec3(0, 50, 0)))
        XCTAssertLessThan(GoldenImage().compare(whole, none).differentFraction, 0.001)
        GoldenImage().attach(cut, name: "section-view")
    }
}
