import Foundation
import HmmPerception

/// The rendered frame's pixels (8-bit, four per pixel, top row first), for the measures that need to see colour:
/// contrast, silhouette, palette, light. Everything else is measured from geometry.
public struct ObservePixels: Sendable {
    public var width: Int
    public var height: Int
    public var bytes: [UInt8]
    /// Channel order: RGBA is (0, 1, 2); BGRA (the renderer's) is (2, 1, 0).
    public var redIndex: Int
    public var greenIndex: Int
    public var blueIndex: Int
    /// What the renderer drew at each pixel, when it can say: the object (its id) per pixel, same size, top row first.
    /// Pixel measures then use it instead of the analysis raster (exact, and posed for skinned characters).
    public var objects: [String?]?

    public init(width: Int, height: Int, bytes: [UInt8], bgra: Bool = false) {
        self.width = width
        self.height = height
        self.bytes = bytes
        redIndex = bgra ? 2 : 0
        greenIndex = 1
        blueIndex = bgra ? 0 : 2
    }

    /// The object drawn around a normalised point (nil: none, or no object buffer).
    func object(x: Double, y: Double) -> String? {
        guard let objects else { return nil }
        let column = min(max(Int(x * Double(width)), 0), width - 1)
        let row = min(max(Int(y * Double(height)), 0), height - 1)
        let index = row * width + column
        return index < objects.count ? objects[index] : nil
    }

    /// The colour (0…1) around a normalised point.
    func color(x: Double, y: Double) -> (red: Double, green: Double, blue: Double) {
        let column = min(max(Int(x * Double(width)), 0), width - 1)
        let row = min(max(Int(y * Double(height)), 0), height - 1)
        let base = (row * width + column) * 4
        guard base + 3 < bytes.count else { return (0, 0, 0) }
        return (Double(bytes[base + redIndex]) / 255, Double(bytes[base + greenIndex]) / 255, Double(bytes[base + blueIndex]) / 255)
    }
}

/// `observe`: looks at a shot the way a director checks a frame and reports it in numbers (PROMPT §12.1). Geometry
/// comes from the scene at that moment (the renderer can hand in the meshes it drew, so loaded models are exact);
/// colour measures come from the rendered pixels when there are some.
public struct ShotObserver {
    public var document: Document
    public var library: LibraryManifest
    public var rigs: [AssetID: RigAsset]
    /// World-space geometry of one node as drawn at the observed moment (nil: Core's own mesh, else its box).
    public var meshes: (ObjectID) -> MeshData?

    public init(document: Document, library: LibraryManifest = LibraryManifest(), rigs: [AssetID: RigAsset] = [:],
                meshes: @escaping (ObjectID) -> MeshData? = { _ in nil }) {
        self.document = document
        self.library = library
        self.rigs = rigs
        self.meshes = meshes
    }

    /// The shot camera at `time` for a frame of `aspect`.
    public func camera(at time: Double, aspect: Double) -> ObserveCamera {
        ObserveCamera.shot(Animator.evaluate(document, at: time, rigs: rigs), fallback: document.scene.viewpoint, aspect: aspect)
    }

    /// Measures the shot at `time`. `subject` names the subject (else the obvious one is chosen and said so).
    public func observe(at time: Double, aspect: Double = 16.0 / 9.0, subject: String? = nil, pixels: ObservePixels? = nil) -> ShotReport {
        let animated = Animator.evaluate(document, at: time, rigs: rigs)
        let camera = ObserveCamera.shot(animated, fallback: document.scene.viewpoint, aspect: aspect)
        let (measured, raster) = measure(animated.scene, camera: camera)
        let subjectID = chooseSubject(subject, measured: measured, scene: animated.scene)
        var objects = measured.map(\.object)
        let contacts = ContactCheck(scene: animated.scene, library: library, units: measured.map(\.id), triangles: measured.map(\.triangles))
        for index in objects.indices {
            // Set pieces (floor, walls, terrain) are built overlapping; only props meeting them, or each other, count.
            objects[index].intersects = contacts.intersecting(index).filter { other in
                !(measured[other].object.isSet && objects[index].isSet) && !Self.rests(measured[index], on: measured[other])
                    && !Self.rests(measured[other], on: measured[index])
            }.map { measured[$0].object.name }
        }
        var frame = frameRead(measured, subject: subjectID, declared: subject != nil, camera: camera, scene: animated.scene)
        if let pixels {
            readPixels(pixels, raster: pixelRaster(pixels, like: raster, units: measured, scene: animated.scene), units: measured, subject: subjectID,
                       objects: &objects, frame: &frame)
        }
        let checks = ShotRubric.evaluate(objects: objects, frame: frame, scaleIssues: scaleIssues(measured, scene: animated.scene))
        let cameraName = animated.camera.flatMap { animated.scene.objects[$0]?.name } ?? "the editor view"
        return ShotReport(scene: document.scene.name, time: time, camera: cameraName, aspect: aspect, objects: objects, frame: frame,
                          checks: checks, summary: Self.summary(objects: objects, frame: frame, checks: checks, camera: cameraName))
    }

    /// A prop standing on a set piece (a log on the grass, a rock on the cave floor): its bottom within a few centimetres
    /// of the set's top. Real meshes aren't flat underneath; that isn't an intersection.
    static func rests(_ prop: Measured, on set: Measured) -> Bool {
        set.object.isSet && !prop.object.isSet && abs(prop.world.min.y - set.world.max.y) < 0.06
    }

    /// The analysis raster's labels taken from the renderer's object buffer (each drawn node mapped to its labelled
    /// unit), when the pixels come with one; otherwise the raster itself.
    func pixelRaster(_ pixels: ObservePixels, like raster: CoverageRaster, units: [Measured], scene: Scene) -> CoverageRaster {
        guard pixels.objects != nil else { return raster }
        var unitOf: [String: Int32] = [:]
        for unit in units {
            for node in scene.subtree(of: unit.id) {
                unitOf[node.raw] = unit.label
            }
        }
        var labels = [Int32](repeating: -1, count: raster.width * raster.height)
        for row in 0 ..< raster.height {
            for column in 0 ..< raster.width {
                let id = pixels.object(x: (Double(column) + 0.5) / Double(raster.width), y: (Double(row) + 0.5) / Double(raster.height))
                labels[row * raster.width + column] = id.flatMap { unitOf[$0] } ?? -1
            }
        }
        return CoverageRaster(width: raster.width, height: raster.height, labels: labels)
    }

    /// The labelled things of a scene: each root, a plain group's children instead of the group, a character whole.
    /// Lights, cameras, overlays, particles and hidden things aren't labelled.
    public static func units(in scene: Scene) -> [ObjectID] {
        var result: [ObjectID] = []
        func visit(_ id: ObjectID) {
            guard let object = scene.objects[id], object.isVisible else { return }
            switch object.kind {
            case .light, .camera, .overlay, .particles:
                return
            case .group where !CharacterOutline.isCharacter(id, in: scene):
                object.children.forEach(visit)
            default:
                result.append(id)
            }
        }
        scene.roots.forEach(visit)
        return result
    }

    /// In the air on purpose: marked so, or 3D words (they hang like signs).
    static func isAirborne(_ object: SceneObject) -> Bool {
        if case .text = object.kind { return true }
        return object[.airborne]?.boolValue == true
    }

    /// World-space triangles (three points each) of a unit and everything under it.
    func triangles(of unit: ObjectID, in scene: Scene, bounds: SceneBounds) -> [Vec3] {
        var result: [Vec3] = []
        for node in scene.subtree(of: unit) {
            guard let object = scene.objects[node], object.isVisible, object.kind.hasSurface else { continue }
            if let mesh = meshes(node) ?? coreMesh(object, world: scene.worldTransform(of: node)), !mesh.isEmpty {
                result += mesh.indices.map { index in
                    let p = mesh.positions[Int(index)]
                    return Vec3(Double(p.x), Double(p.y), Double(p.z))
                }
            } else if let local = bounds.localBounds(of: object) {
                let world = scene.worldTransform(of: node)
                result += Self.boxTriangles(local).map { world.apply(to: $0) }
            }
        }
        return result
    }

    /// Core's own mesh of an object in world space (shapes and drawings; models come from the renderer).
    func coreMesh(_ object: SceneObject, world: Transform) -> MeshData? {
        switch object.kind {
        case let .primitive(shape): PrimitiveMesh.make(shape).transformed(world)
        case let .drawing(recipe): DrawingMesher.mesh(for: recipe).transformed(world)
        case let .mesh(mesh): mesh.renderMesh().transformed(world)
        default: nil
        }
    }

    /// The twelve triangles of a box.
    static func boxTriangles(_ box: Bounds) -> [Vec3] {
        let c = box.corners
        let faces = [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
        return faces.flatMap { face in [c[face[0]], c[face[1]], c[face[2]], c[face[0]], c[face[2]], c[face[3]]] }
    }
}

// MARK: - Measuring

extension ShotObserver {
    /// One labelled thing as measured.
    struct Measured {
        var id: ObjectID
        var label: Int32
        var object: ObservedObject
        var triangles: [Vec3]
        var world: Bounds
        /// Where its projected geometry reaches, unclipped (beyond 0…1 when the frame cuts it).
        var extent: PerceptionRect
    }

    func measure(_ scene: Scene, camera: ObserveCamera) -> (measured: [Measured], raster: CoverageRaster) {
        let bounds = SceneBounds(library: library)
        let units = Self.units(in: scene)
        var raster = CoverageRaster(aspect: camera.aspect)
        var candidates: [(id: ObjectID, triangles: [Vec3], world: Bounds)] = []
        for (index, unit) in units.enumerated() {
            let triangles = triangles(of: unit, in: scene, bounds: bounds)
            guard !triangles.isEmpty, let world = Bounds(points: triangles) else { continue }
            raster.draw(triangles, label: Int32(index), camera: camera)
            candidates.append((unit, triangles, world))
        }
        let solver = RelationSolver(scene: scene, library: library)
        let pixels = Double(raster.width * raster.height)
        var result: [Measured] = []
        for candidate in candidates {
            guard let index = units.firstIndex(of: candidate.id) else { continue }
            let label = Int32(index)
            let solo = raster.soloCounts[label] ?? 0
            let visible = raster.visibleCount(of: label)
            guard solo > 0, let object = scene.objects[candidate.id] else { continue }
            let extent = Self.extent(of: candidate.triangles, camera: camera)
            // Hidden behind something: still reported (visible 0), boxed where it would be.
            guard let box = visibleBox(raster, label: label) ?? extent.intersection(PerceptionRect(x: 0, y: 0, width: 1, height: 1)) else { continue }
            let ground = solver.isGrounded(candidate.id)
            let character = CharacterOutline.isCharacter(candidate.id, in: scene)
            let size = candidate.world.size
            let isSet = !character && (Double(solo) / pixels > 0.4 || max(size.x, size.z) > 6)
            let observed = ObservedObject(
                id: candidate.id.raw, name: object.name, mark: 0, box: box, coverage: Double(visible) / pixels * 100,
                visible: min(Double(visible) / Double(solo) * 100, 100), distance: (candidate.world.center - camera.position).length,
                grounded: ground.grounded || isSet, gap: isSet ? 0 : ground.gap * 100, airborne: Self.isAirborne(object), intersects: [],
                cutByFrame: extent.x < -0.001 || extent.y < -0.001 || extent.maxX > 1.001 || extent.maxY > 1.001,
                facing: facing(candidate.id, scene: scene, camera: camera, character: character), isCharacter: character,
                isAccent: object[.accent]?.boolValue == true, isSet: isSet, lightness: nil, contrast: nil
            )
            result.append(Measured(id: candidate.id, label: label, object: observed, triangles: candidate.triangles, world: candidate.world,
                                   extent: extent))
        }
        // Marks: biggest first, so the subject and the big things get the small numbers.
        result.sort { $0.object.coverage > $1.object.coverage }
        for index in result.indices {
            result[index].object.mark = index + 1
        }
        return (result, raster)
    }

    /// The box of a label's visible pixels, normalised.
    func visibleBox(_ raster: CoverageRaster, label: Int32) -> PerceptionRect? {
        var minX = Int.max
        var minY = Int.max
        var maxX = -1
        var maxY = -1
        for row in 0 ..< raster.height {
            for column in 0 ..< raster.width where raster.labels[row * raster.width + column] == label {
                minX = min(minX, column)
                maxX = max(maxX, column)
                minY = min(minY, row)
                maxY = max(maxY, row)
            }
        }
        guard maxX >= 0 else { return nil }
        let width = Double(raster.width)
        let height = Double(raster.height)
        return PerceptionRect(x: Double(minX) / width, y: Double(minY) / height, width: Double(maxX - minX + 1) / width,
                              height: Double(maxY - minY + 1) / height)
    }

    /// The projected reach of triangles (points behind the camera push it past the frame).
    static func extent(of triangles: [Vec3], camera: ObserveCamera) -> PerceptionRect {
        var minX = Double.infinity
        var minY = Double.infinity
        var maxX = -Double.infinity
        var maxY = -Double.infinity
        var behind = false
        for point in triangles {
            guard let projected = camera.project(point) else {
                behind = true
                continue
            }
            minX = min(minX, projected.x)
            maxX = max(maxX, projected.x)
            minY = min(minY, projected.y)
            maxY = max(maxY, projected.y)
        }
        guard minX.isFinite else { return PerceptionRect(x: -1, y: -1, width: 3, height: 3) }
        if behind {
            minX = min(minX, -0.01)
            maxX = max(maxX, 1.01)
        }
        return PerceptionRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Degrees between a unit's front and the way to the camera, on the ground plane.
    func facing(_ id: ObjectID, scene: Scene, camera: ObserveCamera, character: Bool) -> Double? {
        let kitFront = scene.objects[id]?.kind.assetID.flatMap { library.asset($0)?.kit?.front }
        guard let local = kitFront ?? (character ? Vec3(0, 0, 1) : nil) else { return nil }
        let world = scene.worldTransform(of: id)
        var front = world.rotation.act(local)
        var toCamera = camera.position - world.position
        front.y = 0
        toCamera.y = 0
        guard front.length > 1e-6, toCamera.length > 1e-6 else { return nil }
        let cosine = min(max(front.normalized.dot(toCamera.normalized), -1), 1)
        return acos(cosine) * 180 / .pi
    }

    /// The subject: the one named, else the biggest character in frame, else the biggest thing that isn't the set.
    func chooseSubject(_ name: String?, measured: [Measured], scene _: Scene) -> ObjectID? {
        if let name {
            let wanted = name.lowercased()
            if let match = measured.first(where: { $0.object.name.lowercased() == wanted || $0.id.raw == name }) { return match.id }
            if let match = measured.first(where: { $0.object.name.lowercased().hasPrefix(wanted) }) { return match.id }
        }
        return measured.first { $0.object.isCharacter && $0.object.coverage > 0.5 }?.id ?? measured.first { !$0.object.isSet }?.id
    }

    /// Kit models far from their real size.
    func scaleIssues(_ measured: [Measured], scene: Scene) -> [String] {
        measured.compactMap { unit -> String? in
            guard let kit = scene.objects[unit.id]?.kind.assetID.flatMap({ library.asset($0)?.kit }), kit.realSize.y > 0.01 else { return nil }
            let ratio = unit.world.size.y / kit.realSize.y
            guard ratio < 0.5 || ratio > 2 else { return nil }
            return "“\(unit.object.name)” is \(String(format: "%.1f", ratio))× its real height"
        }
    }
}
