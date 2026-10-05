import Foundation
import HmmDocuments

/// A brush set shared as one file: `.maquettebrushes`, a zip of `set.json` (a versioned envelope: the set's name and
/// its brushes) and the PNGs they use under `brushes/`. AirDrop it, keep it in Files, open it on another iPad.
public enum BrushSetFile {
    public static let fileExtension = "maquettebrushes"

    struct Payload: Codable, Sendable {
        var name: String
        var brushes: [Brush]
    }

    /// `images` returns a picture's PNG by key (missing ones are left out; the brush falls back to a round tip).
    public static func write(name: String, brushes: [Brush], images: (String) -> Data?) throws -> Data {
        var files: [(name: String, data: Data)] = []
        try files.append(("set.json", SchemaCoder.shared.encode(Payload(name: name, brushes: brushes), kind: .brushes)))
        for key in Set(brushes.flatMap(\.imageKeys)).sorted() {
            if let png = images(key) { files.append((key, png)) }
        }
        return ZipWriter.storedArchive(files)
    }

    public static func read(_ data: Data, fileName: String, newID: () -> String) throws -> BrushImportResult {
        guard let entries = try? ZipReader.entries(data), let json = entries.first(where: { $0.name == "set.json" })?.data,
              let payload = try? SchemaCoder.shared.decode(Payload.self, kind: .brushes, from: json) else {
            throw BrushImportError.unreadable(fileName)
        }
        var result = BrushImportResult(setName: payload.name)
        // Keys are content hashes: a picture whose name doesn't match its contents is filed under what it is.
        var keys: [String: String] = [:]
        for (name, png) in entries where name.hasPrefix(BrushLibraryStore.imagesFolder + "/") {
            keys[name] = BrushKey.imageKey(for: png)
            result.images[BrushKey.imageKey(for: png)] = png
        }
        let images = result.images
        var notes: [String] = []
        result.brushes = payload.brushes.map { shared in
            var brush = shared.clamped
            brush.id = newID()
            if case let .image(key) = brush.shape.source, let actual = keys[key] { brush.shape.source = .image(actual) }
            if case let .image(key)? = brush.grain.source, let actual = keys[key] { brush.grain.source = .image(actual) }
            if brush.about.origin != .procreate, brush.about.origin != .photoshop { brush.about.origin = .shared }
            brush.about.resetsTo = nil
            if brush.imageKeys.contains(where: { images[$0] == nil }) {
                notes.append("“\(brush.name)” lost a picture and draws without it")
            }
            if let key = brush.shape.source.imageKey, images[key] == nil { brush.shape.source = .builtIn(.hardRound) }
            if let key = brush.grain.source?.imageKey, images[key] == nil { brush.grain.source = nil }
            return brush
        }
        result.notes = notes
        guard !result.brushes.isEmpty else { throw BrushImportError.empty(fileName) }
        return result
    }
}

/// One entry point for every brush file the app opens.
public enum BrushFileImport {
    public static let fileExtensions = ["brushset", "brush", "abr", BrushSetFile.fileExtension]

    public static func read(_ data: Data, fileName: String, newID: () -> String) throws -> BrushImportResult {
        switch (fileName as NSString).pathExtension.lowercased() {
        case "abr": try ABRBrushImport.read(data, fileName: fileName, newID: newID)
        case BrushSetFile.fileExtension: try BrushSetFile.read(data, fileName: fileName, newID: newID)
        case "brush", "brushset": try ProcreateBrushImport.read(data, fileName: fileName, newID: newID)
        default: throw BrushImportError.unreadable(fileName)
        }
    }
}
