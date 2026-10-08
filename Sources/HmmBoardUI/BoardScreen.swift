#if canImport(UIKit) && canImport(Metal) && canImport(SwiftUI) && !os(watchOS) && !os(tvOS)
    import HmmBoard
    import HmmBrush
    import HmmDesign
    import PhotosUI
    import SwiftUI

    /// The Schizzo board, whole: the canvas under the studio's layout. Top left is the board itself (back, actions,
    /// select); top right the making tools (draw, erase, note, arrow, frame); the sidebar holds size, opacity, the
    /// colour and undo/redo. The app plugs in its own brush row and colour chooser.
    public struct HmmBoardScreen<BrushRow: View, Colours: View>: View {
        let model: BoardModel
        let showsHover: Bool
        let sidebarOnRight: Bool
        let close: () -> Void
        let brushRow: BrushRow
        let colours: (Binding<Color>) -> Colours
        @State var chromeHidden = false
        @State var choosingColour = false
        @State var pickingPhoto = false
        @State var photo: PhotosPickerItem?
        @State var shared: BoardSharedPicture?
        @State var frameTitle = ""
        @State var toast: HmmToastMessage?
        @Environment(\.hmmTheme) var theme
        @Environment(\.self) var environment

        /// - Parameters:
        ///   - showsHover: the app's "Pencil hover" setting.
        ///   - brushRow: the brush in the hand, as the app shows it (it sets `model`'s brush).
        ///   - colours: the app's colour chooser, shown from the sidebar's colour well.
        public init(model: BoardModel, showsHover: Bool = true, sidebarOnRight: Bool = false, close: @escaping () -> Void,
                    @ViewBuilder brushRow: () -> BrushRow, @ViewBuilder colours: @escaping (Binding<Color>) -> Colours) {
            self.model = model
            self.showsHover = showsHover
            self.sidebarOnRight = sidebarOnRight
            self.close = close
            self.brushRow = brushRow()
            self.colours = colours
        }

        public var body: some View {
            ZStack {
                BoardCanvas(model: model, showsHover: showsHover, fingerMakes: model.pencilOrHand.fingerMakes)
                    .ignoresSafeArea()
                if model.isLoaded, model.session.board.isEmpty, !model.session.isBusy {
                    Text("Draw, drop a picture or add a note.")
                        .font(.system(size: 15))
                        .foregroundStyle(theme.text3)
                        .allowsHitTesting(false)
                }
                BoardNoteEditor(model: model)
                if !chromeHidden {
                    chrome
                }
            }
            .background(paperColour.ignoresSafeArea())
            .task { await model.load() }
            .onDisappear { model.close() }
            .hmmUniversalGestures(HmmGestureActions(undo: { model.undo() }, redo: { model.redo() }, toggleChrome: { chromeHidden.toggle() }))
            .photosPicker(isPresented: $pickingPhoto, selection: $photo, matching: .images)
            .onChange(of: photo) { _, item in addPhoto(item) }
            .onChange(of: model.message) { _, text in show(text) }
            .onChange(of: model.renaming) { _, id in frameTitle = id.flatMap { model.session.board.item($0)?.frame?.title } ?? "" }
            .sheet(item: $shared) { picture in BoardShareSheet(url: picture.url) }
            .alert("Rename", isPresented: renamingBinding) {
                TextField("Name", text: $frameTitle)
                Button("Rename") { rename() }
                Button("Cancel", role: .cancel) {}
            }
            .hmmToast($toast)
        }

        private var paperColour: Color {
            let paper = model.session.board.paper.color
            return Color(.sRGB, red: paper.red, green: paper.green, blue: paper.blue, opacity: 1)
        }

        // MARK: Chrome

        private var chrome: some View {
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    boardCluster
                    Spacer(minLength: HmmSpacing.s)
                    HmmCornerCluster(toolItems)
                }
                HStack {
                    if sidebarOnRight { Spacer() }
                    sidebar
                    if !sidebarOnRight { Spacer() }
                }
                .frame(maxHeight: .infinity)
                HStack(alignment: .bottom) {
                    Spacer()
                    bottomBar
                    Spacer()
                    zoomButton
                }
            }
            .padding(HmmSpacing.m)
        }

        private var boardCluster: some View {
            HStack(spacing: HmmSpacing.xxs) {
                HmmButton("chevron.backward", label: "Back", action: close)
                    .accessibilityIdentifier("board-close")
                BoardActionsMenu(model: model, addPicture: { pickingPhoto = true }, share: share)
                HmmButton("hand.point.up.left", label: "Select", isOn: model.session.tool == .select) { model.setTool(.select) }
            }
            .padding(HmmSpacing.xxs)
            .environment(\.hmmInsideGlass, true)
            .hmmGlass(in: Capsule(), interactive: false)
        }

        private var toolItems: [HmmClusterItem] {
            let tools: [(BoardTool, String, String)] = [
                (.draw, "pencil.tip", "Draw"), (.erase, "eraser", "Erase"), (.note, "note.text", "Note"), (.arrow, "arrow.up.right", "Arrow"),
                (.frame, "rectangle.dashed", "Draw a frame")
            ]
            return tools.map { tool, symbol, label in
                HmmClusterItem(id: "board-\(tool.rawValue)", systemName: symbol, label: label, isOn: model.session.tool == tool) {
                    model.setTool(tool)
                }
            }
        }

        private var sidebar: some View {
            let size = HmmSidebarSlider("Size", value: sizeBinding, in: 0 ... 1, format: { _ in sizeText })
            let opacity = HmmSidebarSlider("Opacity", value: opacityBinding, in: 0.05 ... 1)
            return HmmSidebar(top: size, bottom: opacity, accessory: AnyView(colourWell), canUndo: model.session.canUndo,
                              canRedo: model.session.canRedo, undo: { model.undo() }, redo: { model.redo() })
        }

        private var colourWell: some View {
            HmmColourWell(colourBinding.wrappedValue) { choosingColour = true }
                .popover(isPresented: $choosingColour) {
                    colours(colourBinding)
                        .padding(HmmSpacing.m)
                        .frame(minWidth: 280)
                }
        }

        @ViewBuilder private var bottomBar: some View {
            if model.session.tool == .draw {
                brushRow
            } else if model.session.tool == .select, !model.session.selection.isEmpty {
                selectionBar
            }
        }

        /// What can be done with the pick, under the board (the hold menu on each thing has the same and more).
        private var selectionBar: some View {
            HStack(spacing: HmmSpacing.xxs) {
                if model.canPin {
                    HmmButton("pin", label: "Pin to the project") { model.pinExcerpt(of: model.session.selection.first) }
                        .accessibilityIdentifier("board-pin")
                }
                HmmButton("plus.square.on.square", label: "Duplicate") { model.duplicateSelection() }
                HmmButton("trash", label: "Delete", role: .destructive) { model.deleteSelection() }
            }
            .padding(HmmSpacing.xxs)
            .environment(\.hmmInsideGlass, true)
            .hmmGlass(in: Capsule(), interactive: false)
        }

        private var zoomButton: some View {
            Button {
                HmmHaptics.play(.selection)
                model.showEverything()
            } label: {
                Text(verbatim: model.session.viewport.percentText)
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(theme.text)
                    .padding(.horizontal, HmmSpacing.s)
                    .frame(height: HmmTarget.minimum)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .hmmGlass(in: Capsule(), interactive: false)
            .accessibilityLabel(Text("Show everything"))
            .accessibilityIdentifier("board-zoom")
        }

        // MARK: Values

        /// The slider runs evenly from a hairline (half a unit) to a broad marker (60 units).
        private var sizeBinding: Binding<Double> {
            Binding(get: { log(max(model.session.size, 0.5) / 0.5) / log(120) }, set: { value in
                model.mutate { $0.size = 0.5 * pow(120, value) }
            })
        }

        private var sizeText: String {
            let width = model.session.size * 2
            return width < 10 ? String(format: "%.1f", width) : String(Int(width.rounded()))
        }

        private var opacityBinding: Binding<Double> {
            Binding(get: { model.session.opacity }, set: { value in model.mutate { $0.opacity = value } })
        }

        private var colourBinding: Binding<Color> {
            Binding(get: {
                let color = model.session.color
                return Color(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: 1)
            }, set: { chosen in
                let resolved = chosen.resolve(in: environment)
                let color = BoardColor(red: Double(resolved.red), green: Double(resolved.green), blue: Double(resolved.blue))
                model.mutate { $0.setColor(color) }
            })
        }

        private var renamingBinding: Binding<Bool> {
            Binding(get: { model.renaming != nil }, set: { shown in
                if !shown { model.renaming = nil }
            })
        }

        // MARK: Actions

        private func rename() {
            guard let id = model.renaming else { return }
            let title = frameTitle
            model.mutate { $0.rename(frame: id, to: title) }
            model.renaming = nil
        }

        private func show(_ text: String?) {
            guard let text else { return }
            // The model speaks English; the app's String Catalog says it in the person's language.
            toast = HmmToastMessage(NSLocalizedString(text, comment: ""), kind: .error)
            model.message = nil
        }

        private func addPhoto(_ item: PhotosPickerItem?) {
            guard let item else { return }
            photo = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    model.addPicture(data)
                } else {
                    model.message = "That picture couldn't be read."
                }
            }
        }

        private func share() {
            guard let data = model.sharedPNG() else { return }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Board.png")
            do {
                try data.write(to: url, options: .atomic)
                shared = BoardSharedPicture(url: url)
            } catch {
                model.message = "That picture couldn't be saved."
            }
        }
    }

    /// A picture written out to be shared.
    struct BoardSharedPicture: Identifiable {
        let id = UUID()
        let url: URL
    }
#endif
