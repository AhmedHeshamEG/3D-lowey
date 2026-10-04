import CoreGraphics
import LoweyCore
@testable import LoweyEngine
import XCTest

/// The hovering Pencil's point is drawn by the renderer in the stage's own frame, exactly under the tip, the same
/// size wherever the camera is; the outline appears only when asked for (resizing).
@MainActor
final class PointerTests: XCTestCase {
    private static let size = (width: 640, height: 360)

    private func render(pointer: PencilPointer?, distance: Double = 6) async throws -> CGImage {
        let device = try RenderDevice.sharedDevice()
        let models = ModelLibrary()
        let frames = try FrameRenderer(device: device, models: models)
        var document = TestScenes.lookCheck(look: LookPreset.clay.id, mood: .day)
        document.scene.viewpoint.distance = distance
        let builder = ShotBuilder(document: document, catalog: .empty, models: models)
        var request = builder.request(at: 0, framing: .landscape, size: CGSize(width: Self.size.width, height: Self.size.height), frameIndex: 0)
        var editor = EditorScene()
        editor.showsGrid = false
        editor.pointer = pointer
        request.editor = editor
        return try await frames.image(request, width: Self.size.width, height: Self.size.height)
    }

    func testThePointSitsExactlyUnderTheTip() async throws {
        let tip = CGPoint(x: 0.25, y: 0.4)
        let plain = try await render(pointer: nil)
        let marked = try await render(pointer: PencilPointer(location: tip, dotRadius: 3 / 360))
        let centre = ImageChecks.rgb(marked, x: tip.x, y: tip.y)
        XCTAssertGreaterThan(min(centre.r, centre.g, centre.b), 0.85, "a light point at the tip")
        let away = CGRect(x: 0.35, y: 0.5, width: 0.3, height: 0.3)
        XCTAssertEqual(ImageChecks.brightness(plain, in: away), ImageChecks.brightness(marked, in: away), accuracy: 0.002, "nothing else changes")
        let changed = GoldenImage().compare(plain, marked).differentFraction
        XCTAssertLessThan(changed, 0.002, "a small point, not a ring")
        XCTAssertGreaterThan(changed, 0, "it is drawn")
    }

    func testThePointKeepsItsSizeAndTheOutlineIsOnlyForResizing() async throws {
        let tip = CGPoint(x: 0.5, y: 0.5)
        let near = try await GoldenImage().compare(render(pointer: nil, distance: 3), render(pointer: .init(location: tip, dotRadius: 3 / 360),
                                                                                             distance: 3)).differentFraction
        let far = try await GoldenImage().compare(render(pointer: nil, distance: 20), render(pointer: .init(location: tip, dotRadius: 3 / 360),
                                                                                             distance: 20)).differentFraction
        XCTAssertEqual(near, far, accuracy: 0.0004, "the same size on screen however far the scene is")
        let outlined = try await GoldenImage().compare(render(pointer: nil), render(pointer: .init(location: tip, dotRadius: 3 / 360,
                                                                                                   outlineRadius: 60 / 360))).differentFraction
        XCTAssertGreaterThan(outlined, near * 3, "the outline shows while resizing")
    }
}
