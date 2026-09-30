#if canImport(SwiftUI)
    import SwiftUI

    /// Every HmmDesign component in dark and light, side by side (Settings ▸ Diagnostics ▸ Design Gallery in debug and
    /// sideload builds). The quickest way to see that a token change didn't break a screen.
    public struct HmmDesignGallery: View {
        private let accent: HmmAccent

        public init(accent: HmmAccent) {
            self.accent = accent
        }

        public var body: some View {
            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    GalleryColumn(accent: accent)
                        .environment(\.colorScheme, .dark)
                        .hmmThemed(accent)
                    GalleryColumn(accent: accent)
                        .environment(\.colorScheme, .light)
                        .hmmThemed(accent)
                }
            }
            .navigationTitle("Design Gallery")
        }
    }

    private struct GalleryColumn: View {
        let accent: HmmAccent
        @Environment(\.hmmTheme) private var theme
        @State private var size = 0.4
        @State private var opacity = 0.8
        @State private var toast: HmmToastMessage?

        var body: some View {
            VStack(alignment: .leading, spacing: HmmSpacing.l) {
                Text(theme.appearance == .dark ? "Dark" : "Light").font(.hmm(.title3, weight: .semibold))
                colours
                typeScale
                HmmSectionHeader("Buttons")
                HStack(spacing: HmmSpacing.xs) {
                    HmmButton("cube", label: "Build") {}
                    HmmButton("pencil.tip", label: "Draw", isOn: true) {}
                    HmmButton("play.fill", label: "Play", size: HmmTarget.primary) {}
                    HmmButton("trash", label: "Delete", role: .destructive) {}
                }
                HStack(spacing: HmmSpacing.xs) {
                    HmmPillButton("Export", systemName: "square.and.arrow.up", prominent: true) {}
                    HmmPillButton("Cancel") {}
                }
                HmmSectionHeader("Corner cluster")
                HmmCornerCluster([
                    HmmClusterItem(id: "a", systemName: "square.grid.2x2", label: "Gallery") {},
                    HmmClusterItem(id: "b", systemName: "wrench.adjustable", label: "Actions") {},
                    HmmClusterItem(id: "c", systemName: "wand.and.stars", label: "Look", isOn: true) {}
                ])
                HmmSectionHeader("Sidebar")
                HmmSidebar(top: HmmSidebarSlider("Size", value: $size, in: 0 ... 1),
                           bottom: HmmSidebarSlider("Opacity", value: $opacity, in: 0 ... 1),
                           pick: {}, canUndo: true, canRedo: false, undo: {}, redo: {})
                HmmSectionHeader("Panel")
                HmmPanel("Inspector", width: 300, close: {}) {
                    Text("Panel content scrolls when Dynamic Type grows.").font(.hmm(.body)).foregroundStyle(theme.text2)
                }
                HmmSectionHeader("Toast")
                HmmToast(HmmToastMessage("Exported", kind: .success))
                HmmToast(HmmToastMessage("Couldn't save", kind: .error, actionTitle: "Try again")) {}
                HmmSectionHeader("Empty state")
                HmmEmptyState("film.stack", title: "No projects yet", message: "Start with a mood and a look.",
                              actionTitle: "New project") {}
            }
            .padding(HmmSpacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.background)
            .foregroundStyle(theme.text)
        }

        private var colours: some View {
            let swatches: [(String, Color)] = [
                ("bg", theme.background), ("surface", theme.surface), ("surface2", theme.surface2), ("line", theme.line),
                ("text", theme.text), ("text2", theme.text2), ("text3", theme.text3), ("accent", theme.accent),
                ("record", theme.record), ("success", theme.success), ("warning", theme.warning)
            ]
            return LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: HmmSpacing.xs)], spacing: HmmSpacing.xs) {
                ForEach(swatches, id: \.0) { name, color in
                    VStack(spacing: HmmSpacing.xxs) {
                        RoundedRectangle(cornerRadius: HmmRadius.control, style: .continuous)
                            .fill(color)
                            .frame(height: 36)
                            .overlay(RoundedRectangle(cornerRadius: HmmRadius.control, style: .continuous).stroke(theme.line))
                        Text(name).font(.hmm(.caption)).foregroundStyle(theme.text2)
                    }
                }
            }
        }

        private var typeScale: some View {
            VStack(alignment: .leading, spacing: HmmSpacing.xxs) {
                ForEach(HmmTypeScale.allCases.reversed(), id: \.self) { size in
                    Text("\(Int(size.rawValue)) pt hmm.").font(.hmm(size))
                }
                Text("00:12.48").font(.hmmNumbers(.headline))
            }
        }
    }
#endif
