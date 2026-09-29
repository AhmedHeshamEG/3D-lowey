import LoweyCore
@testable import LoweyRender
import UIKit
import XCTest

/// v1.4 on the simulator: media cards standing in the world.
@MainActor
final class Phase5Tests: XCTestCase {
    private func attach(_ image: CGImage, name: String) {
        let attachment = XCTAttachment(image: UIImage(cgImage: image))
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// A 64 × 64 picture: red on top, blue below (so an upside-down card shows).
    private func picture() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(UIColor.blue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
        context.setFillColor(UIColor.red.cgColor)
        context.fill(CGRect(x: 0, y: 32, width: 64, height: 32))
        return try XCTUnwrap(context.makeImage())
    }

    private func rgb(_ image: CGImage, x: Double, y: Double) -> (r: Double, g: Double, b: Double) {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        // Draw the image so the wanted pixel (x, y from the top-left, 0…1) lands on the 1 × 1 context.
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        context?.draw(image, in: CGRect(x: -x * width, y: -(1 - y) * height, width: width, height: height))
        return (Double(pixel[0]) / 255, Double(pixel[1]) / 255, Double(pixel[2]) / 255)
    }

    func testAPictureCardStandsUprightInTheWorld() async throws {
        var scene = CoreScene(id: "cards", name: "Cards")
        var look = Look.default
        look.post = PostSettings()
        scene.look = look
        var card = SceneObject(id: "card", name: "Chart", kind: .card(CardRecipe(image: "chart.png", aspect: 1)))
        card[.color] = .color(.rgba(RGBA(0.96, 0.95, 0.92)))
        scene.objects[card.id] = card
        scene.roots.append(card.id)
        var cam = SceneObject(id: "cam", name: "Camera", kind: .camera,
                              transform: LoweyCore.Transform(position: Vec3(0, 0.53, 2.2)))
        cam[.fieldOfView] = .float(40)
        scene.objects[cam.id] = cam
        scene.roots.append(cam.id)
        scene.activeCamera = cam.id
        let document = Document(project: ProjectInfo(id: "p", name: "Cards"), scene: scene)
        let image = try picture()
        let exporter = VideoExporter(document: document, library: nil, rigs: RigCache())
        exporter.overlayImage = { $0 == "chart.png" ? image : nil }
        let frame = try await exporter.images(at: 0, framings: [.landscape], longSide: 640)[0]
        attach(frame, name: "card-picture")
        let top = rgb(frame, x: 0.5, y: 0.38)
        let bottom = rgb(frame, x: 0.5, y: 0.62)
        XCTAssertGreaterThan(top.r, top.b + 0.3, "the top of the picture is on top (red): \(top)")
        XCTAssertGreaterThan(bottom.b, bottom.r + 0.3, "and the bottom below (blue): \(bottom)")

        // Seen from the side it's a thin slab, not a flat sticker on the frame.
        var side = document
        side.scene.objects["cam"]?.transform = LoweyCore.Transform(position: Vec3(2.2, 0.53, 0.4), rotation: Quat(angle: .pi / 2 * 0.92, axis: .unitY))
        let sideExporter = VideoExporter(document: side, library: nil, rigs: RigCache())
        sideExporter.overlayImage = { $0 == "chart.png" ? image : nil }
        try await attach(sideExporter.images(at: 0, framings: [.landscape], longSide: 640)[0], name: "card-from-the-side")
    }
}
