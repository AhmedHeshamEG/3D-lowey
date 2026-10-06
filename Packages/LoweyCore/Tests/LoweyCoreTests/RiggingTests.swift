import Foundation
@testable import LoweyCore
import XCTest

/// Drawn bones, bone heat, the one skeleton system and its IK (M7).
final class RiggingTests: XCTestCase {
    // MARK: Fixtures

    /// The creature, imported from its GLB as anyone's model would be: every part in the model's space, as one surface.
    static func importedCreature() throws -> MeshData {
        let model = try GLTFMeshReader.model(data: RigSamples.creatureGLB())
        var mesh = MeshData()
        for part in model.parts {
            mesh.append(part.mesh)
        }
        return mesh
    }

    /// One stroke along the tail, seen from above: a ray into the model for every Pencil sample (with a wobbly hand).
    static func tailStroke() -> [Ray] {
        stride(from: RigSamples.tailStart + 0.12, through: RigSamples.tailEnd - 0.03, by: 0.02).enumerated().map { index, x in
            Ray(origin: Vec3(x, 3, 0.012 * sin(Double(index) * 0.7)), direction: Vec3(0, -1, 0))
        }
    }

    static func scene(with object: SceneObject) -> Scene {
        var scene = Scene(id: "s", name: "S")
        scene.objects[object.id] = object
        scene.roots = [object.id]
        return scene
    }

    static func applied(_ changes: [PropertyChange], to scene: Scene) -> Scene {
        var result = scene
        for change in changes {
            result.objects[change.object]?.properties[change.key] = change.value
        }
        return result
    }

    /// The creature with one drawn tail bone and its weights.
    static func riggedCreature() throws -> (scene: Scene, mesh: MeshData, weights: SkinWeights) {
        let mesh = try importedCreature()
        let bvh = TriangleBVH(mesh)
        let samples = BoneStroke.centreline(rays: tailStroke(), surface: bvh)
        let positions = mesh.positions.map { Vec3(Double($0.x), Double($0.y), Double($0.z)) }
        let rig = try BoneStroke.addingChain(samples, to: nil, surface: positions)
        var object = SceneObject(id: "creature", name: "Creature", kind: .asset("creature"))
        let weights = BoneHeat.weights(BoneHeat.Surface(mesh), segments: rig.segments, jointCount: rig.skeleton.joints.count, visibility: bvh)
        object.rig = RigOperations.stored(weights, in: rig, object: object, mesh: mesh).rig
        return (scene(with: object), mesh, weights)
    }

    static func skinned(_ mesh: MeshData, weights: SkinWeights, rig: ObjectRig, object: SceneObject) -> [Vec3] {
        let pose = RigPoses.posed(rig.skeleton.restPose, skeleton: rig.skeleton, by: object)
        let points = mesh.positions.map { Vec3(Double($0.x), Double($0.y), Double($0.z)) }
        return Skinning.deform(points, weights: weights, bind: rig.skeleton.modelRest, pose: rig.skeleton.modelSpace(pose))
    }

    // MARK: Drawing a bone

    func testAStrokeThroughTheTailBecomesAChainDownItsMiddle() throws {
        let mesh = try Self.importedCreature()
        let samples = BoneStroke.centreline(rays: Self.tailStroke(), surface: TriangleBVH(mesh))
        XCTAssertEqual(samples.count, Self.tailStroke().count, "every sample crosses the tail")
        for sample in samples {
            XCTAssertEqual(sample.point.y, RigSamples.tailHeight, accuracy: 0.01, "midway through the tail, not on its skin")
            XCTAssertGreaterThan(sample.thickness, 0.04)
        }
        let positions = mesh.positions.map { Vec3(Double($0.x), Double($0.y), Double($0.z)) }
        let rig = try BoneStroke.addingChain(samples, to: nil, surface: positions)
        XCTAssertEqual(rig.skeleton.joints[0].name, "root")
        XCTAssertLessThan(rig.restPositions[0].x, 0.1, "the root sits in the body")
        let chain = Array(rig.restPositions.dropFirst())
        XCTAssertGreaterThanOrEqual(chain.count, 4)
        XCTAssertLessThan(chain[0].x, chain[chain.count - 1].x, "the chain starts at the body end")
        XCTAssertEqual(rig.skeleton.joints[1].parent, 0)
        // A second stroke hangs from the chain it starts on.
        let again = try BoneStroke.addingChain([BoneStroke.Sample(point: chain[2], thickness: 0.1),
                                                BoneStroke.Sample(point: chain[2] + Vec3(0, 0.4, 0), thickness: 0.1)],
                                               to: rig, surface: positions)
        XCTAssertEqual(again.skeleton.joints.count, rig.skeleton.joints.count + 4, "a short stroke is three bones")
        XCTAssertEqual(again.skeleton.joints[rig.skeleton.joints.count].parent.map { again.skeleton.joints[$0].name }, rig.skeleton.joints[2].name)
        XCTAssertThrowsError(try BoneStroke.addingChain([], to: nil, surface: positions))
    }

    func testBoneHeatFallsOffSmoothlyAlongTheChain() throws {
        let tube = RigSamples.tube(from: 0, to: 2, height: 0, radius: (0.1, 0.1), rings: 40, sides: 10)
        let rig = ObjectRig(names: ["a", "b", "c"], parents: [nil, 0, 1], positions: [Vec3(0, 0, 0), Vec3(1, 0, 0), Vec3(2, 0, 0)])
        let weights = BoneHeat.weights(BoneHeat.Surface(tube), segments: rig.segments, jointCount: 3, visibility: TriangleBVH(tube))
        XCTAssertEqual(weights.count, tube.positions.count)
        var previous: Float = 1.1
        for ring in stride(from: 0, through: 40, by: 4) {
            let index = ring * 10
            let total = (0 ..< 4).reduce(Float(0)) { $0 + weights.weights[index][$1] }
            XCTAssertEqual(total, 1, accuracy: 1e-4)
            let first = weights.weight(of: 0, at: index)
            XCTAssertLessThanOrEqual(first, previous + 1e-3, "joint a's weight only falls along the tube")
            previous = first
        }
        XCTAssertGreaterThan(weights.weight(of: 0, at: 10), 0.95)
        XCTAssertGreaterThan(weights.weight(of: 1, at: 39 * 10), 0.95)
        XCTAssertEqual(weights.weight(of: 0, at: 20 * 10), 0.5, accuracy: 0.2, "the joint shares its weight across the bend")
    }

    /// The acceptance check: a tail drawn on an imported model bends naturally after one stroke.
    func testADrawnTailBendsNaturally() throws {
        let (scene, mesh, weights) = try Self.riggedCreature()
        let object = try XCTUnwrap(scene.objects["creature"])
        let rig = try XCTUnwrap(object.rig)
        // Drag the tail's tip up and forward over the back; the chain follows.
        let handles = IKHandles.handles(of: object.id, in: scene)
        let tip = try XCTUnwrap(handles.first { $0.isEnd })
        let start = try XCTUnwrap(IKHandles.position(of: tip, in: scene, pose: nil))
        XCTAssertEqual(start.x, rig.restPositions.last?.x ?? 0, accuracy: 1e-9)
        let target = Vec3(0.95, 1.35, 0)
        let posed = Self.applied(IKHandles.solve(tip, to: target, in: scene, rest: scene), to: scene)
        let reached = try XCTUnwrap(IKHandles.position(of: tip, in: posed, pose: nil))
        XCTAssertLessThan(reached.distance(to: target), 0.01, "the tip reaches where it was dragged")
        let moved = try Self.skinned(mesh, weights: weights, rig: rig, object: XCTUnwrap(posed.objects["creature"]))
        let original = mesh.positions.map { Vec3(Double($0.x), Double($0.y), Double($0.z)) }
        // The body holds still.
        for index in original.indices where original[index].x < 0.2 {
            XCTAssertLessThan(moved[index].distance(to: original[index]), 1e-3, "body vertex \(index) moved")
        }
        // The tail bends as a curve: each ring stays round and turns a little from the one before.
        let rings = Self.rings(original: original, moved: moved)
        var turned = 0.0
        for index in 2 ..< rings.count {
            let a = (rings[index - 1].centre - rings[index - 2].centre).normalized
            let b = (rings[index].centre - rings[index - 1].centre).normalized
            let angle = acos(min(max(a.dot(b), -1), 1)) * 180 / .pi
            XCTAssertLessThan(angle, 30, "no kink between rings \(index - 1) and \(index)")
            turned += angle
        }
        XCTAssertGreaterThan(turned, 40, "the tail curls up")
        for ring in rings {
            XCTAssertEqual(ring.radius, ring.restRadius, accuracy: ring.restRadius * 0.25, "the tail keeps its thickness")
        }
        try assertGoldenPose(rings.map(\.centre), name: "drawn-tail")
    }

    struct Ring {
        var centre: Vec3
        var radius: Double
        var restRadius: Double
    }

    /// The tail's rings (vertices made at the same x), before and after.
    static func rings(original: [Vec3], moved: [Vec3]) -> [Ring] {
        let tail = original.indices.filter { original[$0].x > RigSamples.tailStart + 0.45 && original[$0].x < RigSamples.tailEnd - 1e-6 }
        let groups = Dictionary(grouping: tail) { (original[$0].x * 1000).rounded() }
        return groups.keys.sorted().compactMap { key in
            guard let members = groups[key], members.count >= 6 else { return nil }
            let centre = members.reduce(Vec3.zero) { $0 + moved[$1] } / Double(members.count)
            let rest = members.reduce(Vec3.zero) { $0 + original[$1] } / Double(members.count)
            let radius = members.reduce(0) { $0 + moved[$1].distance(to: centre) } / Double(members.count)
            let restRadius = members.reduce(0) { $0 + original[$1].distance(to: rest) } / Double(members.count)
            return Ring(centre: centre, radius: radius, restRadius: restRadius)
        }
    }

    /// Compares points with a recorded golden pose (`Fixtures/golden-<name>.json`); records it when it's missing.
    func assertGoldenPose(_ points: [Vec3], name: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let url = URL(fileURLWithPath: "\(file)").deletingLastPathComponent().appendingPathComponent("Fixtures/golden-\(name).json")
        guard let data = try? Data(contentsOf: url) else {
            try LoweyJSON.encode(points).write(to: url)
            return XCTFail("Recorded the golden pose \(url.lastPathComponent); check it and run again", file: file, line: line)
        }
        let golden = try LoweyJSON.decode([Vec3].self, from: data)
        XCTAssertEqual(golden.count, points.count, file: file, line: line)
        for (a, b) in zip(golden, points) {
            XCTAssertLessThan(a.distance(to: b), 2e-3, "pose differs from the golden one at \(a)", file: file, line: line)
        }
    }

    // MARK: The person rig

    /// The Kit's astronaut: its parts in the model's space as one surface, and where each part is.
    static func astronaut() throws -> (mesh: MeshData, parts: [String: Bounds]) {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("App/Resources/Kit/Space/space-astronauta.loweyasset/model.glb")
        let model = try GLTFMeshReader.model(contentsOf: root)
        var mesh = MeshData()
        var parts: [String: Bounds] = [:]
        for part in model.parts {
            mesh.append(part.mesh)
            if let bounds = part.mesh.bounds { parts[part.name] = parts[part.name].map { $0.union(bounds) } ?? bounds }
        }
        return (mesh, parts)
    }

    /// Where a person would put the dots on the astronaut's front view: at its parts' joints.
    static func astronautDots(_ parts: [String: Bounds]) throws -> [HumanRig.Dot: Vec3] {
        func part(_ keyword: String, left: Bool?) throws -> Bounds {
            let matches = parts.filter { $0.key.lowercased().contains(keyword) }.map(\.value)
            guard let left else { return try XCTUnwrap(matches.first) }
            return try XCTUnwrap(left ? matches.max { $0.center.x < $1.center.x } : matches.min { $0.center.x < $1.center.x })
        }
        let head = try part("head", left: nil)
        var dots: [HumanRig.Dot: Vec3] = [.head: Vec3(head.center.x, head.max.y, 0), .chin: Vec3(head.center.x, head.min.y + head.size.y * 0.15, 0)]
        for (side, left) in [("left", true), ("right", false)] {
            let arm = try part("arm", left: left)
            let leg = try part("leg", left: left)
            func dot(_ name: String) -> HumanRig.Dot? { HumanRig.Dot(rawValue: side + name) }
            let armX = arm.center.x
            dots[dot("Shoulder")!] = Vec3(armX, arm.max.y - arm.size.y * 0.15, 0)
            dots[dot("Elbow")!] = Vec3(armX, arm.max.y - arm.size.y * 0.5, 0)
            dots[dot("Wrist")!] = Vec3(armX, arm.min.y + arm.size.y * 0.15, 0)
            dots[dot("Hip")!] = Vec3(leg.center.x, leg.max.y - leg.size.y * 0.1, 0)
            dots[dot("Knee")!] = Vec3(leg.center.x, leg.min.y + leg.size.y * 0.5, 0)
            dots[dot("Ankle")!] = Vec3(leg.center.x, leg.min.y + leg.size.y * 0.15, 0)
        }
        return dots
    }

    /// The acceptance check: the person rig (from its dots) makes a Kit humanoid walk with the built-in clip.
    func testAKitHumanoidWalksWithTheBuiltInClipOnceRiggedAsAPerson() throws {
        let (mesh, parts) = try Self.astronaut()
        let bounds = try XCTUnwrap(mesh.bounds)
        let bvh = TriangleBVH(mesh)
        let rays = try Self.astronautDots(parts).mapValues { Ray(origin: Vec3($0.x, $0.y, bounds.max.z + 5), direction: Vec3(0, 0, -1)) }
        let points = HumanRig.points(rays: rays, surface: bvh, bounds: bounds)
        XCTAssertEqual(points.count, HumanRig.Dot.allCases.count)
        let rig = try XCTUnwrap(HumanRig.rig(from: points, bounds: bounds))
        XCTAssertEqual(Set(rig.skeleton.names), Set(SkeletonStandard.humanoid.bones))
        var object = SceneObject(id: "astro", name: "Astronaut", kind: .asset("kit.space-astronauta"))
        let weighted = try XCTUnwrap(RigOperations.weighted(rig, object: object, mesh: mesh))
        object.rig = weighted.rig
        let weights = try SkinWeights(data: XCTUnwrap(weighted.files.values.first))
        var document = makeDocument()
        document.scene = Self.scene(with: object)
        let walk = ClipSegment(id: "walk", clip: ClipRef(asset: BuiltinClips.assetID, name: "Walk"), start: 0, duration: 4)
        document.scene.timeline.clipTracks = [ClipTrack(id: "t", target: object.id, segments: [walk])]
        let original = mesh.positions.map { Vec3(Double($0.x), Double($0.y), Double($0.z)) }
        let feet = original.indices.filter { original[$0].y < bounds.min.y + bounds.size.y * 0.06 }
        let leftFoot = feet.filter { original[$0].x > bounds.center.x }
        let rightFoot = feet.filter { original[$0].x < bounds.center.x }
        XCTAssertFalse(leftFoot.isEmpty || rightFoot.isEmpty)
        let duration = try XCTUnwrap(BuiltinClips.rig.clips["Walk"]?.duration)
        var gaps: [Double] = []
        for step in 0 ..< 12 {
            let time = duration * Double(step) / 12
            let frame = Animator.evaluate(document, at: time)
            let pose = try XCTUnwrap(frame.poses[object.id], "the walk poses the drawn skeleton")
            let moved = Skinning.deform(original, weights: weights, bind: rig.skeleton.modelRest, pose: rig.skeleton.modelSpace(pose))
            func meanZ(_ indices: [Int]) -> Double { indices.reduce(0) { $0 + moved[$1].z } / Double(indices.count) }
            gaps.append(meanZ(leftFoot) - meanZ(rightFoot))
            // It stays in one piece: nothing flies off.
            for index in moved.indices {
                XCTAssertLessThan(moved[index].distance(to: original[index]), bounds.size.y * 0.6)
            }
        }
        // The feet take turns in front: the gap between them swings both ways by a real step.
        XCTAssertGreaterThan(gaps.max() ?? 0, bounds.size.y * 0.05, "the left foot steps forward")
        XCTAssertLessThan(gaps.min() ?? 0, -bounds.size.y * 0.05, "the right foot steps forward")
    }

    func testDotsMirrorAndTheTemplateStandsInsideTheModel() {
        let bounds = Bounds(min: Vec3(-0.4, 0, -0.2), max: Vec3(0.4, 1.8, 0.2))
        let template = HumanRig.template(bounds: bounds)
        XCTAssertEqual(template.count, HumanRig.Dot.allCases.count)
        for point in template.values {
            XCTAssertTrue(bounds.contains(point, tolerance: 1e-9))
        }
        XCTAssertGreaterThan(template[.leftWrist]?.x ?? 0, 0, "the character's left is +x")
        let placed: Set<HumanRig.Dot> = Set(HumanRig.tapped)
        XCTAssertEqual(placed.count, 8)
        var dots = template
        dots[.leftElbow] = Vec3(0.3, 1.1, 0.05)
        let mirrored = HumanRig.mirrored(dots, from: placed, centreX: 0)
        XCTAssertEqual(mirrored[.rightElbow], Vec3(-0.3, 1.1, 0.05))
        XCTAssertEqual(mirrored[.head], dots[.head])
        XCTAssertNil(HumanRig.rig(from: [.head: .zero], bounds: bounds), "every dot is needed")
    }

    // MARK: 2D drawn puppets

    /// A drawn arm on a plane: an upper arm and a forearm as ink strokes, and a bone drawn through it.
    func testADrawnPuppetBendsItsStrokes() throws {
        let upper = DrawingRecipe.Stroke(points: (0 ... 10).map { Vec3(Double($0) * 0.05, 0, 0) }, widths: Array(repeating: 0.01, count: 11))
        let lower = DrawingRecipe.Stroke(points: (0 ... 10).map { Vec3(0.5 + Double($0) * 0.05, 0.002, 0) }, widths: Array(repeating: 0.01, count: 11))
        let recipe = DrawingRecipe(style: .ink, strokes: [upper, lower], normal: .unitZ)
        var object = SceneObject(id: "arm", name: "Arm", kind: .drawing(recipe))
        let plane = RigOperations.drawingPlane(recipe)
        XCTAssertEqual(plane.normal, .unitZ)
        let rays = stride(from: 0.0, through: 1.0, by: 0.05).map { Ray(origin: Vec3($0, 0, 2), direction: Vec3(0, 0, -1)) }
        let samples = BoneStroke.onPlane(rays: rays, origin: plane.origin, normal: plane.normal)
        let rig = try BoneStroke.addingChain(samples, to: nil, surface: recipe.strokes.flatMap(\.points))
        let weighted = try XCTUnwrap(RigOperations.weighted(rig, object: object, mesh: nil))
        XCTAssertTrue(weighted.files.isEmpty, "a drawing keeps its weights inline")
        XCTAssertEqual(weighted.rig.points?.count, 22)
        object.rig = weighted.rig
        XCTAssertTrue(RigOperations.fits(weighted.rig, object: object, mesh: nil))
        // Bend the end of the chain round; the far end of the drawing follows, the near end stays.
        var document = makeDocument()
        document.scene = Self.scene(with: object)
        let tip = try XCTUnwrap(IKHandles.handles(of: object.id, in: document.scene).first { $0.isEnd })
        let changes = IKHandles.solve(tip, to: Vec3(0.6, 0.5, 0), in: document.scene, rest: document.scene)
        document.scene = Self.applied(changes, to: document.scene)
        let frame = Animator.evaluate(document, at: 0)
        guard case let .drawing(bent)? = frame.scene.objects[object.id]?.kind else { return XCTFail("still a drawing") }
        XCTAssertTrue(frame.animated.contains(object.id))
        XCTAssertEqual(bent.strokes[0].points[0], recipe.strokes[0].points[0], "the shoulder end stays")
        XCTAssertGreaterThan(bent.strokes[1].points[10].y, 0.3, "the hand end swung up")
        // Unposed, the drawing is as drawn.
        var rest = document
        rest.scene = Self.scene(with: object)
        guard case let .drawing(same)? = Animator.evaluate(rest, at: 0).scene.objects[object.id]?.kind else { return XCTFail("a drawing") }
        for (a, b) in zip(same.strokes.flatMap(\.points), recipe.strokes.flatMap(\.points)) {
            XCTAssertLessThan(a.distance(to: b), 1e-9)
        }
    }

    // MARK: One skeleton system

    func testTheRigCommandRevertsAndSurvivesJSON() throws {
        let (scene, _, weights) = try Self.riggedCreature()
        let rig = try XCTUnwrap(scene.objects["creature"]?.rig)
        var document = makeDocument()
        try assertReverts(.setRig("a", rig), on: document)
        document.scene.objects["a"]?.rig = rig
        try assertReverts(.setRig("a", nil), on: document)
        XCTAssertEqual(try SkinWeights(data: weights.data), weights)
        XCTAssertThrowsError(try SkinWeights(data: Data("nope".utf8)))
        let encoded = try LoweyJSON.encode(rig)
        XCTAssertEqual(try LoweyJSON.decode(ObjectRig.self, from: encoded), rig)
        XCTAssertEqual(EditCommand.setRig("a", rig).label, "Rig")
        XCTAssertEqual(PropertyKey.boneTurn("j3").boneJoint, "j3")
        XCTAssertNil(PropertyKey.rotation.boneJoint)
    }

    func testPosesOfADrawnRigSaveApplyAndReset() throws {
        let (scene, _, _) = try Self.riggedCreature()
        let rig = try XCTUnwrap(CharacterRig.of("creature", in: scene))
        XCTAssertEqual(rig.body, .bones)
        XCTAssertEqual(PoseLibrary.character(of: "creature", in: scene), "creature")
        let turns = [2: Quat(angle: 0.6, axis: .unitZ), 3: Quat(angle: 0.4, axis: .unitZ)]
        let posed = Self.applied(rig.changes(turning: turns), to: scene)
        let pose = PoseLibrary.capture("creature", in: posed, id: "curl", name: "Curl")
        XCTAssertEqual(pose.joints.count, rig.skeleton.joints.count)
        let name2 = rig.skeleton.joints[2].name
        XCTAssertTrue(try XCTUnwrap(pose.joints[name2]).isApproximately(Quat(angle: 0.6, axis: .unitZ)))
        let reset = Self.applied(rig.resetting(in: posed), to: posed)
        XCTAssertFalse(reset.objects["creature"]?.properties.keys.contains { $0.boneJoint != nil } ?? true)
        let again = Self.applied(PoseLibrary.applying(pose, to: "creature", in: reset), to: reset)
        XCTAssertTrue(try XCTUnwrap(again.objects["creature"]?[.boneTurn(name2)]?.quatValue).isApproximately(Quat(angle: 0.6, axis: .unitZ)))
    }

    func testChainIKReachesAndBendsAStraightChain() {
        let rig = ObjectRig(names: ["a", "b", "c", "d"], parents: [nil, 0, 1, 2], positions: [.zero, Vec3(1, 0, 0), Vec3(2, 0, 0), Vec3(3, 0, 0)])
        let target = Vec3(2, 1, 0)
        let turns = ChainIK.solve(chain: [0, 1, 2, 3], skeleton: rig.skeleton, local: rig.skeleton.restPose, target: target)
        var local = rig.skeleton.restPose
        for (joint, rotation) in turns {
            local[joint].rotation = rotation
        }
        let model = rig.skeleton.modelSpace(local)
        XCTAssertLessThan(model[3].position.distance(to: target), 1e-3)
        XCTAssertEqual(model[0].position, .zero)
        for index in 1 ..< 4 {
            XCTAssertEqual(model[index].position.distance(to: model[index - 1].position), 1, accuracy: 1e-6, "bones keep their length")
        }
        // Out of reach: the chain points straight at it.
        let far = ChainIK.solve(chain: [0, 1, 2, 3], skeleton: rig.skeleton, local: rig.skeleton.restPose, target: Vec3(0, 10, 0))
        var stretched = rig.skeleton.restPose
        for (joint, rotation) in far {
            stretched[joint].rotation = rotation
        }
        XCTAssertEqual(rig.skeleton.modelSpace(stretched)[3].position.y, 3, accuracy: 1e-6)
    }

    func testWeightPaintingAddsAndTakesAway() throws {
        let rig = ObjectRig(names: ["a", "b"], parents: [nil, 0], positions: [.zero, Vec3(1, 0, 0)], tips: ["b": Vec3(2, 0, 0)])
        let tube = RigSamples.tube(from: 0, to: 2, height: 0, radius: (0.1, 0.1), rings: 20, sides: 8)
        let positions = tube.positions.map { Vec3(Double($0.x), Double($0.y), Double($0.z)) }
        let weights = BoneHeat.weights(BoneHeat.Surface(tube), segments: rig.segments, jointCount: 2)
        let near = try XCTUnwrap(positions.indices.min { positions[$0].distance(to: Vec3(0.2, 0.1, 0)) < positions[$1].distance(to: Vec3(0.2, 0.1, 0)) })
        let before = weights.weight(of: 1, at: near)
        let painted = WeightPaint.apply([WeightPaint.Dab(centre: Vec3(0.2, 0.1, 0), radius: 0.3, amount: 0.8)], joint: 1, erase: false, to: weights,
                                        positions: positions)
        XCTAssertGreaterThan(painted.weight(of: 1, at: near), before + 0.5)
        XCTAssertEqual(painted.weight(of: 0, at: near) + painted.weight(of: 1, at: near), 1, accuracy: 1e-4)
        let far = try XCTUnwrap(positions.indices.max { positions[$0].x < positions[$1].x })
        XCTAssertEqual(painted.weight(of: 1, at: far), weights.weight(of: 1, at: far), "outside the brush nothing changes")
        let erased = WeightPaint.apply([WeightPaint.Dab(centre: Vec3(0.2, 0.1, 0), radius: 0.3, amount: 1)], joint: 1, erase: true, to: painted,
                                       positions: positions)
        XCTAssertLessThan(erased.weight(of: 1, at: near), 0.05)
    }
}
