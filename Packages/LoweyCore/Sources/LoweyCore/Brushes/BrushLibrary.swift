import Foundation
import HmmDocuments

/// A named, ordered group of brushes (Procreate's brush sets).
public struct BrushSet: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var brushes: [String]
    /// The app's own sets: they can't be deleted, and their brushes can be edited and reset but not deleted.
    public var builtIn: Bool

    public init(id: String, name: String, brushes: [String] = [], builtIn: Bool = false) {
        self.id = id
        self.name = name
        self.brushes = brushes
        self.builtIn = builtIn
    }
}

/// Everyone's brushes on this device: the built-in sets (with any edits), made and imported brushes, and how they're
/// organised. Edits to a brush never reach strokes already drawn: a project keeps its own copy of each brush it used
/// (`BrushKey`). Every change returns what it changed, so the view can select it.
public struct BrushLibrary: Codable, Hashable, Sendable {
    public var sets: [BrushSet]
    /// Made and imported brushes, and built-ins that were edited.
    public var brushes: [String: Brush]
    /// Imported brushes as they arrived, so Reset brings them back.
    public var originals: [String: Brush]

    public init(sets: [BrushSet] = BuiltInBrushes.sets, brushes: [String: Brush] = [:], originals: [String: Brush] = [:]) {
        self.sets = sets
        self.brushes = brushes
        self.originals = originals
    }

    public static let standard = BrushLibrary()

    public func brush(_ id: String) -> Brush? {
        brushes[id] ?? BuiltInBrushes.brush(id)
    }

    public func set(_ id: String) -> BrushSet? {
        sets.first { $0.id == id }
    }

    /// The set holding a brush.
    public func set(containing brush: String) -> BrushSet? {
        sets.first { $0.brushes.contains(brush) }
    }

    public func isBuiltIn(_ id: String) -> Bool { BuiltInBrushes.brush(id) != nil }

    /// What Reset would bring back (nil: nothing to reset to, or it's already that).
    public func resetTarget(_ id: String) -> Brush? {
        guard let current = brush(id) else { return nil }
        let original = originals[id] ?? current.about.resetsTo.flatMap(BuiltInBrushes.brush).map { builtIn in
            var copy = builtIn
            copy.id = current.id
            copy.name = isBuiltIn(id) ? builtIn.name : current.name
            copy.about = current.about
            return copy
        }
        return original == current ? nil : original
    }

    /// Built-in sets and brushes a newer app added appear, wherever the person put the rest.
    public func merged() -> BrushLibrary {
        var library = self
        let placed = Set(library.sets.flatMap(\.brushes))
        for builtIn in BuiltInBrushes.sets {
            if let index = library.sets.firstIndex(where: { $0.id == builtIn.id }) {
                library.sets[index].brushes += builtIn.brushes.filter { !placed.contains($0) }
            } else {
                var fresh = builtIn
                fresh.brushes = builtIn.brushes.filter { !placed.contains($0) }
                library.sets.append(fresh)
            }
        }
        return library
    }

    // MARK: Brushes

    public mutating func update(_ brush: Brush) {
        brushes[brush.id] = brush.clamped
    }

    /// A copy right after the original, named "… copy".
    @discardableResult
    public mutating func duplicate(_ id: String, as newID: String) -> Brush? {
        guard var copy = brush(id) else { return nil }
        copy.id = newID
        copy.name = Self.copyName(copy.name, existing: Set(allBrushes.map(\.name)))
        if copy.about.origin == .builtIn { copy.about.origin = .made }
        brushes[newID] = copy
        originals[newID] = originals[id].map { original in
            var moved = original
            moved.id = newID
            moved.name = copy.name
            return moved
        }
        insert(newID, after: id)
        return copy
    }

    @discardableResult
    public mutating func reset(_ id: String) -> Brush? {
        guard let target = resetTarget(id) else { return nil }
        if isBuiltIn(id), target == BuiltInBrushes.brush(id) {
            brushes.removeValue(forKey: id)
        } else {
            brushes[id] = target
        }
        return target
    }

    public mutating func rename(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var brush = brush(id), !trimmed.isEmpty else { return }
        brush.name = trimmed
        brushes[id] = brush
    }

    /// Built-in brushes stay (they can be reset instead).
    public mutating func delete(_ id: String) {
        guard !isBuiltIn(id) else { return }
        brushes.removeValue(forKey: id)
        originals.removeValue(forKey: id)
        for index in sets.indices {
            sets[index].brushes.removeAll { $0 == id }
        }
    }

    /// Moves a brush into a set at a position (the end when nil), out of wherever it was.
    public mutating func move(_ id: String, to setID: String, at position: Int? = nil) {
        guard brush(id) != nil, let target = sets.firstIndex(where: { $0.id == setID }) else { return }
        var index = position ?? sets[target].brushes.count
        if let from = sets[target].brushes.firstIndex(of: id), from < index { index -= 1 }
        for set in sets.indices {
            sets[set].brushes.removeAll { $0 == id }
        }
        sets[target].brushes.insert(id, at: min(max(index, 0), sets[target].brushes.count))
    }

    /// Adds brushes (made or imported) as a new set, or into an existing one by id. Imported ones can be reset to how
    /// they arrived.
    public mutating func add(_ new: [Brush], toSet setID: String, named name: String) {
        for brush in new {
            brushes[brush.id] = brush.clamped
            if brush.about.origin == .procreate || brush.about.origin == .photoshop || brush.about.origin == .shared {
                originals[brush.id] = brush.clamped
            }
        }
        if let index = sets.firstIndex(where: { $0.id == setID }) {
            sets[index].brushes += new.map(\.id)
        } else {
            sets.insert(BrushSet(id: setID, name: name, brushes: new.map(\.id)), at: 0)
        }
    }

    public var allBrushes: [Brush] {
        sets.flatMap(\.brushes).compactMap(brush)
    }

    // MARK: Sets

    public mutating func addSet(id: String, name: String) {
        sets.insert(BrushSet(id: id, name: name), at: 0)
    }

    public mutating func renameSet(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = sets.firstIndex(where: { $0.id == id }), !trimmed.isEmpty else { return }
        sets[index].name = trimmed
    }

    /// Deletes a set of the person's own and the brushes only it held.
    public mutating func deleteSet(_ id: String) {
        guard let index = sets.firstIndex(where: { $0.id == id }), !sets[index].builtIn else { return }
        let removed = sets.remove(at: index)
        for brush in removed.brushes where set(containing: brush) == nil && !isBuiltIn(brush) {
            brushes.removeValue(forKey: brush)
            originals.removeValue(forKey: brush)
        }
    }

    public mutating func moveSet(_ id: String, to position: Int) {
        guard let from = sets.firstIndex(where: { $0.id == id }) else { return }
        let set = sets.remove(at: from)
        sets.insert(set, at: min(max(position, 0), sets.count))
    }

    private mutating func insert(_ id: String, after other: String) {
        if let set = sets.firstIndex(where: { $0.brushes.contains(other) }), let at = sets[set].brushes.firstIndex(of: other) {
            sets[set].brushes.insert(id, at: at + 1)
        } else if !sets.isEmpty {
            sets[0].brushes.append(id)
        }
    }

    static func copyName(_ name: String, existing: Set<String>) -> String {
        var candidate = "\(name) copy"
        var number = 2
        while existing.contains(candidate) {
            candidate = "\(name) copy \(number)"
            number += 1
        }
        return candidate
    }
}

/// The brush library on disk: `brushes.json` (a versioned envelope) beside `brushes/`, the tip and grain PNGs by
/// content hash. Image keys are `brushes/<hash>.png` here and in projects (under `assets/`), so a brush moves between
/// them by copying the same files.
public struct BrushLibraryStore: Sendable {
    public let root: URL
    public static let file = "brushes.json"
    public static let imagesFolder = "brushes"

    public init(root: URL) {
        self.root = root
    }

    public var fileURL: URL { root.appendingPathComponent(Self.file) }

    public func imageURL(_ key: String) -> URL { root.appendingPathComponent(key) }

    public func load() -> BrushLibrary {
        var library: BrushLibrary?
        _ = try? SafeFileWriter.read(fileURL) { data in
            library = try SchemaCoder.shared.decode(BrushLibrary.self, kind: .brushes, from: data)
        }
        return (library ?? .standard).merged()
    }

    public func save(_ library: BrushLibrary) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try SafeFileWriter.write(SchemaCoder.shared.encode(library, kind: .brushes), to: fileURL)
    }

    /// Stores a picture under its content key (once; the same picture is the same file).
    @discardableResult
    public func store(image data: Data) throws -> String {
        let key = BrushKey.imageKey(for: data)
        let url = imageURL(key)
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
        return key
    }
}

/// Content keys: the same brush or picture always gets the same key, so a project stores each brush once however many
/// strokes use it, and an edited brush is a new key (old strokes keep the old one).
public enum BrushKey {
    public static func imageKey(for data: Data) -> String {
        "\(BrushLibraryStore.imagesFolder)/\(hex(fnv(data))).png"
    }

    /// The key a project stores a brush under (its settings and pictures, not its place in the library).
    public static func key(for brush: Brush) -> String {
        var frozen = brush.clamped
        frozen.id = ""
        let data = (try? HmmJSON.encode(frozen)) ?? Data(brush.id.utf8)
        return "b-" + hex(fnv(data))
    }

    static func fnv(_ data: Data) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    static func hex(_ value: UInt64) -> String {
        let digits = String(value, radix: 16)
        return String(repeating: "0", count: max(16 - digits.count, 0)) + digits
    }
}

/// The brush a stroke names, from the project's frozen copies (Ink Pen when it names none, or one that's missing).
public enum BrushResolver {
    public static func brush(_ key: String?, in brushes: [String: Brush]) -> Brush {
        key.flatMap { brushes[$0] } ?? BuiltInBrushes.inkPen
    }
}
