import Foundation
import HmmBoard
import HmmBoardUI
import HmmDesign
import LoweyCore

/// The project's Schizzo board (CONTEXT §10.7): a 2D sheet for planning that lives in the project's package
/// (`board/`), and the pictures pinned from it. A pin starts as a reference card floating over the stage
/// (`workspace.json`, how the project is seen); the same picture can be stood in the scene as a plane (an object).
extension EditorModel {
    /// Settings ▸ Board. Off: no board in Actions, no Sketch template, pinned cards put away (nothing is deleted).
    static var boardEnabled: Bool {
        UserDefaults.standard.object(forKey: AppSettings.boardEnabled) as? Bool ?? true
    }

    /// The board's model, made the first time the board is asked for (a project that never opens it carries none).
    func projectBoard() -> BoardModel {
        if let board { return board }
        let folder = projectURL.appendingPathComponent(ProjectLayout.boardFolder, isDirectory: true)
        let model = BoardModel(store: BoardStore(folder: folder, appName: AppIdentity.displayName))
        model.pin = { [weak self] pin in
            self?.pinReference(pin)
        }
        let brushes = app.brushes
        model.renderer?.brushImage = { key in brushes.image(key) }
        board = model
        return model
    }

    func openBoard() {
        guard Self.boardEnabled else { return }
        HmmHaptics.play(.selection)
        pause()
        openPanel = nil
        _ = projectBoard()
        boardShown = true
    }

    /// Back to the stage: the board is written down first.
    func closeBoard() {
        board?.close()
        boardShown = false
    }

    // MARK: Reference cards

    /// Keeps a picture from the board in the project and floats it over the stage.
    func pinReference(_ pin: BoardPin) {
        let file = "\(ProjectLayout.referencesFolder)/\(BrushKey.hex(BrushKey.fnv(pin.png))).png"
        let url = assetsFolder.appendingPathComponent(file)
        do {
            if !FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try pin.png.write(to: url, options: .atomic)
            }
        } catch {
            app.show("Couldn't pin that: \(error.localizedDescription)", kind: .error)
            return
        }
        let place = ReferenceCard.place(after: references)
        let aspect = pin.size.x > 0 ? pin.size.y / pin.size.x : 1
        // About as large as it was on the board, between a glance and a third of the screen.
        let width = min(max(pin.size.x * 0.6, 200), 380)
        references.append(ReferenceCard(id: UUID().uuidString, image: file, title: pin.title, x: place.x, y: place.y, width: width, aspect: aspect))
        workspaceChanged()
        app.show("Pinned to the project", kind: .success)
    }

    /// A card was moved or resized.
    func updateReference(_ card: ReferenceCard) {
        guard let index = references.firstIndex(where: { $0.id == card.id }) else { return }
        references[index] = card.clamped
        workspaceChanged()
    }

    /// Takes a card off the stage (its picture stays in the project: a plane in a scene may still show it).
    func removeReference(_ id: String) {
        references.removeAll { $0.id == id }
        workspaceChanged()
    }

    /// Where a card's picture is.
    func referenceURL(_ card: ReferenceCard) -> URL {
        assetsFolder.appendingPathComponent(card.image)
    }

    /// Stands a card's picture in the scene as a plane where you're looking: an object like any other (moved, turned,
    /// sized, hidden, undone), seen by every camera and in every export. The card stays.
    func standReferenceInScene(_ card: ReferenceCard) {
        let name = card.title.isEmpty ? String(localized: "Reference") : card.title
        addMediaCard(CardRecipe(image: card.image, aspect: 1 / max(card.aspect, 0.01)), named: name)
    }
}
