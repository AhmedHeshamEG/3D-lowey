#if canImport(UIKit) && canImport(Metal) && canImport(SwiftUI) && !os(watchOS) && !os(tvOS)
    import HmmBoard
    import HmmBrush
    import HmmDesign
    import SwiftUI

    /// The Metal canvas in SwiftUI.
    struct BoardCanvas: UIViewRepresentable {
        let model: BoardModel
        let showsHover: Bool
        /// Read by the screen so a change in Settings (or the first Pencil touch) reaches the canvas' gestures.
        let fingerMakes: Bool

        func makeUIView(context _: Context) -> BoardCanvasView {
            BoardCanvasView(model: model)
        }

        func updateUIView(_ view: BoardCanvasView, context _: Context) {
            view.showsHover = showsHover
            view.applyPencilOrHand()
        }
    }

    /// The words of the note being typed, on the note itself: a text field laid over its slip, moving and scaling
    /// with the board.
    struct BoardNoteEditor: View {
        let model: BoardModel
        @FocusState private var typing: Bool

        var body: some View {
            if let id = model.session.editingNote, let note = model.session.board.item(id)?.note {
                GeometryReader { proxy in
                    field(id: id, note: note, size: Vec2(proxy.size.width, proxy.size.height))
                }
                .ignoresSafeArea()
            }
        }

        private func field(id: String, note: BoardNote, size: Vec2) -> some View {
            let view = model.session.viewport
            let inner = note.rect.expanded(by: -12)
            let middle = view.toScreen(inner.center, size: size)
            let darkWords = note.color.luminance > 0.5
            return TextEditor(text: text(of: id))
                .font(.system(size: 17 * view.scale))
                .foregroundStyle(darkWords ? Color(white: 0.1) : Color(white: 0.95))
                .scrollContentBackground(.hidden)
                .focused($typing)
                .frame(width: max(inner.width * view.scale, 20), height: max(inner.height * view.scale, 20))
                .position(x: middle.x, y: middle.y)
                .accessibilityIdentifier("board-note-text")
                .onAppear { typing = true }
                .onChange(of: typing) { _, focused in
                    if !focused { model.mutate { $0.finishEditing() } }
                }
        }

        private func text(of id: String) -> Binding<String> {
            Binding(get: { model.session.board.item(id)?.note?.text ?? "" }, set: { words in
                model.mutate { $0.setText(words, ofNote: id) }
            })
        }
    }

    /// The board's Actions: the long tail (pictures, paste, the paper, sharing, pinning everything).
    struct BoardActionsMenu: View {
        let model: BoardModel
        let addPicture: () -> Void
        let share: () -> Void

        var body: some View {
            Menu {
                Button(action: addPicture) { Label("Add a picture", systemImage: "photo") }
                Button(action: paste) { Label("Paste", systemImage: "doc.on.clipboard") }
                    .keyboardShortcut("v", modifiers: .command)
                Button(action: selectAll) { Label("Select all", systemImage: "checkmark.circle") }
                    .keyboardShortcut("a", modifiers: .command)
                    .disabled(model.session.board.isEmpty)
                Divider()
                Menu {
                    Picker("Pattern", selection: pattern) {
                        Text("Dots").tag(BoardPaper.Pattern.dots)
                        Text("Grid").tag(BoardPaper.Pattern.grid)
                        Text("Plain").tag(BoardPaper.Pattern.plain)
                    }
                    Picker("Paper colour", selection: dark) {
                        Text("Dark paper").tag(true)
                        Text("Light paper").tag(false)
                    }
                } label: {
                    Label("Paper", systemImage: "square.grid.3x3")
                }
                Button(action: share) { Label("Share a picture", systemImage: "square.and.arrow.up") }
                    .disabled(model.session.board.isEmpty)
                if model.canPin {
                    Button(action: pin) { Label("Pin to the project", systemImage: "pin") }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: HmmTarget.minimum, height: HmmTarget.minimum)
                    .contentShape(Circle())
            }
            .accessibilityLabel(Text("Actions"))
            .accessibilityIdentifier("board-actions")
        }

        private var pattern: Binding<BoardPaper.Pattern> {
            Binding(get: { model.session.board.paper.pattern }, set: { chosen in
                model.mutate { session in
                    var paper = session.board.paper
                    paper.pattern = chosen
                    session.setPaper(paper)
                }
            })
        }

        private var dark: Binding<Bool> {
            Binding(get: { model.session.board.paper.isDark }, set: { isDark in
                model.mutate { session in
                    var paper = session.board.paper
                    paper.color = isDark ? BoardPaper.dark : BoardPaper.light
                    session.setPaper(paper)
                }
            })
        }

        /// What was copied on a board, or else a picture copied anywhere.
        private func paste() {
            if BoardModel.clipboard != nil {
                model.paste()
            } else if let data = UIPasteboard.general.image?.pngData() {
                model.addPicture(data)
            }
        }

        private func selectAll() {
            model.mutate { session in
                session.tool = .select
                session.selectAll()
            }
        }

        /// With nothing picked, the whole board is pinned.
        private func pin() {
            model.pinExcerpt(of: model.session.selection.first)
        }
    }

    /// The system share sheet for a file.
    struct BoardShareSheet: UIViewControllerRepresentable {
        let url: URL

        func makeUIViewController(context _: Context) -> UIActivityViewController {
            UIActivityViewController(activityItems: [url], applicationActivities: nil)
        }

        func updateUIViewController(_: UIActivityViewController, context _: Context) {}
    }

    /// The brush in the hand as a menu of the built-in brushes: what a board shows when the app brings no brush
    /// library of its own.
    public struct BoardBrushMenu: View {
        let model: BoardModel
        @Environment(\.hmmTheme) private var theme

        public init(model: BoardModel) {
            self.model = model
        }

        public var body: some View {
            Menu {
                ForEach(BuiltInBrushes.all) { brush in
                    Button(brush.name) { model.mutate { $0.brush = brush } }
                }
            } label: {
                Label(model.session.brush.name, systemImage: "paintbrush.pointed")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(theme.text)
                    .padding(.horizontal, HmmSpacing.m)
                    .frame(height: HmmTarget.minimum)
                    .contentShape(Capsule())
            }
            .hmmGlass(in: Capsule(), interactive: false)
            .accessibilityIdentifier("board-brush")
        }
    }

    /// A few inks and any colour: what the colour well opens when the app brings no chooser of its own.
    public struct BoardColourGrid: View {
        @Binding var colour: Color
        private static let inks: [UInt32] = [0xEDEDEF, 0x1D1D1F, 0xFFB847, 0xFF6B4A, 0xFF453A, 0x30D158, 0x4AA8FF, 0x8B7CFF]

        public init(colour: Binding<Color>) {
            _colour = colour
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: HmmSpacing.s) {
                HStack(spacing: HmmSpacing.xs) {
                    ForEach(Self.inks, id: \.self) { hex in
                        let ink = Color(hmm: HmmRGB(hex: hex))
                        Button { colour = ink } label: {
                            Circle().fill(ink).frame(width: 30, height: 30)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(verbatim: String(hex, radix: 16)))
                    }
                }
                ColorPicker("Any colour", selection: $colour, supportsOpacity: false)
            }
        }
    }

    public extension HmmBoardScreen where BrushRow == BoardBrushMenu, Colours == BoardColourGrid {
        /// A board with the built-in brushes and a plain colour chooser.
        init(model: BoardModel, showsHover: Bool = true, sidebarOnRight: Bool = false, close: @escaping () -> Void) {
            self.init(model: model, showsHover: showsHover, sidebarOnRight: sidebarOnRight, close: close) {
                BoardBrushMenu(model: model)
            } colours: { colour in
                BoardColourGrid(colour: colour)
            }
        }
    }
#endif
