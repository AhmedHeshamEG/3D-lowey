import CoreGraphics
import Foundation
import LoweyCore
@testable import LoweyEngine
import UIKit
import XCTest

/// Pixel checks shared by the render and export tests (a blank frame, two frames that differ, one pixel's colour).
enum ImageChecks {
    /// Mean absolute difference of two same-sized images, 0…1.
    static func difference(_ a: CGImage, _ b: CGImage) -> Double {
        let x = GoldenImage.rgba(a)
        let y = GoldenImage.rgba(b)
        guard x.count == y.count, !x.isEmpty else { return 1 }
        var sum = 0
        for index in stride(from: 0, to: x.count, by: 4) {
            sum += abs(Int(x[index]) - Int(y[index])) + abs(Int(x[index + 1]) - Int(y[index + 1])) + abs(Int(x[index + 2]) - Int(y[index + 2]))
        }
        return Double(sum) / Double(x.count / 4 * 3 * 255)
    }

    /// The colour at (x, y) given as fractions of the width and height from the top-left, 0…1 per channel.
    static func rgb(_ image: CGImage, x: Double, y: Double) -> (r: Double, g: Double, b: Double) {
        let bytes = GoldenImage.rgba(image)
        let px = min(max(Int(x * Double(image.width)), 0), image.width - 1)
        let py = min(max(Int(y * Double(image.height)), 0), image.height - 1)
        let index = (py * image.width + px) * 4
        guard index + 2 < bytes.count else { return (0, 0, 0) }
        return (Double(bytes[index]) / 255, Double(bytes[index + 1]) / 255, Double(bytes[index + 2]) / 255)
    }

    /// Mean brightness of the pixels inside a rectangle given in fractions of the frame, 0…1.
    static func brightness(_ image: CGImage, in rect: CGRect) -> Double {
        let bytes = GoldenImage.rgba(image)
        var sum = 0.0
        var count = 0.0
        let x0 = Int(rect.minX * CGFloat(image.width)), x1 = Int(rect.maxX * CGFloat(image.width))
        let y0 = Int(rect.minY * CGFloat(image.height)), y1 = Int(rect.maxY * CGFloat(image.height))
        for y in stride(from: y0, to: y1, by: 2) {
            for x in stride(from: x0, to: x1, by: 2) {
                let index = (y * image.width + x) * 4
                sum += Double(bytes[index]) + Double(bytes[index + 1]) + Double(bytes[index + 2])
                count += 3
            }
        }
        return count > 0 ? sum / count / 255 : 0
    }

    static func temporaryFolder(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lowey-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// Builds small documents for the render tests.
enum TestDocuments {
    /// A scene with a camera at `position` looking along `rotation`, holding `objects`.
    static func document(_ name: String, objects: [SceneObject], camera position: Vec3, rotation: Quat = .identity,
                         fieldOfView: Double = 40, look: Look = .default) -> Document {
        var scene = Scene(id: SceneID(raw: name), name: name)
        scene.look = look
        var camera = SceneObject(id: "cam", name: "Camera", kind: .camera, transform: Transform(position: position, rotation: rotation))
        camera[.fieldOfView] = .float(fieldOfView)
        for object in objects + [camera] {
            scene.objects[object.id] = object
        }
        scene.roots = (objects + [camera]).filter { $0.parent == nil }.map(\.id)
        scene.activeCamera = camera.id
        return Document(project: ProjectInfo(id: "p", name: name), scene: scene)
    }

    /// A one-off export session for a document (models from `models`, nothing from a library unless `catalog` says).
    @MainActor
    static func session(_ document: Document, catalog: AssetCatalog = .empty, models: ModelLibrary = ModelLibrary()) throws -> ExportSession {
        try ExportSession(document: document, catalog: catalog, device: RenderDevice.sharedDevice(), models: models)
    }

    static func opening() throws -> Document {
        let (info, scenes) = try EnigmaSample.buildWithOpening()
        return try Document(project: info, scene: XCTUnwrap(scenes.last))
    }

    static func story() throws -> Document {
        let (info, scenes) = try EnigmaSample.buildFull()
        return try Document(project: info, scene: XCTUnwrap(scenes.last))
    }
}
