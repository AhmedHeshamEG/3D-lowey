import CoreGraphics
import Foundation
import LoweyCore
import Metal
import simd

/// Library data the renderer reads (a value, so the stage and an export in the background can both hold it).
public struct AssetCatalog: Sendable {
    public var manifest: LibraryManifest
    public var fileURL: @Sendable (LibraryAsset) -> URL

    public init(manifest: LibraryManifest, fileURL: @escaping @Sendable (LibraryAsset) -> URL) {
        self.manifest = manifest
        self.fileURL = fileURL
    }

    public static let empty = AssetCatalog(manifest: LibraryManifest()) { _ in URL(fileURLWithPath: "/") }
}

/// A tinted see-through copy of an object as it is at another moment (the 3D onion skin): drawn on the stage only,
/// never picked, no shadow, no outline.
public struct Ghost {
    public var scene: Scene
    public var root: ObjectID
    public var tint: RGBA
    public var opacity: Double

    public init(scene: Scene, root: ObjectID, tint: RGBA, opacity: Double) {
        self.scene = scene
        self.root = root
        self.tint = tint
        self.opacity = opacity
    }
}

/// What one frame shows, before any GPU work.
public struct RenderInput {
    /// The document with its scene evaluated at `time` (animation applied).
    public var document: Document
    public var time: Double
    /// Skeletal poses (local joint transforms per Core skeleton joint) from `Animator`.
    public var poses: [ObjectID: [LoweyCore.Transform]]
    public var selection: Set<ObjectID>
    /// The camera you look through is hidden.
    public var hidden: ObjectID?
    /// Light bulbs, camera icons, particle emitters.
    public var showsHelpers: Bool
    /// Card pictures and video frames by key (`CardRecipe.frameKey`).
    public var mediaImage: (String) -> CGImage?
    public var catalog: AssetCatalog
    /// Point / spot lights that shine at once (the nearest to the camera win).
    public var lightBudget: Int
    /// Onion-skin ghosts (stage only).
    public var ghosts: [Ghost] = []
    /// Objects stretched along fast moves this frame (`Smear.smears`).
    public var smears: [ObjectID: Smear] = [:]
    /// The project's paint files by name (`paint/<hash>.png`, `.uv` under assets): painted objects' tiles and unwraps.
    public var paintFile: @Sendable (String) -> Data? = { _ in nil }

    public init(document: Document, time: Double = 0, poses: [ObjectID: [LoweyCore.Transform]] = [:], selection: Set<ObjectID> = [],
                hidden: ObjectID? = nil, showsHelpers: Bool = false, mediaImage: @escaping (String) -> CGImage? = { _ in nil },
                catalog: AssetCatalog = .empty, lightBudget: Int = 16) {
        self.document = document
        self.time = time
        self.poses = poses
        self.selection = selection
        self.hidden = hidden
        self.showsHelpers = showsHelpers
        self.mediaImage = mediaImage
        self.catalog = catalog
        self.lightBudget = lightBudget
    }
}

/// One draw: a mesh with its object's uniforms.
struct DrawItem {
    var mesh: GPUMesh
    var uniforms: ObjectUniforms
    var texture: MTLTexture?
    var blended: Bool
    var castsShadow: Bool
    var worldBounds: Bounds
    /// An onion-skin ghost: shaded pass only (no prepass, so no picking, lines or contact shading).
    var ghost = false
    /// A character part's outline (inverted hull) width in metres; 0 = none.
    var hull: Float = 0
    /// Ink whose brush stamps show instead: in the prepass (picking, selection) and shadows, not shaded.
    var brushDrawn = false
    /// The painted object this draw shows (its paint mesh and composite).
    var painted: ObjectID?
}

/// An editor helper (light bulb, camera box, particle emitter): drawn only on the stage, picked by its sphere.
public struct HelperItem: Sendable {
    public enum Kind: Sendable { case light, camera, emitter }
    public var kind: Kind
    public var object: ObjectID
    public var transform: LoweyCore.Transform
    public var color: RGBA
    public var radius: Double
}

/// A compiled frame: everything the passes need, in arrays the GPU buffers are filled from.
struct RenderScene {
    var items: [DrawItem] = []
    /// Object index (1-based, as in the ID buffer) → the scene object picked there.
    var objectIDs: [ObjectID] = []
    var lineWeights: [Float] = [1]
    var looks: [LookUniforms] = []
    var lookIDs: [String] = []
    var lights: [LightData] = []
    var joints: [simd_float4x4] = []
    var helpers: [HelperItem] = []
    var bounds: Bounds?
    /// Ink strokes' brush stamps, drawn at the end of the shading pass.
    var brushes: [BrushBatch] = []

    /// Registers a scene object for picking and returns its index.
    mutating func index(for id: ObjectID, lineWeight: Float) -> UInt32 {
        objectIDs.append(id)
        lineWeights.append(lineWeight)
        return UInt32(objectIDs.count)
    }

    /// The index of a Look in `looks` (added on first use; at most 16, the ID buffer's 4 bits).
    mutating func lookIndex(_ preset: LookPreset) -> UInt32 {
        if let existing = lookIDs.firstIndex(of: preset.id) { return UInt32(existing) }
        guard looks.count < 16 else { return 0 }
        lookIDs.append(preset.id)
        looks.append(LookResolver.uniforms(preset))
        return UInt32(looks.count - 1)
    }

    mutating func add(_ item: DrawItem) {
        items.append(item)
        bounds = bounds.map { $0.union(item.worldBounds) } ?? item.worldBounds
    }

    /// The scene object at an ID-buffer value.
    func objectID(forPacked packed: UInt32) -> ObjectID? {
        let index = Int(PackedID.object(packed))
        guard index > 0, index <= objectIDs.count else { return nil }
        return objectIDs[index - 1]
    }
}
