import Foundation

/// A 3D printer's build volume, for the outline on the stage and the "fits on the bed" check. Sizes are what the
/// makers publish; the minimum wall is the thinnest wall that prints reliably on that kind of printer.
public struct PrintBed: Hashable, Sendable, Identifiable {
    public enum Process: String, Sendable {
        /// Filament (FDM): walls are made of 0.4 mm lines, two of them at least.
        case filament
        /// Resin (SLA, MSLA).
        case resin
    }

    public var id: String
    public var name: String
    /// Width (x), height (y), depth (z) in metres.
    public var size: Vec3
    public var process: Process

    public init(id: String, name: String, millimetres width: Double, _ depth: Double, _ height: Double, process: Process) {
        self.id = id
        self.name = name
        size = Vec3(width, height, depth) * 0.001
        self.process = process
    }

    /// The thinnest wall worth printing (metres).
    public var minimumWall: Double { process == .filament ? 0.0008 : 0.0005 }

    /// The build volume on the stage: centred on the origin, standing on the ground.
    public var volume: Bounds { Bounds(min: Vec3(-size.x / 2, 0, -size.z / 2), max: Vec3(size.x / 2, size.y, size.z / 2)) }

    /// Whether bounds fit inside the volume, as placed (they can still be turned to fit in a slicer).
    public func fits(_ bounds: Bounds) -> Bool {
        let inner = volume
        return bounds.min.x >= inner.min.x - 1e-9 && bounds.min.y >= -1e-9 && bounds.min.z >= inner.min.z - 1e-9
            && bounds.max.x <= inner.max.x + 1e-9 && bounds.max.y <= inner.max.y + 1e-9 && bounds.max.z <= inner.max.z + 1e-9
    }

    public static let presets: [PrintBed] = [
        PrintBed(id: "filament-220", name: "Filament printer, 220 mm", millimetres: 220, 220, 250, process: .filament),
        PrintBed(id: "filament-256", name: "Filament printer, 256 mm", millimetres: 256, 256, 256, process: .filament),
        PrintBed(id: "filament-180", name: "Small filament printer, 180 mm", millimetres: 180, 180, 180, process: .filament),
        PrintBed(id: "prusa-mk4", name: "Prusa MK4", millimetres: 250, 210, 220, process: .filament),
        PrintBed(id: "bambu-x1", name: "Bambu Lab X1, P1, A1", millimetres: 256, 256, 256, process: .filament),
        PrintBed(id: "bambu-a1-mini", name: "Bambu Lab A1 mini", millimetres: 180, 180, 180, process: .filament),
        PrintBed(id: "ender-3-v3", name: "Creality Ender-3 V3", millimetres: 220, 220, 250, process: .filament),
        PrintBed(id: "resin-218", name: "Resin printer, 218 × 123 mm", millimetres: 218, 123, 220, process: .resin),
        PrintBed(id: "form-4", name: "Formlabs Form 4", millimetres: 200, 125, 210, process: .resin)
    ]

    /// The bed a new *Model to print* project shows.
    public static let standard = presets[0]

    public static func preset(_ id: String?) -> PrintBed? {
        presets.first { $0.id == id }
    }
}

/// The section view: everything on the far side of a plane is cut away on the stage (never in exports), so the inside
/// of a part, a wall or a room shows. The cut faces are drawn in a flat colour.
public struct SectionPlane: Codable, Hashable, Sendable {
    /// Points with `normal · p > offset` are cut away.
    public var normal: Vec3
    public var offset: Double

    public init(normal: Vec3, offset: Double) {
        self.normal = normal.normalized
        self.offset = offset
    }

    /// A cut square to a world axis through a point.
    public init(axis: SymmetryAxis, through point: Vec3) {
        self.init(normal: axis.normal, offset: axis.normal.dot(point))
    }

    /// A cut along a face: the plane of the face, cutting away what's in front of it.
    public init(face normal: Vec3, through point: Vec3) {
        self.init(normal: normal, offset: normal.normalized.dot(point))
    }

    public func cuts(_ point: Vec3) -> Bool { normal.dot(point) > offset }

    /// The same plane facing the other way (keep the other side).
    public var flipped: SectionPlane { SectionPlane(normal: -normal, offset: -offset) }
}
