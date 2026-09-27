import Foundation
@testable import LoweyCore
import XCTest

/// Small scene used by many tests:  root "A" (cube) with child "B" (sphere), plus "C" (cylinder).
func makeDocument() -> Document {
    var a = SceneObject(id: "a", name: "A", kind: .primitive(.cube), transform: Transform(position: Vec3(1, 0, 0)))
    a.children = ["b"]
    a[.color] = .color(.palette(1))
    let b = SceneObject(id: "b", name: "B", kind: .primitive(.sphere), parent: "a",
                        transform: Transform(position: Vec3(0, 1, 0), scale: Vec3(0.5, 0.5, 0.5)))
    let c = SceneObject(id: "c", name: "C", kind: .primitive(.cylinder), transform: Transform(position: Vec3(-2, 0, 1)))
    let scene = Scene(id: "scene-1", name: "Test", objects: ["a": a, "b": b, "c": c], roots: ["a", "c"])
    let info = ProjectInfo(id: "project-1", name: "Test project", created: Date(timeIntervalSince1970: 0),
                           modified: Date(timeIntervalSince1970: 0), sceneOrder: ["scene-1"], sceneNames: ["scene-1": "Test"])
    return Document(project: info, scene: scene)
}

/// Asserts that applying `command` and then its inverse restores the document exactly,
/// and that re-applying (redo) reproduces the applied state exactly.
@discardableResult
func assertReverts(_ command: EditCommand, on document: Document, file: StaticString = #filePath, line: UInt = #line) throws -> Document {
    var working = document
    let (inverse, changes) = try command.apply(to: &working)
    let applied = working
    XCTAssertFalse(changes.isEmpty && applied != document, "changes must be reported", file: file, line: line)
    XCTAssertTrue(applied.scene.validate().isEmpty, "invalid after apply: \(applied.scene.validate())", file: file, line: line)
    let (redo, _) = try inverse.apply(to: &working)
    XCTAssertEqual(working, document, "inverse did not restore the document for \(command.label)", file: file, line: line)
    _ = try redo.apply(to: &working)
    XCTAssertEqual(working, applied, "re-applying did not reproduce the result for \(command.label)", file: file, line: line)
    // Commands must survive JSON (Scene Scripts, logs).
    let data = try LoweyJSON.encode(command)
    XCTAssertEqual(try LoweyJSON.decode(EditCommand.self, from: data), command, file: file, line: line)
    return applied
}

func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("lowey-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
