#if canImport(SwiftUI)
    import SwiftUI

    /// One button of a corner cluster.
    public struct HmmClusterItem: Identifiable {
        public var id: String
        public var systemName: String
        public var label: String
        public var isOn: Bool
        public var isEnabled: Bool
        public var action: () -> Void

        public init(id: String, systemName: String, label: String, isOn: Bool = false, isEnabled: Bool = true, action: @escaping () -> Void) {
            self.id = id
            self.systemName = systemName
            self.label = label
            self.isOn = isOn
            self.isEnabled = isEnabled
            self.action = action
        }
    }

    /// A row of icon buttons sharing one glass capsule, for a canvas corner. Top-left holds document and app-level
    /// actions; top-right holds the app's making tools.
    public struct HmmCornerCluster: View {
        private let items: [HmmClusterItem]

        public init(_ items: [HmmClusterItem]) {
            self.items = items
        }

        public var body: some View {
            HStack(spacing: HmmSpacing.xxs) {
                ForEach(items) { item in
                    HmmButton(item.systemName, label: item.label, isOn: item.isOn, action: item.action)
                        .disabled(!item.isEnabled)
                }
            }
            .padding(HmmSpacing.xxs)
            .environment(\.hmmInsideGlass, true)
            .hmmGlass(in: Capsule(), interactive: false)
        }
    }

    /// A vertical sidebar slider's configuration.
    public struct HmmSidebarSlider {
        public var title: String
        public var value: Binding<Double>
        public var range: ClosedRange<Double>
        public var format: (Double) -> String
        public var onEditingChanged: (Bool) -> Void

        public init(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>,
                    format: @escaping (Double) -> String = { String(Int(($0 * 100).rounded())) + "%" },
                    onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
            self.title = title
            self.value = value
            self.range = range
            self.format = format
            self.onEditingChanged = onEditingChanged
        }
    }

    /// The Procreate sidebar: two context sliders with the Pick button between them, undo and redo below.
    /// It sits on the left edge, or on the right for left-handed use (`mirrored`).
    public struct HmmSidebar: View {
        private let top: HmmSidebarSlider?
        private let bottom: HmmSidebarSlider?
        private let pickActive: Bool
        private let pick: (() -> Void)?
        private let undoState: (canUndo: Bool, canRedo: Bool)
        private let undo: () -> Void
        private let redo: () -> Void

        public init(top: HmmSidebarSlider?, bottom: HmmSidebarSlider?, pickActive: Bool = false, pick: (() -> Void)? = nil,
                    canUndo: Bool, canRedo: Bool, undo: @escaping () -> Void, redo: @escaping () -> Void) {
            self.top = top
            self.bottom = bottom
            self.pickActive = pickActive
            self.pick = pick
            undoState = (canUndo, canRedo)
            self.undo = undo
            self.redo = redo
        }

        public var body: some View {
            VStack(spacing: HmmSpacing.s) {
                if let top {
                    HmmSlider(top.title, value: top.value, in: top.range, length: 150, format: top.format,
                              onEditingChanged: top.onEditingChanged)
                }
                if let pick {
                    HmmButton("eyedropper", label: "Pick", isOn: pickActive, action: pick)
                }
                if let bottom {
                    HmmSlider(bottom.title, value: bottom.value, in: bottom.range, length: 150, format: bottom.format,
                              onEditingChanged: bottom.onEditingChanged)
                }
                HmmButton("arrow.uturn.backward", label: "Undo", action: undo)
                    .disabled(!undoState.canUndo)
                HmmButton("arrow.uturn.forward", label: "Redo", action: redo)
                    .disabled(!undoState.canRedo)
            }
        }
    }

    /// A floating panel with a title row: opens from the button that called it, scrolls when Dynamic Type grows.
    /// With `sizing`, a grip in its bottom corner resizes it and the size is remembered (`hmmResizable`).
    public struct HmmPanel<Content: View>: View {
        private let title: String
        private let width: Double
        private let close: (() -> Void)?
        private let sizing: HmmPanelSizing?
        private let gripOnTrailing: Bool
        private let content: Content
        @State private var size: HmmPanelSize?
        @Environment(\.hmmTheme) private var theme

        public init(_ title: String, width: Double = 340, sizing: HmmPanelSizing? = nil, gripOnTrailing: Bool = true,
                    close: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
            self.title = title
            self.width = width
            self.sizing = sizing
            self.gripOnTrailing = gripOnTrailing
            self.close = close
            self.content = content()
        }

        public var body: some View {
            if let sizing {
                panel
                    .hmmResizable(sizing, size: $size, defaultWidth: width, gripOnTrailing: gripOnTrailing, title: title)
                    .hmmPanelBackground()
            } else {
                panel.frame(width: width).hmmPanelBackground()
            }
        }

        private var panel: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(LocalizedStringKey(title))
                        .font(.hmm(.headline, weight: .semibold))
                        .foregroundStyle(theme.text)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: HmmSpacing.xs)
                    if let close {
                        HmmButton("xmark", label: "Close \(title)", size: 32, action: close)
                    }
                }
                .padding(.horizontal, HmmSpacing.m)
                .padding(.top, HmmSpacing.s)
                .padding(.bottom, HmmSpacing.xs)
                ScrollView {
                    content
                        .padding(.horizontal, HmmSpacing.m)
                        .padding(.bottom, HmmSpacing.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    public extension View {
        /// A resize grip in the bottom corner: drag it to resize, double-tap it for the original size. The size is
        /// remembered per panel (`sizing`) and shared through `size` (nil = the original size). With `appliesFrame`
        /// off, the caller sizes the view from `size` itself (a panel placed by `HmmFloatingPlacement`).
        func hmmResizable(_ sizing: HmmPanelSizing, size: Binding<HmmPanelSize?>, defaultWidth: Double, gripOnTrailing: Bool = true,
                          title: String, appliesFrame: Bool = true) -> some View {
            modifier(HmmResizable(sizing: sizing, size: size, defaultWidth: defaultWidth, gripOnTrailing: gripOnTrailing, title: title,
                                  appliesFrame: appliesFrame))
        }
    }

    struct HmmResizable: ViewModifier {
        let sizing: HmmPanelSizing
        @Binding var size: HmmPanelSize?
        let defaultWidth: Double
        let gripOnTrailing: Bool
        let title: String
        let appliesFrame: Bool
        @State private var dragStart: HmmPanelSize?
        @State private var shownHeight: Double = 0
        @Environment(\.layoutDirection) private var layoutDirection

        func body(content: Content) -> some View {
            framed(content)
                .onGeometryChange(for: Double.self) { Double($0.size.height) } action: { shownHeight = $0 }
                .overlay(alignment: gripOnTrailing ? .bottomTrailing : .bottomLeading) { grip }
                .onAppear { if size == nil { size = sizing.load() } }
        }

        @ViewBuilder
        private func framed(_ content: Content) -> some View {
            if appliesFrame {
                content
                    .frame(width: size?.width ?? defaultWidth)
                    .frame(maxHeight: size?.height.map { CGFloat($0) })
            } else {
                content
            }
        }

        /// Whether the grip is on the right as the glass shows it (global drags are measured that way; the trailing
        /// edge is the left one in right-to-left languages).
        private var gripOnRight: Bool { gripOnTrailing != (layoutDirection == .rightToLeft) }

        private func resetSize() {
            sizing.reset()
            withHmmAnimation(.standard) { size = nil }
        }

        private var grip: some View {
            HmmResizeGrip(mirrored: !gripOnRight)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { value in
                            let start = dragStart ?? size ?? HmmPanelSize(width: defaultWidth)
                            if dragStart == nil { dragStart = start }
                            size = sizing.resized(start, shownHeight: shownHeight, dx: Double(value.translation.width),
                                                  dy: Double(value.translation.height), gripOnRight: gripOnRight)
                        }
                        .onEnded { _ in
                            dragStart = nil
                            if let size { sizing.save(size) }
                        }
                )
                .onTapGesture(count: 2, perform: resetSize)
                .accessibilityElement()
                .accessibilityLabel(Text("Resize \(title)"))
                .accessibilityHint(Text("Double-tap for the original size"))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { resetSize() }
                .accessibilityIdentifier("resize-\(sizing.id)")
        }
    }

    /// The two short diagonal strokes in a resizable panel's corner.
    struct HmmResizeGrip: View {
        let mirrored: Bool
        @Environment(\.hmmTheme) private var theme

        var body: some View {
            Canvas { context, canvas in
                var path = Path()
                let inset: CGFloat = 12
                for step in [CGFloat(6), 12] {
                    path.move(to: CGPoint(x: canvas.width - inset - step, y: canvas.height - inset))
                    path.addLine(to: CGPoint(x: canvas.width - inset, y: canvas.height - inset - step))
                }
                context.stroke(path, with: .color(theme.text3), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            .scaleEffect(x: mirrored ? -1 : 1)
            .allowsHitTesting(false)
        }
    }

    /// Standard sheet body: title, optional subtitle, content, one primary action.
    public struct HmmSheet<Content: View>: View {
        private let title: String
        private let subtitle: String?
        private let primary: (title: String, action: () -> Void)?
        private let content: Content
        @Environment(\.dismiss) private var dismiss
        @Environment(\.hmmTheme) private var theme

        public init(_ title: String, subtitle: String? = nil, primary: (title: String, action: () -> Void)? = nil,
                    @ViewBuilder content: () -> Content) {
            self.title = title
            self.subtitle = subtitle
            self.primary = primary
            self.content = content()
        }

        public var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: HmmSpacing.m) {
                        if let subtitle {
                            Text(LocalizedStringKey(subtitle)).font(.hmm(.body)).foregroundStyle(theme.text2)
                        }
                        content
                    }
                    .padding(HmmSpacing.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .navigationTitle(Text(LocalizedStringKey(title)))
                .navigationBarTitleDisplayModeInline()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                    if let primary {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(LocalizedStringKey(primary.title), action: primary.action).fontWeight(.semibold)
                        }
                    }
                }
            }
        }
    }

    extension View {
        /// Inline titles on iOS (macOS has no such mode).
        func navigationBarTitleDisplayModeInline() -> some View {
            #if os(iOS)
                navigationBarTitleDisplayMode(.inline)
            #else
                self
            #endif
        }
    }

    /// A small upper-case section title inside panels.
    public struct HmmSectionHeader: View {
        private let title: String
        @Environment(\.hmmTheme) private var theme

        public init(_ title: String) {
            self.title = title
        }

        public var body: some View {
            Text(LocalizedStringKey(title))
                .textCase(.uppercase)
                .font(.hmm(.caption, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(theme.text2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
        }
    }
#endif
