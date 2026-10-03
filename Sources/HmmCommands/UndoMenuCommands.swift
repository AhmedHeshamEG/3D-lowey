#if canImport(SwiftUI)
    import SwiftUI

    /// What the Undo menu needs to know about the focused document.
    public struct UndoMenuState: Sendable, Equatable {
        public var undoTitle: String
        public var redoTitle: String
        public var canUndo: Bool
        public var canRedo: Bool

        public init(undoTitle: String = "Undo", redoTitle: String = "Redo", canUndo: Bool = false, canRedo: Bool = false) {
            self.undoTitle = undoTitle
            self.redoTitle = redoTitle
            self.canUndo = canUndo
            self.canRedo = canRedo
        }

        public init(_ stack: CommandStack<some EditCommand>) {
            self.init(undoTitle: stack.undoTitle, redoTitle: stack.redoTitle, canUndo: stack.canUndo, canRedo: stack.canRedo)
        }
    }

    /// Replaces the system Undo/Redo menu items with the document's own labelled ones ("Undo Move Camera", ⌘Z / ⇧⌘Z).
    public struct UndoMenuCommands: Commands {
        private let state: UndoMenuState
        private let undo: @MainActor () -> Void
        private let redo: @MainActor () -> Void

        public init(state: UndoMenuState, undo: @escaping @MainActor () -> Void, redo: @escaping @MainActor () -> Void) {
            self.state = state
            self.undo = undo
            self.redo = redo
        }

        public var body: some Commands {
            CommandGroup(replacing: .undoRedo) {
                Button(LocalizedStringKey(state.undoTitle), action: undo)
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!state.canUndo)
                Button(LocalizedStringKey(state.redoTitle), action: redo)
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!state.canRedo)
            }
        }
    }
#endif
