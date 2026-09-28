import Foundation
@testable import LoweyCore
import XCTest

final class ModelTests: XCTestCase {
    func testIdentifiersEncodeAsPlainStrings() throws {
        let id: ObjectID = "abc"
        XCTAssertEqual(try String(decoding: JSONEncoder().encode(id), as: UTF8.self), "\"abc\"")
        let dictionary: [ObjectID: Int] = ["x": 1]
        let json = try String(decoding: JSONEncoder().encode(dictionary), as: UTF8.self)
        XCTAssertEqual(json, "{\"x\":1}")
        XCTAssertEqual(try JSONDecoder().decode([ObjectID: Int].self, from: Data(json.utf8)), dictionary)
        XCTAssertNotEqual(ObjectID.make(), ObjectID.make())
        XCTAssertTrue(ObjectID(raw: "a") < ObjectID(raw: "b"))
        XCTAssertEqual(ObjectID(raw: "q").description, "q")
    }

    func testIDFactorySequential() {
        var factory = IDFactory.sequential("t")
        let a: ObjectID = factory.next()
        let b: SceneID = factory.next()
        XCTAssertEqual(a.raw, "t-1")
        XCTAssertEqual(b.raw, "t-2")
        var random = IDFactory.random
        let r: ObjectID = random.next()
        XCTAssertEqual(r.raw.count, 36)
    }

    func testPropertyValueCodableAllTypes() throws {
        let values: [PropertyValue] = [
            .float(1.5), .int(3), .bool(true), .vec3(Vec3(1, 2, 3)), .quat(Quat(angle: 1, axis: .unitY)),
            .color(.palette(1)), .color(.rgba(RGBA(0.2, 0.4, 0.6))), .string("hi"), .enumeration("flat"), .asset("tree")
        ]
        for value in values {
            let data = try LoweyJSON.encode(value)
            let decoded = try LoweyJSON.decode(PropertyValue.self, from: data)
            if case let .color(.rgba(color)) = value, case let .color(.rgba(back)) = decoded {
                XCTAssertEqual(color.hex, back.hex)
            } else {
                XCTAssertEqual(decoded, value)
            }
        }
        XCTAssertEqual(try String(decoding: JSONEncoder().encode(PropertyValue.bool(true)), as: UTF8.self), "{\"bool\":true}")
        XCTAssertThrowsError(try LoweyJSON.decode(PropertyValue.self, from: Data("{\"float\":1,\"int\":2}".utf8)))
    }

    func testPropertyValueAccessorsAndTypes() {
        XCTAssertEqual(PropertyValue.int(2).floatValue, 2)
        XCTAssertEqual(PropertyValue.float(2).floatValue, 2)
        XCTAssertNil(PropertyValue.bool(true).floatValue)
        XCTAssertEqual(PropertyValue.bool(true).boolValue, true)
        XCTAssertNil(PropertyValue.int(1).boolValue)
        XCTAssertEqual(PropertyValue.vec3(.one).vec3Value, .one)
        XCTAssertNil(PropertyValue.int(1).vec3Value)
        XCTAssertEqual(PropertyValue.quat(.identity).quatValue, .identity)
        XCTAssertNil(PropertyValue.int(1).quatValue)
        XCTAssertEqual(PropertyValue.color(.palette(0)).colorValue, .palette(0))
        XCTAssertNil(PropertyValue.int(1).colorValue)
        XCTAssertEqual(PropertyValue.string("a").stringValue, "a")
        XCTAssertEqual(PropertyValue.enumeration("b").stringValue, "b")
        XCTAssertNil(PropertyValue.int(1).stringValue)
        XCTAssertEqual(PropertyValue.asset("x").type, .asset)
        XCTAssertTrue(PropertyType.vec3.interpolates)
        XCTAssertFalse(PropertyType.bool.interpolates)
        XCTAssertEqual(PropertyKey.position.spec?.type, .vec3)
        XCTAssertNil(PropertyKey("custom").spec)
        XCTAssertEqual(PropertyKey("z").description, "z")
        XCTAssertTrue(PropertyKey("a") < PropertyKey("b"))
    }

    func testPropertyInterpolation() {
        XCTAssertEqual(PropertyValue.float(0).interpolated(to: .float(10), 0.25), .float(2.5))
        XCTAssertEqual(PropertyValue.vec3(.zero).interpolated(to: .vec3(Vec3(2, 2, 2)), 0.5), .vec3(.one))
        if case let .quat(q) = PropertyValue.quat(.identity).interpolated(to: .quat(Quat(angle: 1, axis: .unitY)), 0.5) {
            XCTAssertTrue(q.isApproximately(Quat(angle: 0.5, axis: .unitY)))
        } else {
            XCTFail("expected quat")
        }
        let palette = Palette(swatches: [.init(name: "a", color: .black), .init(name: "b", color: .white)])
        if case let .color(.rgba(color)) = PropertyValue.color(.palette(0)).interpolated(to: .color(.palette(1)), 0.5, palette: palette) {
            XCTAssertEqual(color.r, 0.5, accuracy: 1.0 / 255)
        } else {
            XCTFail("expected rgba")
        }
        XCTAssertEqual(PropertyValue.color(.palette(0)).interpolated(to: .color(.palette(0)), 0.5), .color(.palette(0)))
        XCTAssertEqual(PropertyValue.bool(false).interpolated(to: .bool(true), 0.9), .bool(false))
        XCTAssertEqual(PropertyValue.bool(false).interpolated(to: .bool(true), 1), .bool(true))
    }

    func testObjectKindCodable() throws {
        let kinds: [ObjectKind] = [
            .group, .primitive(.torus), .asset("a"), .prefab("p"), .light(.spot), .camera,
            .drawing(DrawingRecipe(style: .tube, strokes: [.init(points: [.zero, .one], widths: [0.1, 0.2])]))
        ]
        for kind in kinds {
            XCTAssertEqual(try LoweyJSON.decode(ObjectKind.self, from: LoweyJSON.encode(kind)), kind)
        }
        XCTAssertThrowsError(try LoweyJSON.decode(ObjectKind.self, from: Data("{\"type\":\"banana\"}".utf8)))
        XCTAssertEqual(ObjectKind.asset("a").assetID, "a")
        XCTAssertNil(ObjectKind.group.assetID)
        XCTAssertEqual(ObjectKind.prefab("p").prefabID, "p")
        XCTAssertNil(ObjectKind.group.prefabID)
        XCTAssertTrue(ObjectKind.primitive(.cube).hasSurface)
        XCTAssertFalse(ObjectKind.light(.point).hasSurface)
        XCTAssertEqual(PrimitiveShape.allCases.map(\.displayName).count, 7)
    }

    func testStrokeWidthsPadToPoints() {
        let stroke = DrawingRecipe.Stroke(points: [.zero, .one, .one], widths: [0.3])
        XCTAssertEqual(stroke.widths, [0.3, 0.3, 0.3])
    }

    func testSceneObjectAccessors() {
        var object = SceneObject(id: "o", name: "O", kind: .primitive(.cube))
        XCTAssertTrue(object.isVisible)
        XCTAssertFalse(object.isLocked)
        XCTAssertNil(object.color)
        XCTAssertEqual(object.shading, .inherit)
        object[.visible] = .bool(false)
        object[.locked] = .bool(true)
        object[.color] = .color(.palette(3))
        object[.emissive] = .color(.palette(1))
        object[.emissiveIntensity] = .float(2)
        object[.shading] = .enumeration("flat")
        XCTAssertFalse(object.isVisible)
        XCTAssertTrue(object.isLocked)
        XCTAssertEqual(object.color, .palette(3))
        XCTAssertEqual(object.emissive, .palette(1))
        XCTAssertEqual(object.emissiveIntensity, 2)
        XCTAssertEqual(object.shading, .flat)
        object.transform = Transform(position: Vec3(1, 2, 3))
        XCTAssertEqual(object[.position], .vec3(Vec3(1, 2, 3)))
    }

    func testSceneHierarchyQueries() {
        let document = makeDocument()
        let scene = document.scene
        XCTAssertEqual(scene.orderedIDs(), ["a", "b", "c"])
        XCTAssertEqual(scene.subtree(of: "a"), ["a", "b"])
        XCTAssertEqual(scene.ancestors(of: "b"), ["a"])
        XCTAssertTrue(scene.isAncestor("a", of: "b"))
        XCTAssertFalse(scene.isAncestor("c", of: "b"))
        XCTAssertEqual(scene.childIDs(of: nil), ["a", "c"])
        XCTAssertEqual(scene.childIDs(of: "a"), ["b"])
        XCTAssertTrue(scene.worldTransform(of: "b").position.isApproximately(Vec3(1, 1, 0)))
        XCTAssertEqual(scene.worldTransform(of: "zzz"), .identity)
        XCTAssertTrue(scene.validate().isEmpty)
        XCTAssertTrue(scene.isEffectivelyVisible("b"))
        XCTAssertFalse(scene.isEffectivelyVisible("zzz"))
        XCTAssertFalse(scene.isEffectivelyLocked("b"))
        XCTAssertFalse(scene.isEffectivelyLocked("zzz"))
        var hidden = scene
        hidden.objects["a"]?[.visible] = .bool(false)
        hidden.objects["a"]?[.locked] = .bool(true)
        XCTAssertFalse(hidden.isEffectivelyVisible("b"))
        XCTAssertTrue(hidden.isEffectivelyLocked("b"))
        XCTAssertEqual(scene.cameras, [])
        XCTAssertEqual(scene["a"]?.name, "A")
    }

    func testSceneValidateFindsProblems() {
        var scene = makeDocument().scene
        scene.objects["orphan"] = SceneObject(id: "orphan", name: "x", kind: .group)
        scene.objects["b"]?.parent = "c"
        XCTAssertFalse(scene.validate().isEmpty)
        var dup = makeDocument().scene
        dup.roots.append("a")
        XCTAssertFalse(dup.validate().isEmpty)
    }

    func testViewpoint() {
        let front = Viewpoint(target: .zero, yaw: 0, pitch: 0, distance: 5)
        XCTAssertTrue(front.eye.isApproximately(Vec3(0, 0, 5)))
        XCTAssertTrue(front.rotation.act(Vec3(0, 0, -1)).isApproximately(Vec3(0, 0, -1)))
        let above = Viewpoint(target: .zero, yaw: 90, pitch: 45, distance: 2)
        let forward = above.rotation.act(Vec3(0, 0, -1))
        XCTAssertTrue(forward.isApproximately((above.target - above.eye).normalized, tolerance: 1e-9))
    }

    func testLookPresets() {
        for preset in LightingPreset.allCases {
            let look = LookPresets.look(for: preset)
            XCTAssertEqual(look.lightingPreset, preset)
            XCTAssertFalse(preset.displayName.isEmpty)
            XCTAssertTrue(look.lighting.sunDirection.y < 0, "sun must shine downward")
        }
        var custom = Look.default
        custom.palette = Palette(swatches: [])
        let night = custom.applying(.night)
        XCTAssertEqual(night.palette, custom.palette, "presets keep the palette")
        XCTAssertEqual(night.lighting, LookPresets.look(for: .night).lighting)
        XCTAssertEqual(night.sky.stars, LookPresets.sky(for: .night).stars)
        let document = makeDocument()
        XCTAssertEqual(document.effectiveLook, document.project.look)
        XCTAssertEqual(document.palette, document.project.look.palette)
    }

    // MARK: Palette

    func testRemovingASwatchHidesItButKeepsEveryColour() throws {
        var palette = Palette.starter
        let count = palette.swatches.count
        let before = (0 ..< count).map { palette.color(at: $0) }
        palette.remove(slot: 1)
        XCTAssertEqual(palette.swatches.count, count, "slots never shift: objects bound to later slots keep their colour")
        XCTAssertEqual((0 ..< count).map { palette.color(at: $0) }, before, "nothing changes colour")
        XCTAssertFalse(palette.visibleSlots.contains(1))
        XCTAssertEqual(palette.visibleSlots.count, count - 1)
        // Old files (no "removed" key) still load, and the flag round-trips.
        let data = try JSONEncoder().encode(palette)
        XCTAssertEqual(try JSONDecoder().decode(Palette.self, from: data), palette)
        let old = try JSONDecoder().decode(Palette.Swatch.self, from: Data(##"{"name":"Paper","color":"#F2E8D5"}"##.utf8))
        XCTAssertNil(old.removed)
    }
}
