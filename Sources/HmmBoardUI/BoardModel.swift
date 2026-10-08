#if canImport(Metal) && canImport(CoreText) && canImport(Observation)
    import CoreGraphics
    import Foundation
    import HmmBoard
    import HmmBrush
    import HmmCommands
    import HmmDesign
    import HmmDocuments
    import ImageIO
    import Observation

    /// A picture of a part of the board for the app to keep as a reference.
    public struct BoardPin: Sendable {
        public var png: Data
        /// The frame's name, or the first words of what was pinned (may be empty).
        public var title: String
        /// How large it is on the board, in board units: its shape.
        public var size: Vec2
    }

    /// A board open on screen: the session, its history on disk, its pictures, and what the app plugged in (the
    /// brush in the hand, what a pin does). Every change goes through `mutate`, so it is drawn, recorded in the
    /// journal within a moment and saved at the next quiet one.
    @MainActor
    @Observable
    public final class BoardModel {
        public private(set) var session = BoardSession()
        /// The board has been read from disk (until then the canvas is empty and takes no strokes).
        public private(set) var isLoaded = false
        /// Where the Pencil hovers and where the eraser is, in board units.
        public var hover: Vec2?
        public var eraserAt: Vec2?
        /// Fingers are moving the view.
        public var interacting = false
        /// The frame being renamed.
        public var renaming: String?
        /// Something went wrong, in a sentence for the person.
        public var message: String?
        public var pencilOrHand: HmmPencilOrHand
        /// The app's accent: the selection's marks.
        public var accent = BoardColor(red: 1, green: 0.72, blue: 0.28)

        /// Keeps a picture of the board as a reference in the app (nil: nothing to pin to).
        @ObservationIgnored public var pin: ((BoardPin) -> Void)?
        @ObservationIgnored public let store: BoardStore?
        @ObservationIgnored public let renderer: BoardRenderer?
        @ObservationIgnored var predicted: [BrushInput<Vec2>] = []
        @ObservationIgnored private var changes = BoardChanges()
        @ObservationIgnored private var journal: HistoryJournal<BoardCommand>?
        @ObservationIgnored private var unsaved = 0
        @ObservationIgnored private var idleSave: Task<Void, Never>?
        @ObservationIgnored private var fitsWhenSized = false
        @ObservationIgnored private var viewSize = Vec2.zero
        @ObservationIgnored private let defaults: UserDefaults

        /// What was copied on any board in this app.
        public static var clipboard: BoardClipboard?

        public init(store: BoardStore?, defaults: UserDefaults = .standard) {
            self.store = store
            self.defaults = defaults
            pencilOrHand = HmmPencilOrHand(defaults: defaults)
            renderer = try? BoardRenderer()
            if let store {
                renderer?.assetURL = { name in store.assetURL(name) }
            }
        }

        // MARK: Opening and saving

        private struct Opened: Sendable {
            let journal: HistoryJournal<BoardCommand>
            let board: Board
            let history: CommandStack<BoardCommand>
            let view: BoardViewport?
        }

        /// Reads the board and its history (off the main thread). A board with no file yet starts empty.
        public func load() async {
            guard !isLoaded else { return }
            defer { isLoaded = true }
            guard let store else { return }
            let opened = await Task.detached(priority: .userInitiated) { () -> Opened? in
                guard let result = try? store.open() else { return nil }
                return Opened(journal: result.journal, board: result.opened.document, history: result.opened.history, view: store.loadView())
            }.value
            guard let opened else {
                message = "This board couldn't be opened."
                return
            }
            var fresh = BoardSession(board: opened.board, history: opened.history)
            if let view = opened.view {
                fresh.viewport = view
            } else {
                fitsWhenSized = true
            }
            fresh.brush = session.brush
            session = fresh
            journal = opened.journal
            changes.rebuild = true
            renderer?.invalidate()
            if fitsWhenSized, viewSize.x > 0, viewSize.y > 0 {
                fitsWhenSized = false
                session.zoomToFit(size: viewSize)
            }
        }

        /// Changes the session. What it did to the board reaches the canvas and the journal.
        @discardableResult
        public func mutate<T>(_ body: (inout BoardSession) -> T) -> T {
            var next = session
            let result = body(&next)
            changes.merge(next.takeChanges())
            let ops = next.takePendingOps()
            session = next
            if !ops.isEmpty { record(ops) }
            return result
        }

        private func record(_ ops: [HistoryOp<BoardCommand>]) {
            guard let journal else { return }
            journal.record(ops)
            unsaved += ops.count
            if unsaved >= 200 { save() }
            idleSave?.cancel()
            idleSave = Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                self?.save()
            }
        }

        /// Writes the board down at a quiet moment: a checkpoint in its history, then the readable board file and
        /// the view, in that order on the journal's own queue.
        public func save() {
            guard let journal, let store, session.history.isQuiet else { return }
            unsaved = 0
            let board = session.board
            let view = session.viewport
            journal.checkpoint(board, history: session.history) {
                try? store.save(board)
                store.saveView(view)
            }
        }

        /// The board is leaving the screen: what was being typed or dragged is settled and everything is written.
        public func close() {
            mutate { session in
                session.finishEditing()
                session.cancel()
            }
            idleSave?.cancel()
            save()
            journal?.flush()
        }

        // MARK: What the canvas draws

        /// The frame to draw now. Takes the changes since the last one.
        func scene(size: Vec2, contentScale: Double, showsHover: Bool) -> BoardScene {
            var overlay = BoardDrawList.Overlay(accent: accent, ink: session.board.paper.ink)
            if session.tool == .select {
                overlay.selection = session.selectionBounds
                overlay.marquee = session.marquee
            }
            if session.tool == .erase {
                overlay.eraser = eraserAt
                overlay.eraserRadius = session.eraserRadius
            } else if showsHover {
                overlay.hover = hover
            }
            var scene = BoardScene(board: session.board, viewport: session.viewport, size: size, contentScale: contentScale, overlay: overlay)
            scene.changes = changes
            changes = BoardChanges()
            scene.interacting = interacting
            scene.hidden = session.hidden
            scene.lifted = session.lifted
            scene.liveStroke = session.liveStroke(predicted: predicted)
            scene.liveBrush = session.brush
            scene.editingNote = session.editingNote
            return scene
        }

        /// The canvas' size in points. The first time it is known, a board that has never been looked at shows
        /// everything.
        func sized(_ size: Vec2) {
            viewSize = size
            guard fitsWhenSized, isLoaded, size.x > 0, size.y > 0 else { return }
            fitsWhenSized = false
            mutate { $0.zoomToFit(size: size) }
        }

        /// Shows the whole board.
        public func showEverything() {
            guard viewSize.x > 0, viewSize.y > 0 else { return }
            let size = viewSize
            mutate { $0.zoomToFit(size: size) }
        }

        /// Puts a tool in the hand: what was being typed or dragged is settled first, and only Select keeps a pick.
        public func setTool(_ tool: BoardTool) {
            mutate { session in
                session.cancel()
                session.finishEditing()
                session.tool = tool
                if tool != .select { session.selection = [] }
            }
        }

        /// A Pencil touched: from now on fingers move the view (unless Settings says they draw too).
        func pencilTouched() {
            if pencilOrHand.pencilTouched() { pencilOrHand.save(to: defaults) }
        }

        // MARK: Buttons and menus

        public func undo() {
            if mutate({ $0.undo() }) { HmmHaptics.play(.undo) }
        }

        public func redo() {
            if mutate({ $0.redo() }) { HmmHaptics.play(.undo) }
        }

        public func duplicateSelection() {
            mutate { $0.duplicateSelection() }
        }

        public func deleteSelection() {
            mutate { $0.deleteSelection() }
        }

        public func bringSelectionToFront() {
            mutate { $0.bringSelectionToFront() }
        }

        public func sendSelectionToBack() {
            mutate { $0.sendSelectionToBack() }
        }

        public func copySelection() {
            if let copied = session.copySelection() { Self.clipboard = copied }
        }

        /// Pastes what was copied at a board point (nil: a little off where it came from).
        public func paste(at point: Vec2? = nil) {
            guard let clipboard = Self.clipboard else { return }
            mutate { $0.paste(clipboard, at: point) }
        }

        /// The hold menu of what is under a point with the Select tool (nil: nothing with a menu there).
        public func holdMenu(at point: Vec2, slack: Double) -> HmmHoldMenu? {
            guard session.tool == .select else { return nil }
            guard let item = session.board.item(at: point, tolerance: slack) else {
                guard Self.clipboard != nil else { return nil }
                return HmmHoldMenu(paste: { [weak self] in self?.paste(at: point) })
            }
            let id = item.id
            if !session.board.carried(by: session.selection).contains(id) {
                mutate { session in
                    session.cancel()
                    session.selection = [id]
                }
            }
            var extras: [HmmHoldMenu.Item] = []
            if canPin {
                extras.append(HmmHoldMenu.Item("Pin to the project", id: "board-pin", systemName: "pin") { [weak self] in self?.pinExcerpt(of: id) })
            }
            extras.append(HmmHoldMenu.Item("Bring to the front", systemName: "square.3.layers.3d.top.filled") { [weak self] in
                self?.bringSelectionToFront()
            })
            extras.append(HmmHoldMenu.Item("Send to the back", systemName: "square.3.layers.3d.bottom.filled") { [weak self] in
                self?.sendSelectionToBack()
            })
            // A row a thing can't do stays in its place, dimmed: only frames have names, Paste needs a copy.
            var rename: (@MainActor () -> Void)?
            if item.frame != nil {
                rename = { [weak self] in
                    self?.renaming = id
                }
            }
            var paste: (@MainActor () -> Void)?
            if Self.clipboard != nil {
                paste = { [weak self] in
                    self?.paste(at: point)
                }
            }
            return HmmHoldMenu(duplicate: { [weak self] in self?.duplicateSelection() }, rename: rename,
                               copy: { [weak self] in self?.copySelection() }, paste: paste, extras: extras,
                               delete: { [weak self] in self?.deleteSelection() })
        }

        // MARK: Pictures

        /// Puts a picture (PNG, JPEG, HEIC…) on the board, in the middle of the view unless `point` says where.
        public func addPicture(_ data: Data, at point: Vec2? = nil) {
            guard let store, let size = BoardTextures.pixelSize(of: data) else {
                message = "That picture couldn't be read."
                return
            }
            do {
                let name = try store.storeAsset(data, fileExtension: Self.fileExtension(of: data))
                let center = point ?? session.viewport.center
                mutate { $0.addPicture(asset: name, pixelSize: Vec2(size.width, size.height), at: center) }
            } catch {
                message = "That picture couldn't be saved."
            }
        }

        /// The usual extension for a picture's bytes (Image I/O reads by content; the name is for people).
        static func fileExtension(of data: Data) -> String {
            let head = [UInt8](data.prefix(12))
            if head.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
            if head.starts(with: [0xFF, 0xD8]) { return "jpg" }
            if head.starts(with: [0x47, 0x49, 0x46]) { return "gif" }
            if head.count >= 12, Array(head[4 ..< 8]) == [0x66, 0x74, 0x79, 0x70] { return "heic" }
            return "img"
        }

        // MARK: Pins and shared pictures

        public var canPin: Bool { pin != nil && renderer != nil && !session.board.isEmpty }

        /// Hands the app a picture of a frame, of the selection `id` belongs to, or (nil) of the whole board.
        public func pinExcerpt(of id: String?) {
            guard let pin, let excerpt = session.excerpt(of: id), let png = png(of: excerpt, showingOnlyItsItems: frame(id) == nil) else { return }
            pin(BoardPin(png: png, title: excerpt.title, size: Vec2(excerpt.rect.width, excerpt.rect.height)))
            HmmHaptics.play(.commit)
        }

        private func frame(_ id: String?) -> BoardFrame? {
            id.flatMap { session.board.item($0)?.frame }
        }

        /// A PNG of a part of the board on its paper, at two pixels a unit. A frame shows everything in its area;
        /// anything else, only what was picked.
        public func png(of excerpt: BoardExcerpt, showingOnlyItsItems: Bool) -> Data? {
            let items = showingOnlyItsItems ? excerpt.items : nil
            guard let image = renderer?.snapshot(of: session.board, items: items, region: excerpt.rect, pixelsPerUnit: 2) else { return nil }
            return Self.png(image)
        }

        /// What Share sends: the frame or selection in the hand, else the whole board.
        public func sharedPNG() -> Data? {
            let id = session.selection.count == 1 ? session.selection.first : nil
            let target = session.selection.isEmpty ? session.excerpt(of: nil) : session.excerpt(of: id ?? session.selection.first)
            guard let target else { return nil }
            return png(of: target, showingOnlyItsItems: !session.selection.isEmpty && frame(id) == nil)
        }

        static func png(_ image: CGImage) -> Data? {
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(destination, image, nil)
            return CGImageDestinationFinalize(destination) ? data as Data : nil
        }
    }
#endif
