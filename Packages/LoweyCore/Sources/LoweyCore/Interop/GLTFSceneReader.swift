import Foundation

/// Reads a glTF scene back into objects you can edit: a group or a modelled mesh per node (keeping the hierarchy and
/// each node's own transform), materials as colours, roughness, metal and glow, cameras, lights, and node animation as
/// timeline keys. Skins are left to the library (a rigged model is placed as a model, not taken apart).
public enum GLTFSceneReader {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case empty
        /// More triangles than modelling keeps smooth: place it as a library model instead.
        case tooBig(Int)

        public var description: String {
            switch self {
            case .empty: "That file has nothing to edit in it."
            case let .tooBig(count): "That model has \(count) triangles: too many to edit. It stays a library model."
            }
        }
    }

    /// The most triangles taken apart into editable meshes.
    public static let triangleLimit = 200_000

    public struct Result: Sendable {
        public var fragment: SceneFragment
        public var tracks: [Track]
        public var duration: Double
    }

    public static func read(_ data: Data, baseURL: URL? = nil, ids: inout IDFactory) throws -> Result {
        let file = try GLTFReader.parse(data, baseURL: baseURL)
        let triangles = try countTriangles(file)
        guard triangles <= triangleLimit else { throw Failure.tooBig(triangles) }
        var builder = Builder(file: file)
        let nodes = file.array("nodes")
        let scenes = file.array("scenes")
        let sceneIndex = file.json["scene"] as? Int ?? 0
        let rootNodes = sceneIndex < scenes.count ? scenes[sceneIndex]["nodes"] as? [Int] ?? [] : Array(nodes.indices)
        var roots: [ObjectID] = []
        for node in rootNodes {
            if let id = try builder.object(for: node, parent: nil, ids: &ids) { roots.append(id) }
        }
        guard !roots.isEmpty else { throw Failure.empty }
        let (tracks, duration) = try builder.tracks(ids: &ids)
        return Result(fragment: SceneFragment(objects: builder.objects, roots: roots), tracks: tracks, duration: duration)
    }

    static func countTriangles(_ file: GLTFReader.File) throws -> Int {
        var total = 0
        let accessors = file.array("accessors")
        for mesh in file.array("meshes") {
            for primitive in mesh["primitives"] as? [[String: Any]] ?? [] where (primitive["mode"] as? Int ?? 4) == 4 {
                if let index = primitive["indices"] as? Int, index < accessors.count {
                    total += (accessors[index]["count"] as? Int ?? 0) / 3
                } else if let position = (primitive["attributes"] as? [String: Any])?["POSITION"] as? Int, position < accessors.count {
                    total += (accessors[position]["count"] as? Int ?? 0) / 3
                }
            }
        }
        return total
    }

    /// Walks the nodes, making objects in parent-before-child order.
    struct Builder {
        let file: GLTFReader.File
        var objects: [SceneObject] = []
        var objectOf: [Int: ObjectID] = [:]

        init(file: GLTFReader.File) {
            self.file = file
        }

        mutating func object(for index: Int, parent: ObjectID?, ids: inout IDFactory) throws -> ObjectID? {
            let nodes = file.array("nodes")
            guard index < nodes.count, objectOf[index] == nil else { return nil }
            let node = nodes[index]
            let id: ObjectID = ids.next()
            objectOf[index] = id
            let name = GLTFReader.nodeName(node, index: index)
            var object = SceneObject(id: id, name: name, kind: .group, parent: parent, transform: GLTFReader.localTransform(node))
            let slot = objects.count
            objects.append(object)
            var children: [ObjectID] = []
            if let camera = node["camera"] as? Int {
                object.kind = .camera
                let cameras = file.array("cameras")
                if camera < cameras.count, let yfov = (cameras[camera]["perspective"] as? [String: Any])?["yfov"] as? Double {
                    object[.fieldOfView] = .float(yfov * 180 / .pi)
                }
            } else if let light = lightIndex(node) {
                applyLight(light, to: &object)
            } else if let mesh = node["mesh"] as? Int {
                let pieces = try meshPieces(mesh)
                if pieces.count == 1, let piece = pieces.first {
                    object.kind = .mesh(piece.mesh)
                    apply(piece.material, to: &object)
                } else {
                    // Several materials: one modelled child per material under this node.
                    for piece in pieces {
                        let child: ObjectID = ids.next()
                        var part = SceneObject(id: child, name: piece.name, kind: .mesh(piece.mesh), parent: id)
                        apply(piece.material, to: &part)
                        objects.append(part)
                        children.append(child)
                    }
                }
            }
            for child in node["children"] as? [Int] ?? [] {
                if let childID = try self.object(for: child, parent: id, ids: &ids) { children.append(childID) }
            }
            object.children = children
            objects[slot] = object
            return id
        }

        func lightIndex(_ node: [String: Any]) -> Int? {
            ((node["extensions"] as? [String: Any])?["KHR_lights_punctual"] as? [String: Any])?["light"] as? Int
        }

        func applyLight(_ index: Int, to object: inout SceneObject) {
            let lights = ((file.json["extensions"] as? [String: Any])?["KHR_lights_punctual"] as? [String: Any])?["lights"] as? [[String: Any]] ?? []
            guard index < lights.count else { return }
            let light = lights[index]
            object.kind = .light(LightType(rawValue: light["type"] as? String ?? "") ?? .point)
            if let color = GLTFReader.numbers(light["color"]), color.count >= 3 {
                object[.lightColor] = .color(.rgba(RGBA(SceneExport.srgb(color[0]), SceneExport.srgb(color[1]), SceneExport.srgb(color[2]))))
            }
            if let intensity = light["intensity"] as? Double { object[.lightIntensity] = .float(intensity) }
            if let range = light["range"] as? Double { object[.lightRange] = .float(range) }
            if let outer = (light["spot"] as? [String: Any])?["outerConeAngle"] as? Double { object[.spotAngle] = .float(outer * 2 * 180 / .pi) }
        }

        struct Piece {
            var name: String
            var mesh: EditableMesh
            var material: Material?
        }

        /// A glTF material's numbers as written (linear), before anything rounds them.
        struct Material {
            var base: [Double]
            var emissive: [Double]
            var roughness: Double
            var metallic: Double
        }

        func material(_ index: Int) -> Material? {
            let materials = file.array("materials")
            guard materials.indices.contains(index) else { return nil }
            let material = materials[index]
            let pbr = material["pbrMetallicRoughness"] as? [String: Any] ?? [:]
            let strength = ((material["extensions"] as? [String: Any])?["KHR_materials_emissive_strength"] as? [String: Any])?["emissiveStrength"]
                as? Double ?? 1
            return Material(base: GLTFReader.numbers(pbr["baseColorFactor"]) ?? [1, 1, 1, 1],
                            emissive: (GLTFReader.numbers(material["emissiveFactor"]) ?? [0, 0, 0]).map { $0 * strength },
                            roughness: pbr["roughnessFactor"] as? Double ?? 1, metallic: pbr["metallicFactor"] as? Double ?? 1)
        }

        /// Each triangle primitive of a mesh, its triangles rebuilt into whole faces.
        func meshPieces(_ index: Int) throws -> [Piece] {
            let meshes = file.array("meshes")
            guard index < meshes.count else { return [] }
            let name = meshes[index]["name"] as? String ?? "Mesh \(index)"
            var pieces: [Piece] = []
            for (number, primitive) in (meshes[index]["primitives"] as? [[String: Any]] ?? []).enumerated() {
                guard (primitive["mode"] as? Int ?? 4) == 4, let attributes = primitive["attributes"] as? [String: Any],
                      let positions = attributes["POSITION"] as? Int else { continue }
                let part = try GLTFMeshReader.primitivePart(file, attributes: attributes, positions: positions, indices: primitive["indices"] as? Int,
                                                            name: number == 0 ? name : "\(name) \(number + 1)",
                                                            material: primitive["material"] as? Int ?? -1, skinned: false)
                let mesh = MeshBuilder.mesh(from: part.mesh)
                guard !mesh.isEmpty else { continue }
                pieces.append(Piece(name: part.name, mesh: mesh, material: material(part.material)))
            }
            return pieces
        }

        func apply(_ material: Material?, to object: inout SceneObject) {
            guard let material, material.base.count >= 3 else { return }
            let base = material.base, srgb = SceneExport.srgb
            object[.color] = .color(.rgba(RGBA(srgb(base[0]), srgb(base[1]), srgb(base[2]), base.count > 3 ? base[3] : 1)))
            object[.roughness] = .float(material.roughness)
            object[.metallic] = .float(material.metallic)
            let glow = material.emissive
            guard glow.count >= 3 else { return }
            let strength = max(glow[0], glow[1], glow[2])
            if strength > 1e-6 {
                object[.emissive] = .color(.rgba(RGBA(srgb(glow[0] / strength), srgb(glow[1] / strength), srgb(glow[2] / strength))))
                object[.emissiveIntensity] = .float(strength)
            }
        }

        /// Node animation as tracks: linear keys stay linear, held keys hold, cubic ones keep their values (eased).
        func tracks(ids: inout IDFactory) throws -> ([Track], Double) {
            var result: [Track] = []
            var duration = 0.0
            for animation in file.array("animations") {
                let samplers = animation["samplers"] as? [[String: Any]] ?? []
                for channel in animation["channels"] as? [[String: Any]] ?? [] {
                    guard let target = channel["target"] as? [String: Any], let node = target["node"] as? Int, let id = objectOf[node],
                          let samplerIndex = channel["sampler"] as? Int, samplerIndex < samplers.count,
                          let property = Self.property(target["path"] as? String) else { continue }
                    let sampler = samplers[samplerIndex]
                    guard let input = sampler["input"] as? Int, let output = sampler["output"] as? Int else { continue }
                    let times = try GLTFReader.accessor(file, input).values
                    let (values, components, _) = try GLTFReader.accessor(file, output)
                    let interpolation = sampler["interpolation"] as? String ?? "LINEAR"
                    let cubic = interpolation == "CUBICSPLINE"
                    let easing: Easing = interpolation == "STEP" ? .step : cubic ? .easeInOut : .linear
                    var keys: [Keyframe] = []
                    for (index, time) in times.enumerated() {
                        // A cubic spline stores in-tangent, value, out-tangent per key.
                        let base = (cubic ? index * 3 + 1 : index) * components
                        guard base + components <= values.count else { break }
                        let element = Array(values[base ..< base + components])
                        guard let value = Self.value(element, property: property) else { continue }
                        keys.append(Keyframe(time: time, value: value, easing: easing))
                    }
                    guard !keys.isEmpty else { continue }
                    duration = max(duration, times.last ?? 0)
                    result.append(Track(id: ids.next(), target: id, property: property, keyframes: keys))
                }
            }
            return (result, duration)
        }

        static func property(_ path: String?) -> PropertyKey? {
            switch path {
            case "translation": .position
            case "rotation": .rotation
            case "scale": .scale
            default: nil
            }
        }

        static func value(_ element: [Double], property: PropertyKey) -> PropertyValue? {
            switch (property, element.count) {
            case (.rotation, 4): .quat(Quat(x: element[0], y: element[1], z: element[2], w: element[3]).normalized)
            case (.position, 3), (.scale, 3): .vec3(Vec3(element[0], element[1], element[2]))
            default: nil
            }
        }
    }
}

public extension ModelingOperations {
    /// Puts a glTF scene into the scene as editable objects (and its animation on the timeline), as one step.
    static func importScene(_ result: GLTFSceneReader.Result, in scene: Scene) -> EditCommand {
        var commands: [EditCommand] = [.insert(result.fragment, parent: nil, index: nil)]
        if result.duration > scene.timeline.duration {
            // A longer animation stretches the timeline to hold it.
            var timeline = scene.timeline
            timeline.tracks += result.tracks
            timeline.duration = result.duration
            commands.append(.setTimeline(timeline))
        } else if !result.tracks.isEmpty {
            commands.append(.setTracks(result.tracks.map(TrackEdit.init)))
        }
        return .batch("Import", commands)
    }
}
