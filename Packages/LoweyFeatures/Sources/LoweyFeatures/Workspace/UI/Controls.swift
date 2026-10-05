import HmmDesign
import LoweyCore
import SwiftUI
import UIKit

/// A labelled horizontal slider for panels (the sidebar's vertical sliders are HmmSlider).
struct LabeledSlider: View {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    var format: (Double) -> String = { NumberFormat.short($0) }
    let set: @MainActor (Double) -> Void
    var done: @MainActor () -> Void = {}
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.xxs) {
            HStack {
                Text(LocalizedStringKey(title)).font(.hmm(.footnote, weight: .semibold)).foregroundStyle(theme.text2)
                Spacer()
                Text(format(value)).font(.hmmNumbers(.footnote)).foregroundStyle(theme.text2)
            }
            Slider(value: Binding(get: { value }, set: set), in: range) { editing in
                if !editing { done() }
            }
            .accessibilityLabel(title)
            .accessibilityValue(format(value))
        }
    }
}

/// One selectable pill among a few.
struct ChoiceChip: View {
    let title: String
    var systemName: String?
    let isOn: Bool
    let action: () -> Void
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        Button {
            HmmHaptics.play(.selection)
            action()
        } label: {
            HStack(spacing: HmmSpacing.xxs) {
                if let systemName { Image(systemName: systemName) }
                Text(LocalizedStringKey(title)).lineLimit(1)
            }
            .font(.hmm(.footnote, weight: .semibold))
            .padding(.horizontal, HmmSpacing.s)
            .frame(minHeight: 36)
            .foregroundStyle(isOn ? theme.onAccent : theme.text)
            .background(Capsule().fill(isOn ? theme.accent : theme.surface2.opacity(0.9)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// A square tile with an icon and a title (Build, presets, moves, effects).
struct TileButton: View {
    let title: String
    let systemName: String
    var identifier: String?
    let action: () -> Void
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        Button {
            HmmHaptics.play(.selection)
            action()
        } label: {
            VStack(spacing: HmmSpacing.xxs) {
                Image(systemName: systemName).symbolRenderingMode(.hierarchical).font(.system(size: 20, weight: .medium))
                Text(LocalizedStringKey(title)).font(.hmm(.caption, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 60)
            .foregroundStyle(theme.text)
            .background(RoundedRectangle(cornerRadius: HmmRadius.card, style: .continuous).fill(theme.surface2.opacity(0.9)))
            .contentShape(RoundedRectangle(cornerRadius: HmmRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier ?? title)
        .hoverEffect(.lift)
    }
}

/// A grid of tiles that adapts to the panel's width.
struct TileGrid<Content: View>: View {
    var minimum: CGFloat = 84
    @ViewBuilder let content: () -> Content

    var body: some View {
        // Not lazy: a panel holds a handful of tiles, and VoiceOver (and the UI tests) must reach the ones below the fold.
        TileLayout(minimum: minimum, spacing: HmmSpacing.xs) {
            content()
        }
    }
}

/// Equal-width tiles in as many columns as fit at `minimum` wide, rows as tall as their tallest tile.
struct TileLayout: Layout {
    var minimum: CGFloat
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout Void) -> CGSize {
        let width = proposal.width ?? minimum * 3 + spacing * 2
        let rows = rows(subviews, width: width)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout Void) {
        let tile = columns(width: bounds.width).tile
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            for (column, index) in row.indices.enumerated() {
                let x = bounds.minX + CGFloat(column) * (tile + spacing)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: tile, height: row.height))
            }
            y += row.height + spacing
        }
    }

    private func columns(width: CGFloat) -> (count: Int, tile: CGFloat) {
        let count = max(Int((width + spacing) / (minimum + spacing)), 1)
        return (count, (width - spacing * CGFloat(count - 1)) / CGFloat(count))
    }

    private func rows(_ subviews: Subviews, width: CGFloat) -> [(indices: Range<Int>, height: CGFloat)] {
        let (count, tile) = columns(width: width)
        return stride(from: 0, to: subviews.count, by: count).map { start in
            let indices = start ..< min(start + count, subviews.count)
            let height = indices.map { subviews[$0].sizeThatFits(ProposedViewSize(width: tile, height: nil)).height }.max() ?? 0
            return (indices, height)
        }
    }
}

/// Palette slots as swatches (tap to use; touch and hold to remove when allowed).
struct PaletteRow: View {
    let palette: Palette
    let selected: Int?
    var remove: ((Int) -> Void)?
    let pick: (Int) -> Void
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 36), spacing: HmmSpacing.xs)], spacing: HmmSpacing.xs) {
            ForEach(palette.visibleSlots, id: \.self) { index in
                let swatch = palette.swatches[index]
                Button {
                    HmmHaptics.play(.selection)
                    pick(index)
                } label: {
                    Circle()
                        .fill(swatch.color.color)
                        .frame(width: 36, height: 36)
                        .overlay(Circle().stroke(selected == index ? theme.accent : theme.line, lineWidth: selected == index ? 3 : 1))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(swatch.name)
                .accessibilityAddTraits(selected == index ? .isSelected : [])
                .contextMenu {
                    if let remove {
                        Button("Remove from palette", systemImage: "trash", role: .destructive) { remove(index) }
                    }
                }
            }
        }
    }
}

/// Small text under a control explaining it.
struct Hint: View {
    let text: String
    @Environment(\.hmmTheme) private var theme

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(LocalizedStringKey(text)).font(.hmm(.caption)).foregroundStyle(theme.text2).fixedSize(horizontal: false, vertical: true)
    }
}

/// A section of a panel: a header and its controls.
struct PanelSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.xs) {
            // A stable handle for the layout walk (the header's label is upper-cased for display).
            HmmSectionHeader(title).accessibilityIdentifier("section-\(title)")
            content()
        }
        .padding(.top, HmmSpacing.xxs)
    }
}

/// The system share sheet.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}

struct IdentifiedURL: Identifiable {
    let url: URL
    var id: String { url.path }
}

/// A small capsule label (RIGGED, PREFAB, iCloud).
struct Badge: View {
    let text: String
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        Text(LocalizedStringKey(text))
            .font(.hmm(.caption, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(theme.accent.opacity(0.2)))
            .foregroundStyle(theme.accent)
    }
}

/// Wrapping toggle chips.
struct FlowChips: View {
    let items: [(key: String, title: String)]
    let isOn: (String) -> Bool
    let toggle: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: HmmSpacing.xs)], alignment: .leading, spacing: HmmSpacing.xs) {
            ForEach(items, id: \.key) { item in
                ChoiceChip(title: item.title, isOn: isOn(item.key)) { toggle(item.key) }
            }
        }
    }
}
