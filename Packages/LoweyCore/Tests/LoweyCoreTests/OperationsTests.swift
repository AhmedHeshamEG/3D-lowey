import Foundation
@testable import LoweyCore
import XCTest

final class OperationsTests: XCTestCase {
    private var ops = Operations(ids: .sequential("op"))

    override func setUp() {
        ops = Operations(ids: .sequential("op"))
    }

    private func worldPositions(_ document: Document, _ ids: [ObjectID]) -> [Vec3] {
        ids.map { document.scene.worldTransform(of: $0).position }
    }

    func testAddAndPlaceOnGround() throws {
        var factory = ObjectFactory(ids: .sequential("f"))
        let cube = factory.primitive(.cube)
        let placed = ops.placeOnGround(cube, at: Vec3(1, 2, 3))
        XCTAssertEqual(placed.transform.position, Vec3(1, 2, 3))
        let doc = try assertReverts(ops.add(placed), on: makeDocument())
        XCTAssertNotNil(doc.scene.objects[cube.id])
        try assertReverts(ops.add(cube, parent: "a"), on: makeDocument())
        // Asset whose pivot is in its middle is lifted so it sits on the ground.
        let asset = LibraryAsset(id: "rock", name: "Rock", format: .glb, file: "rock.glb",
                                 bounds: Bounds(min: Vec3(-1, -0.5, -1), max: Vec3(1, 0.5, 1)))
        let lifted = Operations(library: LibraryManifest(assets: [asset])).placeOnGround(factory.asset(asset), at: .zero)
        XCTAssertEqual(lifted.transform.position.y, 0.5)
    }

    func testFactoryDefaults() {
        var factory = ObjectFactory(ids: .sequential("f"))
        XCTAssertEqual(factory.primitive(.cone).color, .rgba(.blockout))
        XCTAssertEqual(factory.group().kind, .group)
        let spot = factory.light(.spot, at: .zero)
        XCTAssertEqual(spot[.spotAngle], .float(40))
        XCTAssertTrue(spot.transform.rotation.act(Vec3(0, 0, -1)).isApproximately(Vec3(0, -1, 0)))
        XCTAssertNotNil(factory.light(.directional, at: .zero)[.lightIntensity])
        XCTAssertEqual(factory.light(.point, at: .zero).name, "Lamp light")
        XCTAssertEqual(factory.camera(at: .default).kind, .camera)
        let prefab = Prefab(id: "p", name: "Thing", fragment: SceneFragment(objects: [], roots: []))
        XCTAssertEqual(factory.prefabInstance(prefab).kind, .prefab("p"))
        for style in DrawingRecipe.Style.allCases {
            XCTAssertFalse(factory.drawing(DrawingRecipe(style: style, strokes: []), transform: .identity, color: .palette(0)).name.isEmpty)
        }
        XCTAssertEqual(ObjectFactory.uniqueName("A", in: makeDocument().scene), "A 2")
        XCTAssertEqual(ObjectFactory.uniqueName("Zed", in: makeDocument().scene), "Zed")
    }

    func testDuplicateKeepsHierarchyWithNewIDs() throws {
        let document = makeDocument()
        let (command, newRoots) = try XCTUnwrap(ops.duplicate(["a", "b"], in: document.scene))
        XCTAssertEqual(newRoots.count, 1, "b comes along as a's child")
        let applied = try assertReverts(command, on: document)
        let copy = try XCTUnwrap(applied.scene.objects[newRoots[0]])
        XCTAssertEqual(copy.name, "A 2")
        XCTAssertEqual(copy.children.count, 1)
        XCTAssertNotEqual(copy.children[0], "b")
        XCTAssertTrue(copy.transform.position.isApproximately(Vec3(1.5, 0, 0.5)))
        XCTAssertNil(ops.duplicate(["missing"], in: document.scene))
    }

    func testDeleteSkipsLocked() throws {
        var document = makeDocument()
        document.scene.objects["c"]?[.locked] = .bool(true)
        let command = try XCTUnwrap(ops.delete(["a", "c"], in: document.scene))
        XCTAssertEqual(command, .delete(["a"]))
        XCTAssertNil(ops.delete(["c"], in: document.scene))
    }

    func testTranslateRotateScaleRespectHierarchy() throws {
        let document = makeDocument()
        let moved = try assertReverts(ops.translate(["a", "b"], by: Vec3(0, 2, 0), in: document.scene), on: document)
        XCTAssertTrue(worldPositions(moved, ["a", "b"])[1].isApproximately(Vec3(1, 3, 0)), "child moved once, with its parent")

        let rotated = try assertReverts(ops.rotate(["c"], by: Quat(angle: .pi, axis: .unitY), around: .zero, in: document.scene), on: document)
        XCTAssertTrue(worldPositions(rotated, ["c"])[0].isApproximately(Vec3(2, 0, -1)))

        let scaled = try assertReverts(ops.scale(["a"], by: Vec3(2, 2, 2), around: Vec3(1, 0, 0), in: document.scene), on: document)
        XCTAssertTrue(worldPositions(scaled, ["b"])[0].isApproximately(Vec3(1, 2, 0)))

        // Child alone moves in world space even though its parent is transformed.
        let child = try assertReverts(ops.translate(["b"], by: Vec3(1, 0, 0), in: document.scene), on: document)
        XCTAssertTrue(worldPositions(child, ["b"])[0].isApproximately(Vec3(2, 1, 0)))

        var locked = document
        locked.scene.objects["c"]?[.locked] = .bool(true)
        XCTAssertEqual(ops.translate(["c"], by: .one, in: locked.scene), .setProperties([]))
        try assertReverts(ops.setTransform("c", Transform(position: .one, rotation: Quat(eulerDegrees: Vec3(0, 45, 0)), scale: Vec3(2, 2, 2))), on: document)
    }

    func testDropToGroundStacks() throws {
        var document = makeDocument()
        document.scene.objects["c"]?.transform = Transform(position: Vec3(1, 3, 0))
        let applied = try assertReverts(ops.dropToGround(["c"], in: document.scene), on: document)
        // c lands on top of a (cube 0..1) — but b (sphere radius 0.25 at y 1..1.5) is on top of a too.
        let bottom = try XCTUnwrap(SceneBounds().worldBounds(of: "c", in: applied.scene)).min.y
        XCTAssertEqual(bottom, 1.5, accuracy: 1e-6)
    }

    func testGroupAndUngroupKeepWorldTransforms() throws {
        let document = makeDocument()
        let before = worldPositions(document, ["a", "b", "c"])
        let (groupCommand, groupID) = try XCTUnwrap(ops.group(["a", "c"], in: document.scene))
        let grouped = try assertReverts(groupCommand, on: document)
        XCTAssertEqual(grouped.scene.objects[groupID]?.children, ["a", "c"])
        XCTAssertEqual(grouped.scene.roots, [groupID])
        for (index, id) in ["a", "b", "c"].enumerated() {
            XCTAssertTrue(grouped.scene.worldTransform(of: ObjectID(raw: id)).position.isApproximately(before[index]))
        }
        let ungroupCommand = try XCTUnwrap(ops.ungroup(groupID, in: grouped.scene))
        let ungrouped = try assertReverts(ungroupCommand, on: grouped)
        XCTAssertEqual(ungrouped.scene.roots, ["a", "c"])
        for (index, id) in ["a", "b", "c"].enumerated() {
            XCTAssertTrue(ungrouped.scene.worldTransform(of: ObjectID(raw: id)).position.isApproximately(before[index]))
        }
        XCTAssertNil(ops.group([], in: document.scene))
        XCTAssertNil(ops.ungroup("missing", in: document.scene))
    }

    func testReparentKeepsWorldTransform() throws {
        let document = makeDocument()
        let before = document.scene.worldTransform(of: "c")
        let command = try XCTUnwrap(ops.reparent(["c"], to: "b", in: document.scene))
        let applied = try assertReverts(command, on: document)
        XCTAssertTrue(applied.scene.worldTransform(of: "c").isApproximately(before))
        XCTAssertNil(ops.reparent(["a"], to: "b", in: document.scene), "can't put a parent inside its child")
    }

    func testArrays() throws {
        let document = makeDocument()
        let (line, lineGroup) = try XCTUnwrap(ops.array("c", layout: .line(count: 5, step: Vec3(1, 0, 0)), in: document.scene))
        let lined = try assertReverts(line, on: document)
        XCTAssertEqual(lined.scene.objects[lineGroup]?.children.count, 5)
        XCTAssertEqual(lined.scene.objects[lineGroup]?.children.first, "c")
        XCTAssertTrue(lined.scene.worldTransform(of: "c").position.isApproximately(Vec3(-2, 0, 1)))

        let (grid, gridGroup) = try XCTUnwrap(ops.array("a", layout: .grid(columns: 3, rows: 2, spacingX: 2, spacingZ: 2), in: document.scene))
        let gridded = try assertReverts(grid, on: document)
        XCTAssertEqual(gridded.scene.objects[gridGroup]?.children.count, 6)
        // Each copy of a includes its child b.
        XCTAssertEqual(gridded.scene.objects.values.filter { $0.name == "B" }.count, 6)

        let (circle, circleGroup) = try XCTUnwrap(ops.array("c", layout: .circle(count: 8, radius: 2, faceCenter: true), in: document.scene))
        let circled = try assertReverts(circle, on: document)
        let center = Vec3(-2, 0, -1)
        for child in circled.scene.objects[circleGroup]?.children ?? [] {
            XCTAssertEqual(circled.scene.worldTransform(of: child).position.distance(to: center), 2, accuracy: 1e-6)
        }
        XCTAssertNil(ops.array("missing", layout: .line(count: 3, step: .one), in: document.scene))
        XCTAssertNil(ops.array("c", layout: .line(count: 1, step: .one), in: document.scene))
    }

    func testScatterIsDeterministicAndInsideTheArea() throws {
        let document = makeDocument()
        let settings = ScatterSettings(count: 20, radius: 6, seed: 99)
        let (first, group) = try XCTUnwrap(ops.scatter("c", center: Vec3(10, 0, 10), settings: settings, in: document.scene))
        var again = Operations(ids: .sequential("op"))
        let (second, _) = try XCTUnwrap(again.scatter("c", center: Vec3(10, 0, 10), settings: settings, in: document.scene))
        XCTAssertEqual(first, second, "same seed → same scatter")
        let applied = try assertReverts(first, on: document)
        let children = applied.scene.objects[group]?.children ?? []
        XCTAssertEqual(children.count, 20)
        XCTAssertNotNil(applied.scene.objects["c"], "source stays where it was")
        for child in children {
            let world = applied.scene.worldTransform(of: child)
            XCTAssertLessThanOrEqual(Vec3(world.position.x - 10, 0, world.position.z - 10).length, 6 + 1e-9)
            let bottom = try XCTUnwrap(SceneBounds().worldBounds(of: child, in: applied.scene)).min.y
            XCTAssertEqual(bottom, 0, accuracy: 1e-6, "copies sit on the ground")
        }
        // Impossible spacing still terminates.
        let crowded = ScatterSettings(count: 500, radius: 0.5, spacing: 5)
        let (tight, tightGroup) = try XCTUnwrap(ops.scatter("c", center: .zero, settings: crowded, in: document.scene))
        var doc = document
        _ = try tight.apply(to: &doc)
        XCTAssertLessThan(doc.scene.objects[tightGroup]?.children.count ?? 0, 500)
        XCTAssertNil(ops.scatter("missing", center: .zero, settings: settings, in: document.scene))
    }

    func testAlignAndDistribute() throws {
        var document = makeDocument()
        document.scene.objects["d"] = SceneObject(id: "d", name: "D", kind: .primitive(.cube), transform: Transform(position: Vec3(10, 0, 5)))
        document.scene.roots.append("d")
        let aligned = try assertReverts(XCTUnwrap(ops.align(["a", "c", "d"], axis: .z, mode: .max, in: document.scene)), on: document)
        let bounds = SceneBounds()
        for id in ["c", "d"] {
            XCTAssertEqual(try XCTUnwrap(bounds.worldBounds(of: ObjectID(raw: id), in: aligned.scene)).max.z, 5.5, accuracy: 1e-6)
        }
        let centered = try assertReverts(XCTUnwrap(ops.align(["a", "c"], axis: .x, mode: .center, in: document.scene)), on: document)
        XCTAssertEqual(try XCTUnwrap(bounds.worldBounds(of: "c", in: centered.scene)).center.x, -0.5, accuracy: 1e-6)
        _ = try XCTUnwrap(ops.align(["a", "c"], axis: .y, mode: .min, in: document.scene))
        XCTAssertNil(ops.align(["a"], axis: .x, mode: .min, in: document.scene))

        let distributed = try assertReverts(XCTUnwrap(ops.distribute(["a", "c", "d"], axis: .x, in: document.scene)), on: document)
        XCTAssertEqual(try XCTUnwrap(bounds.worldBounds(of: "a", in: distributed.scene)).center.x, 4, accuracy: 1e-6)
        XCTAssertNil(ops.distribute(["a", "c"], axis: .x, in: document.scene))
    }

    func testSwapFitsTheBlockout() throws {
        var document = makeDocument()
        // A desk blockout: 1.6 × 0.75 × 0.8.
        document.scene.objects["c"]?.transform = Transform(position: Vec3(0, 0, 0), rotation: Quat(angle: 0.5, axis: .unitY), scale: Vec3(1.6, 0.75, 0.8))
        let desk = LibraryAsset(id: "desk", name: "Desk", format: .glb, file: "desk.glb",
                                bounds: Bounds(min: Vec3(-80, -37.5, -40), max: Vec3(80, 37.5, 40))) // authored in cm, centered pivot
        let command = try XCTUnwrap(Operations(library: LibraryManifest(assets: [desk])).swap("c", with: desk, in: document.scene))
        let applied = try assertReverts(command, on: document)
        let object = try XCTUnwrap(applied.scene.objects["c"])
        XCTAssertEqual(object.kind, .asset("desk"))
        XCTAssertEqual(object.name, "Desk")
        XCTAssertNil(object.color)
        XCTAssertEqual(object.transform.scale.x, 0.01, accuracy: 1e-9)
        XCTAssertTrue(object.transform.rotation.isApproximately(Quat(angle: 0.5, axis: .unitY)))
        let world = try XCTUnwrap(SceneBounds(library: LibraryManifest(assets: [desk])).worldBounds(of: "c", in: applied.scene))
        XCTAssertEqual(world.min.y, 0, accuracy: 1e-6, "base stays on the ground")
        XCTAssertNil(ops.swap("missing", with: desk, in: document.scene))
    }

    func testColorAndFlags() throws {
        let document = makeDocument()
        var withLight = document
        withLight.scene.objects["l"] = SceneObject(id: "l", name: "L", kind: .light(.point))
        withLight.scene.roots.append("l")
        let colored = try assertReverts(ops.setColor(["a", "c", "l"], .palette(4), in: withLight.scene), on: withLight)
        XCTAssertEqual(colored.scene.objects["c"]?.color, .palette(4))
        XCTAssertNil(colored.scene.objects["l"]?.color, "lights don't take surface colors")
        let hidden = try assertReverts(ops.setFlag(["a"], key: .visible, false), on: document)
        XCTAssertFalse(hidden.scene.isEffectivelyVisible("b"))
    }

    func testPrefabRoundTrip() throws {
        let document = makeDocument()
        let fragment = try XCTUnwrap(ops.prefabFragment(["a"], in: document.scene))
        XCTAssertEqual(fragment.objects.count, 2)
        let root = try XCTUnwrap(fragment.objects.first { fragment.roots.contains($0.id) })
        XCTAssertTrue(root.transform.position.isApproximately(.zero), "prefab is centred on its base")
        let prefab = Prefab(id: "pf", name: "Cube with ball", fragment: fragment)
        let (replace, instanceID) = try XCTUnwrap(ops.replaceWithPrefab(["a"], prefab: prefab, in: document.scene))
        let replaced = try assertReverts(replace, on: document)
        XCTAssertNil(replaced.scene.objects["a"])
        XCTAssertEqual(replaced.scene.objects[instanceID]?.kind, .prefab("pf"))
        let library = LibraryManifest(prefabs: [prefab])
        let instanceBounds = try XCTUnwrap(SceneBounds(library: library).worldBounds(of: instanceID, in: replaced.scene))
        let originalBounds = try XCTUnwrap(SceneBounds().worldBounds(of: "a", in: document.scene))
        XCTAssertTrue(instanceBounds.min.isApproximately(originalBounds.min))
        XCTAssertTrue(instanceBounds.max.isApproximately(originalBounds.max))

        let unpack = try XCTUnwrap(ops.unpack(instanceID, prefab: prefab, in: replaced.scene))
        let unpacked = try assertReverts(unpack, on: replaced)
        let unpackedBounds = try XCTUnwrap(SceneBounds().worldBounds(of: unpacked.scene.roots, in: unpacked.scene))
        XCTAssertTrue(unpackedBounds.min.isApproximately(SceneBounds().worldBounds(of: document.scene.roots, in: document.scene)!.min))
        XCTAssertNil(ops.prefabFragment([], in: document.scene))
        XCTAssertNil(ops.replaceWithPrefab([], prefab: prefab, in: document.scene))
        XCTAssertNil(ops.unpack("missing", prefab: prefab, in: document.scene))
    }

    func testSnapping() {
        XCTAssertEqual(Snapping.snapToGrid(0.37, size: 0.25), 0.25)
        XCTAssertEqual(Snapping.snapToGrid(0.38, size: 0.25), 0.5)
        XCTAssertEqual(Snapping.snapToGrid(0.38, size: 0), 0.38)
        XCTAssertEqual(Snapping.snapToGrid(Vec3(0.3, 0.3, 0.3), size: 0.5), Vec3(0.5, 0.3, 0.5))
        XCTAssertEqual(Snapping.snapToGrid(Vec3(0.3, 0.3, 0.3), size: 0.5, includeY: true), Vec3(0.5, 0.5, 0.5))
        XCTAssertEqual(Snapping.snapAngle(22, step: 15), 15)
        XCTAssertEqual(Snapping.snapAngle(23, step: 15), 30)
        XCTAssertEqual(Snapping.snapAngle(23, step: 0), 23)
        // Box almost touching the right face of another box snaps flush.
        let other = Bounds(min: Vec3(0, 0, 0), max: Vec3(1, 1, 1))
        let moving = Bounds(min: Vec3(1.05, 0.02, 0), max: Vec3(2.05, 1.02, 1))
        let offset = Snapping.objectSnapOffset(moving: moving, others: [other], threshold: 0.1)
        XCTAssertEqual(offset.x, -0.05, accuracy: 1e-9)
        XCTAssertEqual(offset.y, -0.02, accuracy: 1e-9)
        // Far away: no snap.
        XCTAssertEqual(Snapping.objectSnapOffset(moving: moving.transformed(by: Transform(position: Vec3(5, 5, 5))), others: [other], threshold: 0.1), .zero)
        let settings = SnapSettings()
        XCTAssertTrue(settings.ground)
    }

    func testSceneBoundsKinds() throws {
        let bounds = SceneBounds()
        XCTAssertNil(bounds.localBounds(of: SceneObject(id: "g", name: "g", kind: .group)))
        XCTAssertNotNil(bounds.localBounds(of: SceneObject(id: "l", name: "l", kind: .light(.point))))
        XCTAssertEqual(bounds.localBounds(of: SceneObject(id: "x", name: "x", kind: .asset("unknown"))), .unitBase)
        XCTAssertEqual(bounds.localBounds(of: SceneObject(id: "x", name: "x", kind: .prefab("unknown"))), .unitBase)
        let recipe = DrawingRecipe(style: .tube, strokes: [.init(points: [.zero, Vec3(0, 2, 0)], widths: [0.1, 0.1])])
        let drawn = try XCTUnwrap(bounds.localBounds(of: SceneObject(id: "d", name: "d", kind: .drawing(recipe))))
        XCTAssertEqual(drawn.max.y, 2.0, accuracy: 0.01, "flat caps end at the last point")
        XCTAssertNil(bounds.worldBounds(of: [], in: makeDocument().scene))
    }
}
