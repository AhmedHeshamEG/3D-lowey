import Foundation
@testable import LoweyCore
import XCTest

/// 3D printing: STL and 3MF out and in, the printability check and repair, wall thickness, beds; and the precision
/// tools (snapping, kept dimensions, the section plane).
final class PrintingTests: XCTestCase {
    private let mm = 0.001

    /// M3's acceptance part: a 40 × 20 × 10 mm block with a 6 mm hole through it.
    private func m3Block() throws -> EditableMesh {
        let block = EditableMesh.box(min: .zero, max: Vec3(40 * mm, 10 * mm, 20 * mm))
        let hole = EditableMesh.cylinder(base: Vec3(20 * mm, -1 * mm, 10 * mm), radius: 3 * mm, height: 12 * mm, segments: 48)
        return try MeshBoolean.combine(block, hole, .subtract)
    }

    private func exportMesh(_ mesh: EditableMesh, name: String = "Block", at position: Vec3 = .zero) -> ExportMesh {
        ExportMesh(name: name, transform: Transform(position: position), mesh: mesh.renderMesh(), color: RGBA(1, 0.5, 0))
    }

    private func solid(from data: MeshData) -> EditableMesh {
        MeshBuilder.mesh(from: data)
    }

    // MARK: STL

    /// Acceptance: the STL of the M3 block is watertight. `ACCEPTANCE_DIR` also writes it out for CI's slicer-side
    /// validator (trimesh), which checks it the way a slicer would.
    func testTheM3BlockExportsAWatertightSTL() throws {
        let block = try m3Block()
        let stl = STLFile.binary([exportMesh(block)], name: "M3 block")
        XCTAssertEqual(stl.count, 84 + 50 * block.triangulated().triangles.count)
        let back = try solid(from: STLFile.read(stl))
        XCTAssertTrue(MeshTopology(back).isClosedManifold, "every edge shared by two triangles")
        XCTAssertTrue(MeshBoolean.isSolid(back), "Manifold reads it as a solid")
        XCTAssertEqual(back.volume, block.volume, accuracy: block.volume * 1e-5)
        let size = try XCTUnwrap(back.bounds).size
        XCTAssertTrue(size.isApproximately(Vec3(40 * mm, 10 * mm, 20 * mm), tolerance: 1e-6), "millimetres in, metres back")
        if let directory = ProcessInfo.processInfo.environment["ACCEPTANCE_DIR"] {
            let folder = URL(fileURLWithPath: directory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try stl.write(to: folder.appendingPathComponent("m3-block.stl"))
            try ThreeMFFile.data([exportMesh(block)]).write(to: folder.appendingPathComponent("m3-block.3mf"))
        }
    }

    func testSTLIsMillimetresWithZUp() throws {
        let tall = EditableMesh.box(min: .zero, max: Vec3(10 * mm, 30 * mm, 20 * mm))
        let triangles = STLFile.worldTriangles([exportMesh(tall)])
        let zs = triangles.flatMap { [$0.0.z, $0.1.z, $0.2.z] }
        XCTAssertEqual(zs.max() ?? 0, 30, accuracy: 1e-4, "the scene's height is the printer's z, in millimetres")
        XCTAssertEqual(zs.min() ?? 0, 0, accuracy: 1e-4)
    }

    func testASCIISTLReads() throws {
        let ascii = """
        solid tet
        facet normal 0 0 -1
        outer loop
        vertex 0 0 0
        vertex 0 10 0
        vertex 10 0 0
        endloop
        endfacet
        facet normal 0 -1 0
        outer loop
        vertex 0 0 0
        vertex 10 0 0
        vertex 0 0 10
        endloop
        endfacet
        facet normal 1 1 1
        outer loop
        vertex 10 0 0
        vertex 0 10 0
        vertex 0 0 10
        endloop
        endfacet
        facet normal -1 0 0
        outer loop
        vertex 0 0 0
        vertex 0 0 10
        vertex 0 10 0
        endloop
        endfacet
        endsolid tet
        """
        let mesh = try STLFile.read(Data(ascii.utf8))
        XCTAssertEqual(mesh.positions.count, 4, "shared corners welded")
        let tetrahedron = solid(from: mesh)
        XCTAssertTrue(MeshTopology(tetrahedron).isClosedManifold)
        XCTAssertEqual(tetrahedron.volume, 1000.0 / 6 * 1e-9, accuracy: 1e-12, "files hold Float")
        XCTAssertThrowsError(try STLFile.read(Data("solid nothing\nendsolid".utf8)))
    }

    // MARK: 3MF

    func test3MFRoundTripKeepsPartsColoursAndSize() throws {
        let block = try m3Block()
        let peg = EditableMesh.cylinder(base: .zero, radius: 2 * mm, height: 15 * mm, segments: 24)
        var red = exportMesh(peg, name: "Peg & pin", at: Vec3(60 * mm, 0, 0))
        red.color = RGBA(1, 0, 0)
        let data = ThreeMFFile.data([exportMesh(block), red])
        let entries = try ZipReader.entries(data)
        XCTAssertEqual(Set(entries.map(\.name)), ["[Content_Types].xml", "_rels/.rels", "3D/3dmodel.model"])
        let model = try ThreeMFFile.read(data)
        XCTAssertEqual(model.parts.count, 2)
        XCTAssertEqual(model.parts[1].name, "Peg & pin")
        XCTAssertEqual(model.materials[model.parts[1].material].baseColor.r, 1, accuracy: 1e-9)
        let back = solid(from: model.parts[0].mesh)
        XCTAssertTrue(MeshTopology(back).isClosedManifold)
        XCTAssertEqual(back.volume, block.volume, accuracy: block.volume * 1e-5)
        XCTAssertEqual(try XCTUnwrap(solid(from: model.parts[1].mesh).bounds).center.x, 60 * mm, accuracy: 1e-6)
    }

    func testADeflated3MFFromAnotherAppReads() throws {
        let model = try ThreeMFFile.read(XCTUnwrap(Data(base64Encoded: Self.deflated3MF)))
        XCTAssertEqual(model.parts.count, 1)
        XCTAssertEqual(model.parts[0].name, "Tet")
        XCTAssertEqual(model.materials[0].baseColor.r, 1, accuracy: 1e-9)
        let tetrahedron = solid(from: model.parts[0].mesh)
        XCTAssertTrue(MeshTopology(tetrahedron).isClosedManifold)
        XCTAssertEqual(tetrahedron.volume, 1000.0 / 6 * 1e-9, accuracy: 1e-12, "files hold Float")
        // The build item moves it 5 mm along the printer's x.
        XCTAssertEqual(try XCTUnwrap(tetrahedron.bounds).min.x, 5 * mm, accuracy: 1e-9)
    }

    func testInflate() throws {
        let text = "Maquette prints: " + String(repeating: "0123456789abcdef", count: 40) + " the end.\n"
        let raw = try XCTUnwrap(Data(base64Encoded: "800sLE0tKUlVKCjKzCsptlIwMDQyNjE1M7ewTExKTklNG+WP8unJVyjJSFVIzUvR4wIA"))
        XCTAssertEqual(try String(data: Inflate.decompress(raw), encoding: .utf8), text)
        let fixed = try XCTUnwrap(Data(base64Encoded: "y0jNyclXyECQAA=="))
        XCTAssertEqual(try String(data: Inflate.decompress(fixed), encoding: .utf8), "hello hello hello")
        XCTAssertThrowsError(try Inflate.decompress(Data([0xFF, 0xFF, 0xFF])))
    }

    // MARK: Check and repair

    func testASolidPartIsReadyToPrint() throws {
        let report = try PrintCheck.check(m3Block(), bed: PrintBed.standard)
        XCTAssertTrue(report.isWatertight)
        XCTAssertTrue(report.isReady, report.problems.joined(separator: " "))
        XCTAssertEqual(try XCTUnwrap(report.thinnestWall), 7 * mm, accuracy: 0.5 * mm, "from the hole to the nearest side")
    }

    func testAHoleIsFoundAndClosed() throws {
        let box = EditableMesh.box(min: .zero, max: Vec3(20 * mm, 20 * mm, 20 * mm))
        let open = EditableMesh(vertices: box.vertices, faces: Array(box.faces.dropLast()))
        let report = PrintCheck.check(open, bed: nil)
        XCTAssertFalse(report.isWatertight)
        XCTAssertEqual(report.openEdges, 4)
        XCTAssertFalse(report.problems.isEmpty)
        let repaired = PrintCheck.repair(open)
        XCTAssertTrue(PrintCheck.check(repaired, bed: nil).isWatertight)
        XCTAssertEqual(repaired.volume, box.volume, accuracy: 1e-15)
    }

    func testInsideOutFacesAreTurnedBack() throws {
        let box = EditableMesh.box(min: .zero, max: Vec3(20 * mm, 20 * mm, 20 * mm))
        var faces = box.faces
        faces[2] = EditableMesh.Face(Array(faces[2].outline.reversed()))
        let flipped = EditableMesh(vertices: box.vertices, faces: faces)
        XCTAssertFalse(PrintCheck.check(flipped, bed: nil).isWatertight)
        let inverted = EditableMesh(vertices: box.vertices, faces: box.faces.map { EditableMesh.Face(Array($0.outline.reversed())) })
        XCTAssertTrue(PrintCheck.check(inverted, bed: nil).insideOut)
        for broken in [flipped, inverted] {
            let repaired = PrintCheck.repair(broken)
            XCTAssertTrue(PrintCheck.check(repaired, bed: nil).isWatertight)
            XCTAssertEqual(repaired.volume, box.volume, accuracy: 1e-15)
        }
    }

    func testThinWallsAndTheBed() throws {
        let sheet = EditableMesh.box(min: .zero, max: Vec3(30 * mm, 0.5 * mm, 30 * mm))
        let report = PrintCheck.check(sheet, bed: PrintBed.standard)
        XCTAssertFalse(report.thinFaces.isEmpty, "0.5 mm is under a filament printer's 0.8 mm")
        XCTAssertEqual(try XCTUnwrap(report.thinnestWall), 0.5 * mm, accuracy: 1e-9)
        let resin = try XCTUnwrap(PrintBed.preset("form-4"))
        XCTAssertTrue(PrintCheck.check(sheet, bed: resin).thinFaces.isEmpty, "resin prints 0.5 mm")
        let huge = EditableMesh.box(min: Vec3(-0.2, 0, -0.2), max: Vec3(0.2, 0.1, 0.2))
        XCTAssertEqual(PrintCheck.check(huge, bed: PrintBed.standard).fitsBed, false)
        XCTAssertNil(PrintBed.preset("nope"))
    }

    func testRepairCommandIsOneStep() throws {
        let box = EditableMesh.box(min: .zero, max: Vec3(1, 1, 1))
        let open = EditableMesh(vertices: box.vertices, faces: Array(box.faces.dropLast()))
        let object = SceneObject(id: "o", name: "O", kind: .mesh(open))
        let scene = Scene(id: "s", name: "S", objects: ["o": object], roots: ["o"])
        let command = try ModelingOperations.repairForPrinting("o", in: scene)
        XCTAssertEqual(command.label, "Repair for printing")
        XCTAssertNotNil(ModelingOperations.worldMesh(of: "o", in: scene))
    }

    // MARK: Precision

    private func project(_ point: Vec3) -> Vec2 {
        // Looking straight down from above: x right, -z up, 1000 points per metre.
        Vec2(point.x * 1000, -point.z * 1000)
    }

    func testPointsSnapToCornersMiddlesEdgesFacesAndTheGrid() {
        let box = EditableMesh.box(min: .zero, max: Vec3(0.1, 0.05, 0.1))
        let nearby = PointSnap.Nearby(meshes: [box])
        let ground = PlaneFrame(normal: .unitY, origin: .zero)
        func snap(_ x: Double, _ z: Double, settings: SnapSettings = SnapSettings(), surface: Vec3? = nil) -> SnapResult? {
            let ray = Ray(origin: Vec3(x, 1, z), direction: -.unitY)
            return PointSnap.snap(screen: Vec2(x * 1000, -z * 1000), ray: ray, surface: surface, in: nearby, plane: ground,
                                  settings: settings, radius: 8, project: project)
        }
        XCTAssertEqual(snap(0.103, 0.004)?.kind, .corner)
        XCTAssertTrue(snap(0.103, 0.004)?.point.isApproximately(Vec3(0.1, 0.05, 0)) == true, "the top corner, in front")
        XCTAssertEqual(snap(0.05, 0.0035)?.kind, .midpoint)
        XCTAssertEqual(snap(0.03, 0.0035)?.kind, .edge)
        XCTAssertEqual(snap(0.05, 0.05, surface: Vec3(0.05, 0.05, 0.05))?.kind, .face)
        var grid = SnapSettings(grid: true, gridSize: 0.01)
        grid.corners = false
        grid.edges = false
        let onGrid = snap(0.3141, 0.2718, settings: grid)
        XCTAssertEqual(onGrid?.kind, .grid)
        XCTAssertTrue(onGrid?.point.isApproximately(Vec3(0.31, 0, 0.27), tolerance: 1e-9) == true)
        XCTAssertEqual(snap(0.3141, 0.2718)?.kind, .free)
        XCTAssertEqual(PointSnap.measure(.zero, Vec3(3, -4, 0)).length, 5, accuracy: 1e-12)
    }

    func testOlderSnapSettingsKeepTheirValues() throws {
        let old = #"{"grid":true,"gridSize":0.01,"rotation":true,"rotationStep":15,"ground":true,"objects":true,"objectThreshold":0.005}"#
        let settings = try JSONDecoder().decode(SnapSettings.self, from: Data(old.utf8))
        XCTAssertEqual(settings.gridSize, 0.01)
        XCTAssertTrue(settings.corners && settings.edges && settings.faces)
        let workspace = try JSONDecoder().decode(ProjectWorkspace.self, from: Data(#"{"snap":\#(old),"printBed":"made-up"}"#.utf8))
        XCTAssertEqual(workspace.snap.gridSize, 0.01)
        XCTAssertNil(workspace.printBed, "an unknown printer is dropped")
        XCTAssertNil(workspace.section)
        XCTAssertEqual(StarterTemplate.print.workspace.printBed, PrintBed.standard.id)
    }

    func testKeptDimensionsFollowTheirObjectAndNeverExport() throws {
        let box = SceneObject(id: "box", name: "Box", kind: .mesh(.box(min: .zero, max: Vec3(0.04, 0.01, 0.02))),
                              transform: Transform(position: Vec3(1, 0, 0)))
        var scene = Scene(id: "s", name: "S", objects: ["box": box], roots: ["box"])
        var document = Document(project: ProjectInfo(id: "p", name: "P", created: Date(timeIntervalSince1970: 0),
                                                     modified: Date(timeIntervalSince1970: 0), sceneOrder: ["s"], sceneNames: ["s": "S"]),
                                scene: scene)
        let keep = ModelingOperations.keepDimension(from: Vec3(1, 0.01, 0), to: Vec3(1.04, 0.01, 0), owner: "box", in: scene, id: "dim")
        _ = try keep.apply(to: &document)
        scene = document.scene
        XCTAssertEqual(scene.objects["dim"]?.parent, "box")
        guard case let .dimension(recipe)? = scene.objects["dim"]?.kind else { return XCTFail("a dimension") }
        XCTAssertEqual(recipe.length, 0.04, accuracy: 1e-12)
        // Move the box: the dimension goes with it.
        _ = try EditCommand.setProperties([PropertyChange(object: "box", key: .position, value: .vec3(Vec3(2, 0, 0)))]).apply(to: &document)
        let kept = try XCTUnwrap(ModelingOperations.dimensions(in: document.scene).first)
        XCTAssertTrue(kept.start.isApproximately(Vec3(2, 0.01, 0)))
        XCTAssertTrue(SceneExport.meshes(nil, in: document.scene, look: document.project.look).allSatisfy { $0.name != "Dimension" })
        // It round-trips through the file format.
        let data = try JSONEncoder().encode(ObjectKind.dimension(recipe))
        XCTAssertEqual(try JSONDecoder().decode(ObjectKind.self, from: data), .dimension(recipe))
    }

    func testSectionPlanes() {
        let cut = SectionPlane(axis: .x, through: Vec3(0.5, 0, 0))
        XCTAssertTrue(cut.cuts(Vec3(0.6, 0, 0)))
        XCTAssertFalse(cut.cuts(Vec3(0.4, 0, 0)))
        XCTAssertTrue(cut.flipped.cuts(Vec3(0.4, 0, 0)))
        let face = SectionPlane(face: Vec3(0, 2, 0), through: Vec3(0, 1, 0))
        XCTAssertEqual(face.offset, 1, accuracy: 1e-12)
    }

    /// A zip from Python's zipfile (deflated): a red tetrahedron, 10 mm, moved 5 mm along x by its build item.
    static let deflated3MF = """
    UEsDBBQAAAAIAPl5RV2Rp6EmNAEAAJICAAAQAAAAM0QvM2Rtb2RlbC5tb2RlbH2RS27DIBBAr4Km+2BsZVNhuvMBql6A4ElCxccCbCU9fTGkiqNUAYkZ8eY//ONiDVkwRO1d\
    D2zXwIfg1o9oyOx06sFqY7TFhAFItnWxh3NK0zulUZ3RyrizWgUf/THtlLe0G61081GqNAftTlT5gLRt2J42LQgeMPo5KIyCH2TM/jmwliYSPeb0UH+JkxZ7+MQRyKjjZORV\
    eeNDD2/D0OQzDEAFpw8RBPeHb1SpRGqBpOuUY5RWgEw1fJZuxEsPDdxyfGHKSS3Gs+B5DEmX0lYNL6QaXsv7s750i9gLVhF7wSpihdF75pR7cSezVcnCivnSlr6Wbu2E/s9Z\
    5d0TZw/+z/zm31Xelqo2tdA6IVpHnJXtHmdtRsF1Qksq/9tAkC4efbA5PWnKvcv9KusWqz8tqxK/UEsDBBQAAAAIAPl5RV3HHBc8CgAAAAgAAAATAAAAW0NvbnRlbnRfVHlw\
    ZXNdLnhtbLMJqSxILda3AwBQSwECFAAUAAAACAD5eUVdkaehJjQBAACSAgAAEAAAAAAAAAAAAAAAgAEAAAAAM0QvM2Rtb2RlbC5tb2RlbFBLAQIUABQAAAAIAPl5RV3HHBc8\
    CgAAAAgAAAATAAAAAAAAAAAAAACAAWIBAABbQ29udGVudF9UeXBlc10ueG1sUEsFBgAAAAACAAIAfwAAAJ0BAAAAAA==
    """
}
