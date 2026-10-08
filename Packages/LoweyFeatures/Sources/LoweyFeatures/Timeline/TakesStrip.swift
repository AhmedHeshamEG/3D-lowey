import HmmDesign
import LoweyCore
import SwiftUI

/// The takes, above the lanes while the timeline is in Perform: one row a take, newest on top, bright where the comp
/// plays it. Drag across a take to use it from there to there; touch and hold for the rest.
struct TakesStrip: View {
    let editor: EditorModel
    let width: CGFloat
    @State private var swipe: (take: String, from: CGFloat, to: CGFloat)?
    @State private var renaming: Take?
    @State private var name = ""
    @Environment(\.hmmTheme) private var theme

    static let row: CGFloat = 26

    static func height(for editor: EditorModel) -> CGFloat {
        guard editor.timelineMode == .perform, !editor.recordedTakes.isEmpty else { return 0 }
        return CGFloat(min(editor.recordedTakes.count, 4)) * row + 1
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(editor.recordedTakes.reversed()) { take in
                    HStack(spacing: 0) {
                        label(take)
                        bar(take)
                    }
                    .frame(height: Self.row)
                    .hmmHoldMenu(menu(for: take))
                }
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(theme.line).frame(height: 1) }
        .alert("Take name", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $name)
            Button("Save") {
                if let take = renaming { editor.renameTake(take.id, to: name) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("takes")
    }

    private func label(_ take: Take) -> some View {
        let picked = editor.live.selectedTake == take.id
        return HStack(spacing: HmmSpacing.xxs) {
            Image(systemName: editor.share(of: take) > 0 ? "record.circle.fill" : "record.circle")
                .font(.system(size: 11))
                .foregroundStyle(editor.share(of: take) > 0 ? theme.accent : theme.text3)
            Text(take.name).font(.hmm(.caption, weight: picked ? .semibold : .regular)).foregroundStyle(picked ? theme.text : theme.text2).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, HmmSpacing.xs)
        .frame(width: TimelineLayout.labelWidth, height: Self.row)
        .contentShape(Rectangle())
        .onTapGesture { editor.live.selectedTake = take.id }
        .accessibilityLabel(take.name)
        .accessibilityValue(NumberFormat.percent(editor.share(of: take)))
        .accessibilityIdentifier("take-\(take.name)")
    }

    private func x(_ time: Double) -> CGFloat { CGFloat((time - editor.timelineStart) * editor.timelineZoom) }

    private func time(at x: CGFloat) -> Double { editor.timelineStart + Double(x) / editor.timelineZoom }

    private func bar(_ take: Take) -> some View {
        Canvas { context, size in
            let whole = CGRect(x: x(take.range.start), y: 6, width: max(x(take.range.end) - x(take.range.start), 2), height: size.height - 12)
            context.fill(Path(roundedRect: whole, cornerRadius: 4), with: .color(theme.surface2))
            for used in take.used {
                let rect = CGRect(x: x(used.start), y: 6, width: max(x(used.end) - x(used.start), 2), height: size.height - 12)
                context.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(theme.accent.opacity(0.85)))
            }
            if let swipe, swipe.take == take.id {
                let rect = CGRect(x: min(swipe.from, swipe.to), y: 2, width: abs(swipe.to - swipe.from), height: size.height - 4)
                context.stroke(Path(roundedRect: rect, cornerRadius: 4), with: .color(theme.accent), lineWidth: 2)
            }
        }
        .frame(width: width, height: Self.row)
        .clipped()
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 8)
            .onChanged { value in swipe = (take.id, value.startLocation.x, value.location.x) }
            .onEnded { value in
                swipe = nil
                let range = TimeRange(start: time(at: value.startLocation.x), end: time(at: value.location.x))
                if range.duration > 0.05 { editor.useTake(take.id, over: range) }
            })
        .onTapGesture { editor.live.selectedTake = take.id }
        .accessibilityHidden(true)
    }

    private func menu(for take: Take) -> HmmHoldMenu {
        var extras = [HmmHoldMenu.Item("Use all of it", id: "take-use", systemName: "checkmark.circle") { editor.useTake(take.id, over: take.range) }]
        if let loop = editor.timeline.loop {
            extras.append(HmmHoldMenu.Item("Use it in the loop", id: "take-use-loop", systemName: "repeat") { editor.useTake(take.id, over: loop) })
        }
        extras.append(HmmHoldMenu.Item("Go to its start", id: "take-go", systemName: "arrow.right.to.line") {
            editor.pause()
            editor.setTime(take.range.start)
        })
        return HmmHoldMenu(rename: {
            name = take.name
            renaming = take
        }, extras: extras, delete: { editor.deleteTake(take.id) })
    }
}
