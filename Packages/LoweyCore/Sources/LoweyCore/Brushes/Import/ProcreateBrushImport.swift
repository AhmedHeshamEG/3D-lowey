import Foundation

/// What an import brought: brushes ready for the library, the pictures they use (by key), and what was left out.
public struct BrushImportResult: Sendable {
    public var setName: String
    public var brushes: [Brush]
    /// PNG data by image key (`brushes/<hash>.png`).
    public var images: [String: Data]
    /// One line per brush or setting that couldn't come across.
    public var notes: [String]

    public init(setName: String, brushes: [Brush] = [], images: [String: Data] = [:], notes: [String] = []) {
        self.setName = setName
        self.brushes = brushes
        self.images = images
        self.notes = notes
    }
}

public enum BrushImportError: Error, Equatable, CustomStringConvertible {
    case unreadable(String)
    case empty(String)

    public var description: String {
        switch self {
        case let .unreadable(name): "“\(name)” isn't a brush file Maquette can read"
        case let .empty(name): "“\(name)” holds no brushes Maquette can use"
        }
    }
}

/// Procreate's `.brush` (a zip: `Brush.archive`, `Shape.png`, `Grain.png`) and `.brushset` (a zip of brush folders and
/// `brushset.plist`). Settings map as closely as the engine allows (DECISIONS D-141 has the table); tips and grains
/// that point at Procreate's own bundled pictures become the nearest built-in one.
public enum ProcreateBrushImport {
    public static func read(_ data: Data, fileName: String, newID: () -> String) throws -> BrushImportResult {
        let entries: [(name: String, data: Data)]
        do {
            entries = try ZipReader.entries(data)
        } catch {
            throw BrushImportError.unreadable(fileName)
        }
        let files = Dictionary(entries.map { ($0.name, $0.data) }, uniquingKeysWith: { first, _ in first })
        let baseName = (fileName as NSString).deletingPathExtension
        var result = BrushImportResult(setName: baseName)
        if let manifest = files["brushset.plist"] {
            let plist = try? plist(manifest)
            result.setName = plist?["name"]?.string ?? baseName
            let folders = plist?["brushes"]?.array?.compactMap(\.string) ?? folderNames(in: files.keys)
            for folder in folders {
                read(folder: folder + "/", files: files, into: &result, newID: newID)
            }
        } else {
            read(folder: "", files: files, into: &result, newID: newID)
        }
        guard !result.brushes.isEmpty else { throw BrushImportError.empty(fileName) }
        return result
    }

    /// Folders holding a `Brush.archive` (a brushset whose plist doesn't list them).
    static func folderNames(in names: some Sequence<String>) -> [String] {
        names.filter { $0.hasSuffix("/Brush.archive") && !$0.contains("/Reset/") && $0.split(separator: "/").count == 2 }
            .map { String($0.split(separator: "/")[0]) }
            .sorted()
    }

    static func plist(_ data: Data) throws -> PlistValue {
        if BinaryPlist.isBinary(data) { return try BinaryPlist.read(data) }
        let object = try PropertyListSerialization.propertyList(from: data, format: nil)
        return PlistValue(foundation: object)
    }

    static func read(folder: String, files: [String: Data], into result: inout BrushImportResult, newID: () -> String) {
        guard let archiveData = files[folder + "Brush.archive"], let archive = try? KeyedArchive(plist(archiveData)) else {
            result.notes.append("Skipped “\(folder.isEmpty ? "the brush" : String(folder.dropLast()))”: its settings can't be read")
            return
        }
        var images: [String: Data] = [:]
        func image(_ name: String) -> BrushImageSource? {
            guard let png = files[folder + name], png.count > 8 else { return nil }
            let key = BrushKey.imageKey(for: png)
            images[key] = png
            return .image(key)
        }
        var brush = brushSettings(archive, id: newID())
        brush.shape.source = image("Shape.png") ?? bundled(archive.string("bundledShapePath"), grain: false) ?? .builtIn(.hardRound)
        brush.grain.source = image("Grain.png") ?? bundled(archive.string("bundledGrainPath"), grain: true)
        if brush.name.isEmpty { brush.name = folder.isEmpty ? result.setName : String(folder.dropLast()) }
        result.brushes.append(brush.clamped)
        result.images.merge(images) { first, _ in first }
    }

    /// Procreate's settings mapped onto the engine's (D-141).
    static func brushSettings(_ archive: KeyedArchive, id: String) -> Brush {
        func number(_ key: String, _ fallback: Double = 0) -> Double { archive.double(key) ?? fallback }
        let spacing = number("plotSpacing", 0.05)
        var brush = Brush(id: id, name: (archive.string("name") ?? "").trimmingCharacters(in: .whitespaces),
                          about: BrushAbout(origin: .procreate, author: archive.string("authorName").flatMap { $0.isEmpty ? nil : $0 }))
        brush.shape = BrushShape(source: .builtIn(.hardRound), roundness: number("shapeRoundness", 1), angle: number("shapeRotation") * 180,
                                 followsStroke: archive.bool("oriented") ?? true, rotationJitter: number("shapeScatter"),
                                 flipXJitter: archive.bool("shapeFlipXJitter") ?? false, flipYJitter: archive.bool("shapeFlipYJitter") ?? false,
                                 count: 1 + Int((number("shapeCount") * 15).rounded()), inverted: archive.bool("shapeInverted") ?? false)
        brush.grain = BrushGrain(source: nil, scale: 0.05 + number("textureScale", 0.5) * 2, depth: number("grainDepth", 1),
                                 movement: number("textureMovement", 1) >= 0.5 ? .rolling : .texturized,
                                 inverted: archive.bool("textureInverted") ?? false)
        brush.stroke = BrushStrokeSettings(
            spacing: 0.02 + spacing * spacing * 1.98, streamline: max(number("plotSmoothing"), number("plotMovingAverageStabilization")),
            jitter: number("plotJitter") * 2, falloff: number("dynamicsFalloff"),
            taperStart: number("pencilTaperStartLength") * 0.4, taperEnd: number("pencilTaperEndLength") * 0.4,
            taperSize: number("pencilTaperSize"), taperOpacity: number("pencilTaperOpacity")
        )
        brush.dynamics = BrushDynamics(
            pressureSize: number("dynamicsPressureSize"), pressureOpacity: number("dynamicsPressureOpacity"),
            pressureCurve: curve(archive, "dynamicsPressureSizeCurve"), tiltSize: number("dynamicsTiltSize"),
            tiltOpacity: number("dynamicsTiltOpacity"), speedSize: number("dynamicsSpeedSize"), speedOpacity: number("dynamicsSpeedOpacity"),
            sizeJitter: number("dynamicsJitterSize"), opacityJitter: number("dynamicsJitterOpacity"), minimumSize: 0, minimumOpacity: 0
        )
        brush.rendering = BrushRendering(flow: number("dynamicsGlazedFlow", 1), wetEdges: number("wetEdgesAmount"))
        return brush
    }

    /// A `ValkyrieMagnitudinalCurve`: an array of point strings "{x, y}".
    static func curve(_ archive: KeyedArchive, _ key: String) -> BrushCurve {
        guard let object = archive.value(key), let points = archive.resolve(object["points"]) else { return .linear }
        let parsed = archive.items(of: points).compactMap { item -> Vec2? in
            guard let text = item.string else { return nil }
            let numbers = text.trimmingCharacters(in: CharacterSet(charactersIn: "{} ")).split(separator: ",")
                .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            return numbers.count == 2 ? Vec2(numbers[0], numbers[1]) : nil
        }
        return parsed.count >= 2 ? BrushCurve(parsed).clamped : .linear
    }

    /// Procreate's own pictures don't travel with the file: the nearest built-in stands in, by name.
    static func bundled(_ name: String?, grain: Bool) -> BrushImageSource? {
        guard let name = name?.lowercased(), !name.isEmpty, name != "$null" else { return nil }
        let table: [(String, BuiltInBrushImage)] = grain
            ? [("canvas", .canvas), ("charcoal", .charcoal), ("paper", .paper), ("noise", .noise)]
            : [("soft", .softRound), ("air", .softRound), ("pencil", .pencilTip), ("chalk", .chalkTip), ("charcoal", .chalkTip),
               ("grit", .chalkTip), ("bristle", .bristleTip), ("acrylic", .bristleTip), ("oil", .bristleTip), ("splat", .splatterTip),
               ("spray", .splatterTip), ("flat", .flatTip)]
        let match = table.first { name.contains($0.0) }?.1
        return .builtIn(match ?? (grain ? .paper : .hardRound))
    }
}

extension PlistValue {
    /// From Foundation's reader (XML plists; keyed archives in XML aren't used by Procreate).
    init(foundation object: Any) {
        switch object {
        case let value as String: self = .string(value)
        case let value as Bool: self = .bool(value)
        case let value as Int: self = .int(Int64(value))
        case let value as Double: self = .real(value)
        case let value as Data: self = .data(value)
        case let value as Date: self = .date(value.timeIntervalSinceReferenceDate)
        case let value as [Any]: self = .array(value.map(PlistValue.init(foundation:)))
        case let value as [String: Any]: self = .dict(value.mapValues(PlistValue.init(foundation:)))
        default: self = .null
        }
    }
}
