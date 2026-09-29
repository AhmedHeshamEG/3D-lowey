import Foundation
import LoweyCore
import RealityKit
import UIKit

/// Ground grid for building (1 m cells, 5 m major lines, coloured axes). Drawn per pixel by the `loweyGrid` shader on one
/// big quad: crisp, anti-aliased lines at any distance that fade out towards the horizon. Without the shader it falls
/// back to thin line meshes.
@MainActor
public final class GridEntity: Entity {
    private var shaded: ModelEntity?
    private var pixelAngle: Float = 0

    public required init() {
        super.init()
        name = "Grid"
        components.set(LoweyHelperComponent())
        if let material = MaterialFactory.shared.gridMaterial(pixelAngle: 0.0012),
           let resource = try? MeshUpload.resource(from: Self.quad(half: 400), name: "grid") {
            let entity = ModelEntity(mesh: resource, materials: [material])
            addChild(entity)
            shaded = entity
            pixelAngle = 0.0012
        } else {
            build(extent: 20)
        }
    }

    /// The view's angle per pixel (2·tan(fov/2) / height in pixels): keeps lines about a pixel wide and soft.
    public func setPixelAngle(_ value: Float) {
        guard let shaded, value > 0, abs(value - pixelAngle) > pixelAngle * 0.02,
              var material = shaded.model?.materials.first as? CustomMaterial else { return }
        pixelAngle = value
        material.custom.value = SIMD4<Float>(value, 0, 0, 0)
        shaded.model?.materials = [material]
    }

    /// A flat square just above the ground (y = 1 mm).
    static func quad(half: Float) -> MeshData {
        var mesh = MeshData()
        let up = SIMD3<Float>(0, 1, 0)
        let a = mesh.addVertex(SIMD3<Float>(-half, 0.001, -half), normal: up, uv: SIMD2<Float>(0, 0))
        let b = mesh.addVertex(SIMD3<Float>(half, 0.001, -half), normal: up, uv: SIMD2<Float>(1, 0))
        let c = mesh.addVertex(SIMD3<Float>(half, 0.001, half), normal: up, uv: SIMD2<Float>(1, 1))
        let d = mesh.addVertex(SIMD3<Float>(-half, 0.001, half), normal: up, uv: SIMD2<Float>(0, 1))
        mesh.addTriangle(a, d, c)
        mesh.addTriangle(a, c, b)
        return mesh
    }

    private func build(extent: Int) {
        let thin: Float = 0.006
        let thick: Float = 0.014
        var minor = MeshData()
        var major = MeshData()
        let half = Float(extent)
        for index in -extent ... extent where index != 0 {
            let offset = Float(index)
            let isMajor = index % 5 == 0
            let width = isMajor ? thick : thin
            var line = PrimitiveMesh.box(size: SIMD3<Float>(half * 2, 0.001, width))
            line = line.transformed(LoweyCore.Transform(position: Vec3(0, 0.001, Double(offset))))
            var column = PrimitiveMesh.box(size: SIMD3<Float>(width, 0.001, half * 2))
            column = column.transformed(LoweyCore.Transform(position: Vec3(Double(offset), 0.001, 0)))
            if isMajor {
                major.append(line)
                major.append(column)
            } else {
                minor.append(line)
                minor.append(column)
            }
        }
        let factory = MaterialFactory.shared
        if let resource = try? MeshUpload.resource(from: minor) {
            addChild(ModelEntity(mesh: resource, materials: [factory.helper(color: .white, opacity: 0.12)]))
        }
        if let resource = try? MeshUpload.resource(from: major) {
            addChild(ModelEntity(mesh: resource, materials: [factory.helper(color: .white, opacity: 0.25)]))
        }
        let xAxis = PrimitiveMesh.box(size: SIMD3<Float>(half * 2, 0.001, 0.02)).transformed(LoweyCore.Transform(position: Vec3(0, 0.0015, 0)))
        let zAxis = PrimitiveMesh.box(size: SIMD3<Float>(0.02, 0.001, half * 2)).transformed(LoweyCore.Transform(position: Vec3(0, 0.0015, 0)))
        if let resource = try? MeshUpload.resource(from: xAxis) {
            addChild(ModelEntity(mesh: resource, materials: [factory.helper(color: UIColor(red: 0.95, green: 0.35, blue: 0.35, alpha: 1), opacity: 0.7)]))
        }
        if let resource = try? MeshUpload.resource(from: zAxis) {
            addChild(ModelEntity(mesh: resource, materials: [factory.helper(color: UIColor(red: 0.35, green: 0.55, blue: 1, alpha: 1), opacity: 0.7)]))
        }
    }
}

/// Wireframe box around the selection.
@MainActor
public final class SelectionBoxEntity: Entity {
    private let edges = Entity()
    /// What's on screen now: the box is rebuilt only when the bounds really change (not on every camera move or frame).
    private var shown: Bounds?

    public required init() {
        super.init()
        name = "Selection"
        components.set(LoweyHelperComponent())
        addChild(edges)
    }

    public func show(_ bounds: Bounds?) {
        if let bounds, let shown, isEnabled, bounds.min.isApproximately(shown.min, tolerance: 1e-5),
           bounds.max.isApproximately(shown.max, tolerance: 1e-5) {
            return
        }
        shown = bounds
        for child in Array(edges.children) {
            child.removeFromParent()
        }
        guard let bounds else {
            isEnabled = false
            return
        }
        isEnabled = true
        let lo = bounds.min.simd - SIMD3<Float>(repeating: 0.01)
        let hi = bounds.max.simd + SIMD3<Float>(repeating: 0.01)
        let size = hi - lo
        let thickness = max(0.008, min(size.x, min(size.y, size.z)) * 0.012)
        var mesh = MeshData()
        func edge(_ center: SIMD3<Float>, _ extent: SIMD3<Float>) {
            let box = PrimitiveMesh.box(size: extent)
            mesh.append(box.transformed(LoweyCore.Transform(position: Vec3(center - SIMD3<Float>(0, extent.y / 2, 0)))))
        }
        for y in [lo.y, hi.y] {
            for z in [lo.z, hi.z] {
                edge(SIMD3<Float>((lo.x + hi.x) / 2, y, z), SIMD3<Float>(size.x, thickness, thickness))
            }
        }
        for y in [lo.y, hi.y] {
            for x in [lo.x, hi.x] {
                edge(SIMD3<Float>(x, y, (lo.z + hi.z) / 2), SIMD3<Float>(thickness, thickness, size.z))
            }
        }
        for x in [lo.x, hi.x] {
            for z in [lo.z, hi.z] {
                edge(SIMD3<Float>(x, (lo.y + hi.y) / 2, z), SIMD3<Float>(thickness, size.y, thickness))
            }
        }
        if let resource = try? MeshUpload.resource(from: mesh) {
            edges.addChild(ModelEntity(mesh: resource, materials: [MaterialFactory.shared.helper(color: UIColor(red: 1, green: 0.78, blue: 0.2, alpha: 1))]))
        }
    }
}

/// Which gizmo handle was grabbed.
public struct GizmoHandle: Component, Sendable, Hashable {
    public enum Kind: String, Sendable { case move, rotate, scale, uniformScale }
    public var kind: Kind
    public var axis: CoreAxis
    public init(kind: Kind, axis: CoreAxis) {
        self.kind = kind
        self.axis = axis
    }
}

public enum GizmoMode: String, Sendable, CaseIterable {
    case move, rotate, scale
}

/// Move arrows / rotate rings / scale cubes, sized to stay the same on screen.
@MainActor
public final class GizmoEntity: Entity {
    public var mode: GizmoMode = .move {
        didSet { if mode != oldValue { rebuild() } }
    }

    public required init() {
        super.init()
        name = "Gizmo"
        components.set(LoweyHelperComponent())
        GizmoHandle.registerComponent()
        rebuild()
    }

    static func color(_ axis: CoreAxis) -> UIColor {
        switch axis {
        case .x: UIColor(red: 0.96, green: 0.33, blue: 0.36, alpha: 1)
        case .y: UIColor(red: 0.45, green: 0.86, blue: 0.4, alpha: 1)
        case .z: UIColor(red: 0.35, green: 0.58, blue: 1, alpha: 1)
        }
    }

    private func rebuild() {
        for child in Array(children) {
            child.removeFromParent()
        }
        let factory = MaterialFactory.shared
        for axis in CoreAxis.allCases {
            let material = factory.helper(color: Self.color(axis))
            let handle = Entity()
            handle.components.set(GizmoHandle(kind: mode == .rotate ? .rotate : (mode == .scale ? .scale : .move), axis: axis))
            switch mode {
            case .move:
                let shaft = ModelEntity(mesh: .generateCylinder(height: 0.8, radius: 0.025), materials: [material])
                shaft.position = SIMD3<Float>(0, 0.4, 0)
                let tip = ModelEntity(mesh: .generateCone(height: 0.25, radius: 0.08), materials: [material])
                tip.position = SIMD3<Float>(0, 0.92, 0)
                handle.addChild(shaft)
                handle.addChild(tip)
                handle.components.set(CollisionComponent(
                    shapes: [ShapeResource.generateBox(size: SIMD3<Float>(0.22, 1.05, 0.22)).offsetBy(translation: SIMD3<Float>(0, 0.55, 0))],
                    mode: .default, filter: CollisionFilter(group: PickGroup.gizmo, mask: .all)
                ))
            case .rotate:
                // A thin ring around the axis. Rings are picked by their drawn line on screen (`StageView.pickRotationRing`),
                // not by collision boxes: three boxes around three rings overlap and grabbed the wrong axis.
                let ring = PrimitiveMesh.torus(segments: 64, sides: 6, major: Self.ringRadius, minor: 0.022)
                    .transformed(LoweyCore.Transform(position: Vec3(0, -0.022, 0)))
                if let resource = try? MeshUpload.resource(from: ring) {
                    handle.addChild(ModelEntity(mesh: resource, materials: [material]))
                }
            case .scale:
                let shaft = ModelEntity(mesh: .generateCylinder(height: 0.8, radius: 0.02), materials: [material])
                shaft.position = SIMD3<Float>(0, 0.4, 0)
                let cube = ModelEntity(mesh: .generateBox(size: 0.16), materials: [material])
                cube.position = SIMD3<Float>(0, 0.88, 0)
                handle.addChild(shaft)
                handle.addChild(cube)
                handle.components.set(CollisionComponent(
                    shapes: [ShapeResource.generateBox(size: SIMD3<Float>(0.24, 1.0, 0.24)).offsetBy(translation: SIMD3<Float>(0, 0.5, 0))],
                    mode: .default, filter: CollisionFilter(group: PickGroup.gizmo, mask: .all)
                ))
            }
            // Point the handle's local +Y along its axis.
            switch axis {
            case .x: handle.orientation = simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(0, 0, 1))
            case .y: break
            case .z: handle.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
            }
            addChild(handle)
        }
        if mode == .scale {
            let center = ModelEntity(mesh: .generateBox(size: 0.2), materials: [factory.helper(color: .white)])
            center.components.set(GizmoHandle(kind: .uniformScale, axis: .y))
            center.components.set(CollisionComponent(shapes: [.generateBox(size: SIMD3<Float>(repeating: 0.3))],
                                                     mode: .default, filter: CollisionFilter(group: PickGroup.gizmo, mask: .all)))
            addChild(center)
        }
    }

    /// Radius of the rotate rings (gizmo units; the gizmo scales to stay the same size on screen).
    public static let ringRadius: Float = 0.95

    /// The handle an entity belongs to.
    public static func handle(for entity: Entity) -> GizmoHandle? {
        var current: Entity? = entity
        while let node = current {
            if let handle = node.components[GizmoHandle.self] { return handle }
            current = node.parent
        }
        return nil
    }
}

/// The translucent surface you draw on.
@MainActor
public final class GuideEntity: Entity {
    /// The surface on screen (rebuilt only when it changes, not on every camera move).
    private var shown: GuideSurface?
    private var hasShown = false

    public required init() {
        super.init()
        name = "Guide"
        components.set(LoweyHelperComponent())
    }

    public func show(_ surface: GuideSurface?) {
        if hasShown, surface == shown { return }
        hasShown = true
        shown = surface
        for child in Array(children) {
            child.removeFromParent()
        }
        guard let surface else {
            isEnabled = false
            return
        }
        isEnabled = true
        let fill = MaterialFactory.shared.helper(color: UIColor(red: 0.45, green: 0.75, blue: 1, alpha: 1), opacity: 0.16)
        let line = MaterialFactory.shared.helper(color: UIColor(red: 0.55, green: 0.8, blue: 1, alpha: 1), opacity: 0.45)
        switch surface {
        case let .plane(origin, normal):
            let size: Float = 8
            var slab = PrimitiveMesh.box(size: SIMD3<Float>(size, 0.002, size))
            // Grid lines on the plane.
            for index in -4 ... 4 {
                let offset = Double(index)
                slab.append(PrimitiveMesh.box(size: SIMD3<Float>(size, 0.004, 0.01)).transformed(LoweyCore.Transform(position: Vec3(0, 0, offset))))
                slab.append(PrimitiveMesh.box(size: SIMD3<Float>(0.01, 0.004, size)).transformed(LoweyCore.Transform(position: Vec3(offset, 0, 0))))
            }
            if let resource = try? MeshUpload.resource(from: slab) {
                let entity = ModelEntity(mesh: resource, materials: [fill])
                entity.transform = RealityKit.Transform(scale: .one, rotation: Quat.rotation(from: .unitY, to: normal).simd, translation: origin.simd)
                addChild(entity)
            }
        case let .box(center, size):
            let entity = ModelEntity(mesh: .generateBox(size: size.simd), materials: [fill])
            entity.position = center.simd
            addChild(entity)
            let outline = ModelEntity(mesh: .generateBox(size: size.simd * 1.002), materials: [line])
            outline.position = center.simd
            outline.scale = SIMD3<Float>(repeating: 1)
            addChild(outline)
        case let .cylinder(base, radius, height):
            let entity = ModelEntity(mesh: .generateCylinder(height: Float(height), radius: Float(radius)), materials: [fill])
            entity.position = base.simd + SIMD3<Float>(0, Float(height) / 2, 0)
            addChild(entity)
        case let .sphere(center, radius):
            let entity = ModelEntity(mesh: .generateSphere(radius: Float(radius)), materials: [fill])
            entity.position = center.simd
            addChild(entity)
        }
    }
}

extension UIFont {
    /// The same font in another system design (rounded, serif…), or itself when unavailable.
    func withDesign(_ design: UIFontDescriptor.SystemDesign) -> UIFont {
        guard let descriptor = fontDescriptor.withDesign(design) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
