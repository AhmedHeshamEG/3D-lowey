import Foundation
@testable import LoweyCore
import XCTest

final class LookSystemTests: XCTestCase {
    func testFiveBuiltInLooksWithTheirIdentity() {
        XCTAssertEqual(LookPreset.builtIns.map(\.id), ["ink", "comic", "sketch", "clay", "lowPoly"])
        XCTAssertEqual(Set(LookPreset.builtIns.map(\.id)).count, 5)
        XCTAssertEqual(LookPreset.comic.stepping, .onTwos, "Comic animates on twos")
        XCTAssertGreaterThan(LookPreset.comic.comic.halftone, 0)
        XCTAssertTrue(LookPreset.comic.comic.misregistration)
        XCTAssertTrue(LookPreset.sketch.finish.accentKeepsColor)
        XCTAssertTrue(LookPreset.sketch.lines.pencil)
        XCTAssertGreaterThan(LookPreset.sketch.lines.boil, 0)
        XCTAssertEqual(LookPreset.clay.shading.model, .clay)
        XCTAssertFalse(LookPreset.clay.lines.enabled)
        XCTAssertEqual(LookPreset.lowPoly.shading.smoothing, 0, "Low-poly is faceted")
        XCTAssertTrue(LookPreset.ink.lines.enabled)
        XCTAssertEqual(LookPreset.ink.lines.colorMode, .darkened, "Ink lines are the darkened object colour, never pure black")
        for preset in LookPreset.builtIns {
            XCTAssertTrue(preset.isBuiltIn)
            XCTAssertTrue((0.002 ... 0.5).contains(preset.shading.edgeSoftness), preset.id)
            XCTAssertTrue([2, 3].contains(preset.shading.bands), preset.id)
        }
    }

    func testResolveFallsBackToInk() {
        let mine = LookPreset.comic.duplicated(id: "mine", name: "My Comic")
        XCTAssertEqual(LookLibrary.resolve("mine", custom: [mine]).name, "My Comic")
        XCTAssertEqual(LookLibrary.resolve("clay").id, "clay")
        XCTAssertEqual(LookLibrary.resolve("deleted").id, "ink")
        XCTAssertEqual(LookLibrary.resolve(nil).id, "ink")
        XCTAssertEqual(LookLibrary.all(custom: [mine]).count, 6)
        XCTAssertEqual(mine.basedOn, "comic")
        XCTAssertFalse(mine.isBuiltIn)
    }

    func testDuplicateNames() {
        XCTAssertEqual(LookLibrary.duplicateName(for: .ink, existing: []), "My Ink")
        let first = LookPreset.ink.duplicated(id: "a", name: "My Ink")
        XCTAssertEqual(LookLibrary.duplicateName(for: .ink, existing: [first]), "My Ink 2")
    }

    func testPerObjectOverrideAndSceneLook() {
        var document = makeDocument()
        document.project.look.presetID = "sketch"
        XCTAssertEqual(document.lookPreset.id, "sketch")
        var object = document.scene.objects["a"]!
        XCTAssertEqual(document.lookPreset(for: object).id, "sketch")
        object[.lookPreset] = .enumeration("comic")
        object[.accent] = .bool(true)
        object[.lineWeight] = .float(2)
        XCTAssertEqual(document.lookPreset(for: object).id, "comic", "one character can come from a different universe")
        XCTAssertTrue(object.isAccent)
        XCTAssertEqual(object.lineWeight, 2)
        XCTAssertFalse(object.isGlossy)
    }

    func testCustomLooksRoundTripAndStayOptional() throws {
        var info = ProjectInfo(id: "p", name: "P")
        let plain = try LoweyJSON.encode(info)
        XCTAssertFalse(String(decoding: plain, as: UTF8.self).contains("looks"), "no key until there is a custom Look")
        info.customLooks = [LookPreset.sketch.duplicated(id: "x", name: "My Sketch")]
        let data = try SchemaCoder.shared.encode(info, kind: .project)
        XCTAssertEqual(try SchemaCoder.shared.decode(ProjectInfo.self, kind: .project, from: data), info)
        info.customLooks = []
        XCTAssertEqual(info.customLooks, [])
    }

    func testLookPresetJSONRoundTrip() throws {
        for preset in LookPreset.builtIns {
            let data = try LoweyJSON.encode(preset)
            XCTAssertEqual(try LoweyJSON.decode(LookPreset.self, from: data), preset)
        }
    }

    func testWithPresetKeepsTheWorld() {
        let night = MoodPresets.look(for: .night)
        let comic = night.withPreset("comic")
        XCTAssertEqual(comic.presetID, "comic")
        XCTAssertEqual(comic.sky, night.sky)
        XCTAssertEqual(comic.palette, night.palette)
    }

    func testOpeningAVersion1ProjectUpgradesItWithABackup() throws {
        // A 1.x package: project.json + one scene at schema 3, no manifest.
        let root = try temporaryDirectory()
        let url = root.appendingPathComponent("Old film.lowey")
        let scenes = url.appendingPathComponent("scenes")
        try FileManager.default.createDirectory(at: scenes, withIntermediateDirectories: true)
        let document = makeDocument()
        func v3(_ data: Data, stripping key: String) throws -> Data {
            var json = try LoweyJSON.decode(JSONValue.self, from: data)
            json["schemaVersion"] = .number(3)
            var payload = json["payload"] ?? .null
            if var look = payload[key] {
                look["presetID"] = nil
                if case var .object(dictionary) = look {
                    dictionary.removeValue(forKey: "presetID")
                    look = .object(dictionary)
                }
                payload[key] = look
            }
            json["payload"] = payload
            return try LoweyJSON.encode(json)
        }
        try v3(SchemaCoder.shared.encode(document.project, kind: .project), stripping: "look")
            .write(to: url.appendingPathComponent("project.json"))
        try v3(SchemaCoder.shared.encode(document.scene, kind: .scene), stripping: "look")
            .write(to: scenes.appendingPathComponent("scene-1.json"))

        let store = ProjectStore(root: root)
        let opened = try store.openDocument(at: url)
        XCTAssertEqual(opened.scene.objects.count, 3)
        XCTAssertEqual(opened.project.look.presetID, "clay", "a 1.x project keeps its look")
        let manifest = try XCTUnwrap(DocumentPackage(url: url).readManifest())
        XCTAssertEqual(manifest.app, "lowey")
        XCTAssertEqual(manifest.schemaVersion, ProjectLayout.packageVersion)
        let backup = root.appendingPathComponent("Old film.v1.bak")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.appendingPathComponent("project.json").path))
        XCTAssertEqual(store.listProjects().count, 1, "the backup isn't listed as a project")
        try store.save(opened, to: url)
        let raw = try LoweyJSON.decode(JSONValue.self, from: Data(contentsOf: url.appendingPathComponent("project.json")))
        XCTAssertEqual(raw["schemaVersion"]?.numberValue, Double(LoweySchema.currentVersion))
    }

    func testNewProjectsAreV2PackagesInInk() throws {
        let store = try ProjectStore(root: temporaryDirectory())
        let (url, document) = try store.createProject(name: "Fresh")
        XCTAssertEqual(document.project.look.presetID, "ink")
        XCTAssertEqual(try DocumentPackage(url: url).readManifest()?.kind, "project")
    }
}
