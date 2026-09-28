import LoweyCore
@testable import LoweyRender
import UIKit
import XCTest

/// Phase 4 on the simulator: the blob characters (the house style) as the app renders them.
@MainActor
final class Phase4Tests: XCTestCase {
    private func attach(_ image: CGImage, name: String) {
        let attachment = XCTAttachment(image: UIImage(cgImage: image))
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Hesham, Newton and Einstein side by side, then Hesham talking and blinking.
    func testBlobCharactersRender() async throws {
        var scene = CoreScene(id: "blobs", name: "Blobs")
        var look = Look.default.applying(.night)
        look.post = PostSettings()
        scene.look = look
        var ids = IDFactory.sequential("b")
        var heshamRoot: ObjectID?
        for (index, recipe) in [Likeness.recipe(for: "newton"), .hesham, Likeness.recipe(for: "einstein")].compactMap({ $0 }).enumerated() {
            let build = BlobCharacter.build(recipe, ids: &ids)
            for object in build.fragment.objects {
                scene.objects[object.id] = object
            }
            let root = build.fragment.roots[0]
            scene.objects[root]?.transform.position = Vec3(Double(index - 1) * 1.7, 0, 0)
            scene.roots.append(root)
            if recipe == .hesham { heshamRoot = root }
        }
        var cam = SceneObject(id: "cam", name: "Camera", kind: .camera,
                              transform: LoweyCore.Transform(position: Vec3(0, 1.2, 6.2), rotation: Quat(angle: -0.04, axis: .unitX)))
        cam[.fieldOfView] = .float(38)
        scene.objects[cam.id] = cam
        scene.roots.append(cam.id)
        scene.activeCamera = cam.id
        let document = Document(project: ProjectInfo(id: "p", name: "Blobs"), scene: scene)
        let trio = try await VideoExporter(document: document, library: nil, rigs: RigCache()).images(at: 0, framings: [.landscape], longSide: 1280)
        attach(trio[0], name: "blobs-newton-hesham-einstein")

        // Expressions: each keyed at 0 and seen once settled, plus one caught mid-overshoot.
        let root = try XCTUnwrap(heshamRoot)
        var close = document
        close.scene.look?.lighting = Look.default.applying(.goldenHour).lighting
        close.scene.objects["cam"]?.transform = LoweyCore.Transform(position: Vec3(0, 1.15, 2.9))
        var sheet: [CGImage] = []
        for expression in [FaceExpression.neutral, .happy, .laugh, .surprised, .shocked, .angry, .sad, .wink] {
            var posed = close
            var ids = IDFactory.sequential("e")
            posed.scene.timeline = expression.keyed(on: root, at: 0, in: posed.scene.timeline, ids: &ids)
            posed.scene.objects[root]?[.autoBlink] = .bool(false)
            let frame = try await VideoExporter(document: posed, library: nil, rigs: RigCache()).images(at: 2, framings: [.landscape], longSide: 640)
            attach(frame[0], name: "blob-face-\(expression.rawValue)")
            sheet.append(frame[0])
        }
        XCTAssertGreaterThan(Self.difference(sheet[0], sheet[4]), 0.005, "shocked doesn't look like neutral")
        var hit = close
        var hitIDs = IDFactory.sequential("h")
        hit.scene.timeline = FaceExpression.neutral.keyed(on: root, at: 0, in: hit.scene.timeline, ids: &hitIDs)
        hit.scene.timeline = FaceExpression.shocked.keyed(on: root, at: 1, in: hit.scene.timeline, ids: &hitIDs)
        let overshoot = try await VideoExporter(document: hit, library: nil, rigs: RigCache()).images(at: 1.12, framings: [.landscape], longSide: 640)
        attach(overshoot[0], name: "blob-face-shocked-overshoot")
    }

    static func difference(_ a: CGImage, _ b: CGImage) -> Double {
        func bytes(_ image: CGImage) -> [UInt8] {
            var data = [UInt8](repeating: 0, count: 64 * 36 * 4)
            let context = CGContext(data: &data, width: 64, height: 36, bitsPerComponent: 8, bytesPerRow: 64 * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: 64, height: 36))
            return data
        }
        let x = bytes(a)
        let y = bytes(b)
        return Double(zip(x, y).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }) / Double(x.count * 255)
    }
}
