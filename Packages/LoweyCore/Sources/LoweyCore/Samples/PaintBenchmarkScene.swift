import Foundation

/// The painting benchmark (M6's performance gate): a placed model of about fifty thousand triangles, filling most of
/// the frame, painted by a scripted Pencil for twenty seconds. The model is generated (seeded into the model library,
/// never read from a file), so every run paints the same thing.
public enum PaintBenchmarkScene {
    public static let assetID: AssetID = "benchmark.paint-sphere"
    public static let objectID: ObjectID = "painted"
    public static let projectName = "Painting on a 50k-triangle model"
    public static let duration = 20.0
    /// Seconds per scripted stroke (each ends, the next starts where the Pencil lifts).
    public static let strokeLength = 1.5
    /// The Pencil's sample rate.
    public static let sampleRate = 240.0

    public static let asset = LibraryAsset(id: assetID, name: "Paint benchmark sphere", tags: ["benchmark"], format: .glb,
                                           file: "benchmark-sphere.glb")

    /// A sphere of `rings` × `segments` quads (160 × 160: 50 880 triangles), radius 1, standing on the ground.
    public static func sphere(rings: Int = 160, segments: Int = 160) -> MeshData {
        var mesh = MeshData()
        for ring in 0 ... rings {
            let polar = Double(ring) / Double(rings) * .pi
            for segment in 0 ... segments {
                let azimuth = Double(segment) / Double(segments) * 2 * .pi
                let normal = SIMD3<Float>(Float(sin(polar) * cos(azimuth)), Float(cos(polar)), Float(sin(polar) * sin(azimuth)))
                mesh.addVertex(normal + SIMD3<Float>(0, 1, 0), normal: normal,
                               uv: SIMD2<Float>(Float(segment) / Float(segments), Float(ring) / Float(rings)))
            }
        }
        let row = UInt32(segments + 1)
        for ring in 0 ..< UInt32(rings) {
            for segment in 0 ..< UInt32(segments) {
                let a = ring * row + segment, b = a + 1, c = a + row, d = c + 1
                // The poles' degenerate halves are left out.
                if ring > 0 { mesh.addTriangle(a, b, c) }
                if ring < UInt32(rings) - 1 { mesh.addTriangle(b, d, c) }
            }
        }
        return mesh
    }

    public static func model() -> ImportedModel {
        ImportedModel(parts: [ImportedPart(name: "Sphere", mesh: sphere(), material: 0)],
                      materials: [ImportedMaterial(name: "Clay", baseColor: RGBA(0.86, 0.84, 0.8))])
    }

    /// The scene: the model in the middle of a clay-lit room, the camera close enough for it to fill most of the frame.
    public static func document() -> Document {
        let object = SceneObject(id: objectID, name: "Sphere", kind: .asset(assetID))
        var camera = SceneObject(id: "camera", name: "Camera", kind: .camera, transform: Transform(position: Vec3(0, 1, 3.4)))
        camera[.fieldOfView] = .float(45)
        var scene = Scene(id: "paint-benchmark", name: projectName, objects: [object.id: object, camera.id: camera], roots: [object.id, camera.id])
        scene.activeCamera = camera.id
        scene.look = Look(presetID: LookPreset.clay.id)
        let info = ProjectInfo(id: "paint-benchmark", name: projectName, sceneOrder: [scene.id], sceneNames: [scene.id: scene.name])
        return Document(project: info, scene: scene)
    }

    /// The scripted Pencil at `time`: which stroke it's in, and that stroke's samples so far, as fractions of the
    /// frame (x across, y down). Strokes sweep across the sphere's face in loops, a new one every `strokeLength`.
    public static func pencil(at time: Double) -> (stroke: Int, samples: [(point: Vec2, pressure: Double)]) {
        let stroke = Int(time / strokeLength)
        let into = time - Double(stroke) * strokeLength
        let count = max(Int(into * sampleRate), 1)
        let phase = Double(stroke) * 0.7
        let samples = (0 ..< count).map { index -> (point: Vec2, pressure: Double) in
            let t = Double(index) / sampleRate / strokeLength
            let x = 0.5 + 0.22 * sin(2 * .pi * t + phase) + 0.08 * sin(9 * .pi * t)
            let y = 0.5 + 0.2 * sin(4 * .pi * t + phase * 1.3)
            return (Vec2(x, y), 0.55 + 0.45 * sin(.pi * t))
        }
        return (stroke, samples)
    }
}
