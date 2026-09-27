import Foundation
@testable import LoweyCore
import XCTest

final class SerializationTests: XCTestCase {
    func testSceneRoundTripIsIdentical() throws {
        let (info, scenes) = try EnigmaSample.build()
        for scene in scenes {
            let data = try SchemaCoder.shared.encode(scene, kind: .scene)
            let loaded = try SchemaCoder.shared.decode(Scene.self, kind: .scene, from: data)
            XCTAssertEqual(loaded, scene)
            // Byte-identical re-save (sorted keys, exact numbers).
            XCTAssertEqual(try SchemaCoder.shared.encode(loaded, kind: .scene), data)
        }
        let infoData = try SchemaCoder.shared.encode(info, kind: .project)
        XCTAssertEqual(try SchemaCoder.shared.decode(ProjectInfo.self, kind: .project, from: infoData), info)
    }

    func testEnvelopeShape() throws {
        let data = try SchemaCoder.shared.encode(makeDocument().scene, kind: .scene)
        let raw = try LoweyJSON.decode(JSONValue.self, from: data)
        XCTAssertEqual(raw["schemaVersion"]?.numberValue, Double(SchemaCoder.currentVersion))
        XCTAssertEqual(raw["kind"]?.stringValue, "scene")
        XCTAssertNotNil(raw["payload"]?["objects"]?["a"])
    }

    /// A hand-written v0 file: bare payload, objects as an array, nested transform object.
    func testMigrationFromFakeV0File() throws {
        let v0 = """
        {
          "id": "old-scene",
          "name": "From 2025",
          "objects": [
            {"id": "table", "name": "Table", "kind": {"type": "primitive", "shape": "cube"},
             "transform": {"position": [1, 0, 2], "rotation": [0, 0, 0, 1], "scale": [2, 1, 1]},
             "children": ["cup"]},
            {"id": "cup", "name": "Cup", "kind": {"type": "primitive", "shape": "cylinder"}, "parent": "table",
             "transform": {"position": [0, 1, 0], "rotation": [0, 0, 0, 1], "scale": [0.1, 0.1, 0.1]},
             "properties": {"color": {"color": "#FF0000"}}}
          ]
        }
        """
        let scene = try SchemaCoder.shared.decode(Scene.self, kind: .scene, from: Data(v0.utf8))
        XCTAssertEqual(scene.name, "From 2025")
        XCTAssertEqual(scene.roots, ["table"])
        XCTAssertEqual(scene.objects["table"]?.transform.position, Vec3(1, 0, 2))
        XCTAssertEqual(scene.objects["table"]?.transform.scale, Vec3(2, 1, 1))
        XCTAssertEqual(scene.objects["cup"]?.parent, "table")
        XCTAssertEqual(scene.objects["cup"]?.color, .rgba(RGBA(1, 0, 0)))
        XCTAssertTrue(scene.validate().isEmpty)
        XCTAssertEqual(scene.viewpoint, .default)
        // A migrated scene saves in the current format.
        let resaved = try SchemaCoder.shared.encode(scene, kind: .scene)
        XCTAssertEqual(try SchemaCoder.shared.decode(Scene.self, kind: .scene, from: resaved), scene)
    }

    func testMigrationOfV0ObjectDictionaryAndProject() throws {
        let v0 = """
        {"id":"s","name":"Dict","objects":{"x":{"id":"x","name":"X","kind":{"type":"group"}}}}
        """
        let scene = try SchemaCoder.shared.decode(Scene.self, kind: .scene, from: Data(v0.utf8))
        XCTAssertEqual(scene.roots, ["x"])
        XCTAssertEqual(scene.objects["x"]?.children, [])
        let project = try SchemaCoder.shared.decode(ProjectInfo.self, kind: .project, from:
            SchemaCoder.shared.encode(ProjectInfo(id: "p", name: "P"), kind: .project))
        XCTAssertEqual(project.name, "P")
        // Raw v0 project (unwrapped).
        let rawProject = try LoweyJSON.encode(ProjectInfo(id: "p2", name: "Old"))
        XCTAssertEqual(try SchemaCoder.shared.decode(ProjectInfo.self, kind: .project, from: rawProject).name, "Old")
    }

    func testNewerFilesAreRefused() throws {
        let future = """
        {"schemaVersion": 99, "kind": "scene", "payload": {}}
        """
        XCTAssertThrowsError(try SchemaCoder.shared.decode(Scene.self, kind: .scene, from: Data(future.utf8))) { error in
            XCTAssertEqual(error as? SchemaError, .newerThanApp(found: 99, supported: SchemaCoder.currentVersion))
        }
    }

    func testMissingMigrationAndMalformed() throws {
        let coder = SchemaCoder(migrations: [], currentVersion: 2)
        let v1 = try SchemaCoder.shared.encode(makeDocument().scene, kind: .scene)
        XCTAssertThrowsError(try coder.decode(Scene.self, kind: .scene, from: v1)) { error in
            XCTAssertEqual(error as? SchemaError, .missingMigration(from: 1))
        }
        XCTAssertThrowsError(try SchemaCoder.shared.decode(Scene.self, kind: .scene, from: Data("not json".utf8)))
        XCTAssertThrowsError(try SchemaCoder.shared.decode(Scene.self, kind: .scene, from: Data("{\"schemaVersion\":1,\"payload\":{}}".utf8)))
        for error in [SchemaError.newerThanApp(found: 2, supported: 1), .missingMigration(from: 0), .malformed("x")] {
            XCTAssertFalse(error.description.isEmpty)
        }
    }

    func testCustomMigrationChain() throws {
        // A future v2 that renames "name" → "title" and back, proving the chain runs in order.
        let coder = SchemaCoder(migrations: SchemaCoder.builtInMigrations + [
            Migration(kind: .scene, from: 1) { payload in
                var p = payload
                p["name"] = .string((payload["name"]?.stringValue ?? "") + " (migrated)")
                return p
            }
        ], currentVersion: 2)
        let v1 = try SchemaCoder.shared.encode(makeDocument().scene, kind: .scene)
        let scene = try coder.decode(Scene.self, kind: .scene, from: v1)
        XCTAssertEqual(scene.name, "Test (migrated)")
    }

    func testJSONValue() throws {
        let json = """
        {"a": [1, true, null, "s", {"b": 2.5}]}
        """
        let value = try LoweyJSON.decode(JSONValue.self, from: Data(json.utf8))
        XCTAssertEqual(value["a"]?.arrayValue?.count, 5)
        XCTAssertEqual(value["a"]?.arrayValue?[3].stringValue, "s")
        XCTAssertEqual(value["a"]?.arrayValue?[4]["b"]?.numberValue, 2.5)
        XCTAssertNil(JSONValue.null["x"])
        XCTAssertNil(JSONValue.null.objectValue)
        XCTAssertNil(JSONValue.null.arrayValue)
        XCTAssertNil(JSONValue.null.stringValue)
        XCTAssertNil(JSONValue.null.numberValue)
        var mutable = JSONValue.null
        mutable["x"] = .bool(true) // ignored on non-objects
        XCTAssertEqual(mutable, .null)
        XCTAssertEqual(try LoweyJSON.decode(JSONValue.self, from: LoweyJSON.encode(value)), value)
    }

    func testSafeWriterKeepsBackupAndRecovers() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("scene.json")
        try SafeFileWriter.write(Data("{\"v\":1}".utf8), to: url)
        try SafeFileWriter.write(Data("{\"v\":2}".utf8), to: url)
        XCTAssertEqual(try Data(contentsOf: SafeFileWriter.backupURL(for: url)), Data("{\"v\":1}".utf8))
        // Simulate a crash that damaged the main file.
        try Data("{\"v\":".utf8).write(to: url)
        let result = try SafeFileWriter.read(url) { data in _ = try LoweyJSON.decode(JSONValue.self, from: data) }
        XCTAssertTrue(result.recoveredFromBackup)
        XCTAssertEqual(result.data, Data("{\"v\":1}".utf8))
        // Writing over a damaged file must not replace the good backup with garbage.
        try SafeFileWriter.write(Data("{\"v\":3}".utf8), to: url)
        XCTAssertEqual(try Data(contentsOf: SafeFileWriter.backupURL(for: url)), Data("{\"v\":1}".utf8))
        // Missing entirely.
        XCTAssertThrowsError(try SafeFileWriter.read(directory.appendingPathComponent("missing.json")) { _ in })
    }
}
