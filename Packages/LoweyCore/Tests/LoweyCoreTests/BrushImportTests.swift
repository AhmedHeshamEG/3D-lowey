import Foundation
@testable import LoweyCore
import XCTest

/// The import fixtures are made by `Tools/make_brush_fixtures.py` in Procreate's and Photoshop's formats (as found in
/// real files for the M5 spike, D-141) from pictures of our own.
final class BrushImportTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let root = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        return try Data(contentsOf: root.appendingPathComponent("Brushes").appendingPathComponent(name))
    }

    private func ids() -> () -> String {
        var next = 0
        return {
            next += 1
            return "imported-\(next)"
        }
    }

    func testAProcreateBrushSetImports() throws {
        let result = try BrushFileImport.read(fixture("Sample.brushset"), fileName: "Sample.brushset", newID: ids())
        XCTAssertEqual(result.setName, "Sample Set")
        XCTAssertEqual(result.brushes.map(\.name), ["Leaf Stamp", "Hard Pen"])
        XCTAssertEqual(result.brushes.map(\.id), ["imported-1", "imported-2"])

        let leaf = result.brushes[0]
        XCTAssertEqual(leaf.about.origin, .procreate)
        XCTAssertEqual(leaf.about.author, "studio h.")
        let shape = try XCTUnwrap(leaf.shape.source.imageKey)
        let grain = try XCTUnwrap(leaf.grain.source?.imageKey)
        XCTAssertNotNil(result.images[shape])
        XCTAssertNotNil(result.images[grain])
        XCTAssertEqual(leaf.stroke.spacing, 0.02 + 0.36 * 1.98, accuracy: 1e-6)
        XCTAssertEqual(leaf.shape.rotationJitter, 0.5, accuracy: 1e-6)
        XCTAssertEqual(leaf.grain.movement, .rolling)
        XCTAssertEqual(leaf.dynamics.sizeJitter, 0.2, accuracy: 1e-6)
        XCTAssertEqual(leaf.dynamics.pressureCurve.points.count, 3)
        XCTAssertEqual(leaf.dynamics.pressureCurve.value(at: 0.4), 0.7, accuracy: 1e-6)

        let pen = result.brushes[1]
        XCTAssertEqual(pen.shape.source, .builtIn(.hardRound), "a Procreate bundled tip becomes the nearest built-in")
        XCTAssertNil(pen.grain.source)
        XCTAssertEqual(pen.stroke.taperStart, 0.2, accuracy: 1e-6)
        XCTAssertEqual(pen.stroke.streamline, 0.5, accuracy: 1e-6)
    }

    func testASingleProcreateBrushImports() throws {
        // A `.brush` is one brush folder's contents at the top of the zip.
        let set = try ZipReader.entries(fixture("Sample.brushset"))
        let single = ZipWriter.storedArchive(set.filter { $0.name.hasPrefix("LEAF-0001/") }
            .map { (String($0.name.dropFirst("LEAF-0001/".count)), $0.data) })
        let result = try BrushFileImport.read(single, fileName: "Leaf.brush", newID: ids())
        XCTAssertEqual(result.setName, "Leaf")
        XCTAssertEqual(result.brushes.map(\.name), ["Leaf Stamp"])
    }

    func testAPhotoshopBrushFileImportsItsSampledTips() throws {
        let result = try BrushFileImport.read(fixture("Sample.abr"), fileName: "Sample.abr", newID: ids())
        XCTAssertEqual(result.setName, "Sample")
        XCTAssertEqual(result.brushes.map(\.name), ["Soft Dot", "Checker Stamp"])
        XCTAssertEqual(result.brushes.map(\.stroke.spacing), [0.15, 0.8])
        XCTAssertTrue(result.brushes.allSatisfy { $0.about.origin == .photoshop })
        for brush in result.brushes {
            let key = try XCTUnwrap(brush.shape.source.imageKey)
            let png = try XCTUnwrap(result.images[key])
            XCTAssertEqual(BrushKey.imageKey(for: png), key)
        }
        // The PackBits tip comes back the size it was drawn.
        let checker = try XCTUnwrap(result.images[result.brushes[1].shape.source.imageKey ?? ""])
        XCTAssertEqual(checker[16 ..< 24].reduce(0) { $0 << 8 | Int($1) }, 80 << 32 | 40)
    }

    func testOldPhotoshopVersionTwoImports() throws {
        // Version 2: a count, then a sampled brush with spacing, a name, short and long bounds and raw rows.
        var bytes: [UInt8] = [0, 2, 0, 1]
        var body: [UInt8] = [0, 0, 0, 0, 0, 30]
        let name = Array("Old\0".utf16).flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] }
        body += [0, 0, 0, 4] + name + [1] + [UInt8](repeating: 0, count: 8)
        body += [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 3, 0, 8, 0]
        body += [255, 128, 0, 255, 128, 0]
        bytes += [0, 2] + withUnsafeBytes(of: UInt32(body.count).bigEndian, Array.init) + body
        let result = try ABRBrushImport.read(Data(bytes), fileName: "Old.abr", newID: ids())
        XCTAssertEqual(result.brushes.map(\.name), ["Old"])
        XCTAssertEqual(result.brushes[0].stroke.spacing, 0.3, accuracy: 1e-9)
    }

    func testABrushSetFileRoundTrips() throws {
        let imported = try BrushFileImport.read(fixture("Sample.brushset"), fileName: "Sample.brushset", newID: ids())
        let file = try BrushSetFile.write(name: "To share", brushes: imported.brushes) { imported.images[$0] }
        let back = try BrushFileImport.read(file, fileName: "To share.\(BrushSetFile.fileExtension)", newID: { "again" })
        XCTAssertEqual(back.setName, "To share")
        XCTAssertEqual(back.brushes.count, 2)
        XCTAssertEqual(back.brushes[0].shape, imported.brushes[0].shape)
        XCTAssertEqual(back.brushes[0].dynamics, imported.brushes[0].dynamics)
        XCTAssertEqual(back.brushes[0].about.origin, .procreate)
        XCTAssertEqual(back.images, imported.images)
        XCTAssertTrue(back.notes.isEmpty, "\(back.notes)")
    }

    func testASharedSetMissingAPictureFallsBack() throws {
        var brush = BuiltInBrushes.charcoal
        brush.shape.source = .image("brushes/gone.png")
        let file = try BrushSetFile.write(name: "Lossy", brushes: [brush]) { _ in nil }
        let back = try BrushSetFile.read(file, fileName: "Lossy.maquettebrushes", newID: { "n" })
        XCTAssertEqual(back.brushes[0].shape.source, .builtIn(.hardRound))
        XCTAssertEqual(back.notes.count, 1)
    }

    func testDamagedFilesFailCleanly() throws {
        XCTAssertThrowsError(try BrushFileImport.read(Data("hello".utf8), fileName: "x.brushset", newID: ids()))
        XCTAssertThrowsError(try BrushFileImport.read(Data([0, 6, 0, 2, 1]), fileName: "x.abr", newID: ids()))
        XCTAssertThrowsError(try BrushFileImport.read(Data(), fileName: "x.png", newID: ids()))
        let real = try fixture("Sample.abr")
        for cut in stride(from: 4, to: real.count, by: 97) {
            _ = try? ABRBrushImport.read(real.prefix(cut), fileName: "cut.abr", newID: ids())
        }
        let set = try fixture("Sample.brushset")
        let archive = try XCTUnwrap(ZipReader.entries(set).first { $0.name == "LEAF-0001/Brush.archive" }?.data)
        for cut in stride(from: 40, to: archive.count, by: 53) {
            _ = try? BinaryPlist.read(archive.prefix(cut))
        }
    }

    func testBinaryPlistsReadEveryType() throws {
        let archive = try XCTUnwrap(ZipReader.entries(fixture("Sample.brushset")).first { $0.name == "brushset.plist" }?.data)
        let plist = try BinaryPlist.read(archive)
        XCTAssertEqual(plist["name"]?.string, "Sample Set")
        XCTAssertEqual(plist["brushes"]?.array?.count, 2)
        XCTAssertThrowsError(try BinaryPlist.read(Data("bplist00".utf8)))
    }
}
