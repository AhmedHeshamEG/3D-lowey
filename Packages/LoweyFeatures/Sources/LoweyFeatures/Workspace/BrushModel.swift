import CoreGraphics
import Foundation
import LoweyCore
import LoweyEngine
import Observation
import os
import UIKit

/// The drawing tools that hold a brush.
enum BrushTool: String, CaseIterable, Sendable {
    case ink, flipbook
}

/// The brushes on this iPad (CONTEXT §10.3): the library with its sets, edits and imports, the brush each drawing
/// tool holds, and their pictures. Strokes never see library edits: a project keeps a frozen copy of each brush it
/// used (`EditorModel+Brushes`).
@Observable
@MainActor
final class BrushModel {
    private(set) var library = BrushLibrary.standard
    @ObservationIgnored let store: BrushLibraryStore
    /// The brush each tool draws with, by library id.
    private(set) var selection: [BrushTool: String] = [:]
    /// Bumped whenever a brush's look changes, so previews redraw.
    private(set) var revision = 0
    @ObservationIgnored private var images: [String: CGImage] = [:]
    @ObservationIgnored private var previews: [String: CGImage] = [:]
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private lazy var renderer: BrushPreviewRenderer? = (try? RenderDevice.sharedDevice()).flatMap { try? BrushPreviewRenderer(device: $0) }
    @ObservationIgnored private let logger = Logger(subsystem: AppIdentity.subsystem, category: "brushes")

    static let selectionKey = "brushSelection"

    init(root: URL) {
        store = BrushLibraryStore(root: root)
    }

    func load() {
        library = store.load()
        let saved = UserDefaults.standard.dictionary(forKey: Self.selectionKey) as? [String: String] ?? [:]
        for tool in BrushTool.allCases {
            selection[tool] = saved[tool.rawValue].flatMap { library.brush($0) == nil ? nil : $0 }
        }
    }

    // MARK: Choosing

    func brush(for tool: BrushTool) -> Brush {
        selection[tool].flatMap(library.brush) ?? BuiltInBrushes.inkPen
    }

    func select(_ id: String, for tool: BrushTool) {
        guard library.brush(id) != nil else { return }
        selection[tool] = id
        UserDefaults.standard.set(Dictionary(uniqueKeysWithValues: selection.map { ($0.key.rawValue, $0.value) }), forKey: Self.selectionKey)
    }

    // MARK: Changing

    /// A Brush Studio edit (saved a moment later, so dragging a slider writes once).
    func update(_ brush: Brush) {
        library.update(brush)
        changed()
    }

    @discardableResult
    func duplicate(_ id: String) -> String? {
        let newID = "brush-" + UUID().uuidString.prefix(8).lowercased()
        guard library.duplicate(id, as: newID) != nil else { return nil }
        changed()
        return newID
    }

    func reset(_ id: String) {
        guard library.reset(id) != nil else { return }
        changed()
    }

    func delete(_ id: String) {
        library.delete(id)
        for tool in BrushTool.allCases where selection[tool] == id {
            selection[tool] = nil
        }
        changed()
    }

    func rename(_ id: String, to name: String) {
        library.rename(id, to: name)
        changed()
    }

    @discardableResult
    func addSet(named name: String) -> String {
        let id = "set-" + UUID().uuidString.prefix(8).lowercased()
        library.addSet(id: id, name: name)
        changed()
        return id
    }

    func renameSet(_ id: String, to name: String) {
        library.renameSet(id, to: name)
        changed()
    }

    func deleteSet(_ id: String) {
        library.deleteSet(id)
        for tool in BrushTool.allCases where selection[tool].flatMap(library.brush) == nil {
            selection[tool] = nil
        }
        changed()
    }

    func move(_ id: String, to set: String, at position: Int? = nil) {
        library.move(id, to: set, at: position)
        changed()
    }

    private func changed() {
        revision += 1
        previews.removeAll()
        saveTask?.cancel()
        let library = library
        let store = store
        saveTask = Task { [logger] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            do {
                try store.save(library)
            } catch {
                logger.error("Couldn't save the brush library: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: Files

    /// Imports a `.brushset`, `.brush`, `.abr` or `.maquettebrushes` as a new set; returns what to tell the person.
    func importFile(_ url: URL) async -> (message: String, failed: Bool) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let name = url.lastPathComponent
        let store = store
        let result: Result<BrushImportResult, Error> = await Task.detached(priority: .userInitiated) {
            Result {
                let data = try Data(contentsOf: url)
                let imported = try BrushFileImport.read(data, fileName: name) { "brush-" + UUID().uuidString.prefix(8).lowercased() }
                for (_, png) in imported.images {
                    try store.store(image: png)
                }
                return imported
            }
        }.value
        switch result {
        case let .success(imported):
            let setID = "set-" + UUID().uuidString.prefix(8).lowercased()
            library.add(imported.brushes, toSet: setID, named: imported.setName)
            changed()
            for note in imported.notes {
                logger.notice("Import of \(name, privacy: .public): \(note, privacy: .public)")
            }
            let count = imported.brushes.count
            return (count == 1 ? "Added “\(imported.setName)”" : "Added \(count) brushes in “\(imported.setName)”", false)
        case let .failure(error):
            logger.error("Brush import failed: \(String(describing: error), privacy: .public)")
            return ((error as? BrushImportError)?.description ?? "Couldn't read “\(name)”", true)
        }
    }

    /// A set written as a `.maquettebrushes` file to share (in a temporary folder).
    func shareFile(for setID: String) -> URL? {
        guard let set = library.set(setID) else { return nil }
        let brushes = set.brushes.compactMap(library.brush)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Brush sets", isDirectory: true)
        let safe = set.name.replacingOccurrences(of: "/", with: "-")
        let url = folder.appendingPathComponent(safe).appendingPathExtension(BrushSetFile.fileExtension)
        do {
            let data = try BrushSetFile.write(name: set.name, brushes: brushes) { [store] in try? Data(contentsOf: store.imageURL($0)) }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            logger.error("Couldn't write the brush set: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: Pictures

    /// A picture chosen in Brush Studio, stored as a grey tip or grain (its key, nil when it isn't a picture).
    func storePicture(_ data: Data) -> String? {
        guard let picture = UIImage(data: data)?.cgImage, let grey = GreyImage(cgImage: picture) else { return nil }
        return try? store.store(image: GreyPNG.encode(grey.fitting(ABRBrushImport.maximumTipSize)))
    }

    /// An imported tip or grain from the library's pictures.
    func image(_ key: String) -> CGImage? {
        if let cached = images[key] { return cached }
        guard let picture = UIImage(contentsOfFile: store.imageURL(key).path)?.cgImage else { return nil }
        images[key] = picture
        return picture
    }

    /// A brush drawing its sample stroke, `width` × `height` points at the screen's scale.
    func preview(_ brush: Brush, width: Double, height: Double, color: RGBA, scale: Double) -> CGImage? {
        let key = "\(BrushKey.key(for: brush))-\(Int(width))x\(Int(height))-\(color.hex)-\(scale)"
        if let cached = previews[key] { return cached }
        let pixels = (width * scale, height * scale)
        let path = BrushPreviewPath.sample(width: pixels.0, height: pixels.1, brush: brush, size: min(pixels.1 * 0.16, 14 * scale))
        let stroke = BrushPreviewStroke(path: path, brush: brush, color: color)
        let picture = renderer?.image([stroke], width: Int(pixels.0), height: Int(pixels.1)) { [weak self] key in self?.image(key) }
        if previews.count > 200 { previews.removeAll() }
        previews[key] = picture
        return picture
    }

    /// Strokes drawn on Brush Studio's pad.
    func padImage(_ strokes: [BrushPreviewStroke], width: Int, height: Int) -> CGImage? {
        renderer?.image(strokes, width: width, height: height) { [weak self] in self?.image($0) }
    }
}
