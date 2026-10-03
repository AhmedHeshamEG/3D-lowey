import HmmDesign
import LoweyCore
import SwiftUI

/// The graph editor: a keyed property as curves over time (X / Y / Z, the turn angles, or the number), key dots you
/// drag in time and value, and the tangent handles of the segment leaving the picked key (its easing). Preset easings
/// apply to that segment. Every drag is one undo step.
struct GraphEditorSheet: View {
    let editor: EditorModel
    @State private var trackID: TrackID
    @State private var picked: Int
    @State private var component = 0
    @State private var hidden: Set<Int> = []
    /// The track while something is dragged (committed when the finger lifts).
    @State private var draft: Track?
    @Environment(\.hmmTheme) private var theme

    init(editor: EditorModel, key: KeyRef) {
        self.editor = editor
        _trackID = State(initialValue: key.track)
        let index = editor.timeline.track(key.track)?.keyframes.firstIndex { abs($0.time - key.time) < 0.0005 } ?? 0
        _picked = State(initialValue: index)
    }

    private var stored: Track? { editor.timeline.track(trackID) }
    private var track: Track? { draft ?? stored }

    var body: some View {
        HmmSheet("Graph", subtitle: "Drag keys in time and value; drag the handles to shape the move between two keys.") {
            if let track, let stored, let first = track.keyframes.first, GraphCurves.components(first.value) != nil {
                let names = GraphCurves.componentNames(first.value)
                properties(of: track.target)
                HStack(spacing: HmmSpacing.xs) {
                    ForEach(names.indices, id: \.self) { index in
                        ChoiceChip(title: names[index], isOn: !hidden.contains(index)) {
                            if hidden.contains(index) { hidden.remove(index) } else { hidden.insert(index) }
                            if !hidden.contains(component) || hidden.count == names.count { return }
                            component = names.indices.first { !hidden.contains($0) } ?? 0
                        }
                        .overlay(alignment: .bottom) { Capsule().fill(Self.color(index, of: names.count)).frame(width: 18, height: 3) }
                    }
                }
                GeometryReader { geometry in
                    // Fitted to the stored curves, so the view holds still while a key is dragged.
                    let frame = GraphFrame(track: stored, components: visible(names.count), size: geometry.size)
                    graph(track, frame: frame)
                }
                .frame(minHeight: 300)
                easings(track)
            } else {
                HmmEmptyState("point.topleft.down.to.point.bottomright.curvepath", title: "Nothing to draw",
                              message: "This property has no curve (colours and switches step from key to key).")
            }
        }
    }

    private func visible(_ count: Int) -> [Int] { (0 ..< count).filter { !hidden.contains($0) } }

    /// The object's graphable properties.
    private func properties(of target: ObjectID) -> some View {
        let tracks = editor.timeline.tracks.filter { track in track.target == target && Self.isCurve(track) }
        let items: [(String, String)] = tracks.map { track in (track.id.raw, track.property.spec?.label ?? track.property.rawValue) }
        return FlowChips(items: items, isOn: { $0 == trackID.raw }) { key in
            trackID = TrackID(raw: key)
            picked = 0
            hidden = []
            component = 0
        }
    }

    private func graph(_ track: Track, frame: GraphFrame) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: HmmRadius.card, style: .continuous).fill(theme.surface2.opacity(0.6))
            Path { path in
                path.addLines([frame.point(time: editor.time, value: frame.values.lowerBound),
                               frame.point(time: editor.time, value: frame.values.upperBound)])
            }
            .stroke(theme.accent.opacity(0.5), lineWidth: 1)
            ForEach(frame.components, id: \.self) { index in
                let points = curvePoints(track, component: index, frame: frame)
                Path { path in path.addLines(points) }
                    .stroke(Self.color(index, of: componentsCount(track)), lineWidth: index == component ? 2.5 : 1.5)
            }
            handles(track, frame: frame)
            ForEach(frame.components, id: \.self) { index in
                ForEach(track.keyframes.indices, id: \.self) { key in
                    keyDot(track, key: key, component: index, frame: frame)
                }
            }
        }
    }

    private func curvePoints(_ track: Track, component index: Int, frame: GraphFrame) -> [CGPoint] {
        let samples = GraphCurves.curve(track, component: index, from: frame.times.lowerBound, to: frame.times.upperBound, count: 160)
        return samples.map { sample in frame.point(time: sample.time, value: sample.value) }
    }

    static func isCurve(_ track: Track) -> Bool {
        guard let first = track.keyframes.first else { return false }
        return GraphCurves.components(first.value) != nil
    }

    private func componentsCount(_ track: Track) -> Int {
        track.keyframes.first.flatMap { GraphCurves.components($0.value)?.count } ?? 1
    }

    private func keyDot(_ track: Track, key: Int, component index: Int, frame: GraphFrame) -> some View {
        let keyframe = track.keyframes[key]
        let value = GraphCurves.components(keyframe.value)?[index] ?? 0
        let isPicked = key == picked
        return Circle()
            .fill(isPicked ? theme.accent : Self.color(index, of: componentsCount(track)))
            .overlay(Circle().stroke(theme.background, lineWidth: 2))
            .frame(width: isPicked ? 16 : 13, height: isPicked ? 16 : 13)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .position(frame.point(time: keyframe.time, value: value))
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    picked = key
                    component = index
                    guard let base = stored else { return }
                    let target = frame.timeValue(at: drag.location)
                    draft = GraphCurves.moving(key: key, in: base, to: target.time, component: index, value: target.value, fps: editor.timeline.fps)
                }
                .onEnded { _ in commit() })
            .accessibilityLabel("Key at \(NumberFormat.short(keyframe.time)) seconds")
    }

    @ViewBuilder private func handles(_ track: Track, frame: GraphFrame) -> some View {
        if frame.components.contains(component), let handles = GraphCurves.handles(track, key: picked, component: component) {
            let start = track.keyframes[picked]
            let end = track.keyframes[picked + 1]
            let startPoint = frame.point(time: start.time, value: GraphCurves.components(start.value)?[component] ?? 0)
            let endPoint = frame.point(time: end.time, value: GraphCurves.components(end.value)?[component] ?? 0)
            ForEach([true, false], id: \.self) { first in
                let handle = first ? handles.first : handles.second
                let point = frame.point(time: handle.time, value: handle.value)
                Path { $0.addLines([first ? startPoint : endPoint, point]) }.stroke(theme.text.opacity(0.55), lineWidth: 1)
                Circle()
                    .stroke(theme.text, lineWidth: 2)
                    .frame(width: 14, height: 14)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                    .position(point)
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            guard var base = stored else { return }
                            let target = frame.timeValue(at: drag.location)
                            guard let easing = GraphCurves.easing(base, key: picked, component: component, first: first, to: target.time,
                                                                  value: target.value) else { return }
                            var keys = base.keyframes
                            keys[picked].easing = easing
                            base.setKeys(keys)
                            draft = base
                        }
                        .onEnded { _ in commit() })
                    .accessibilityLabel(first ? "Leaving handle" : "Arriving handle")
            }
        }
    }

    private func easings(_ track: Track) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: HmmSpacing.xs) {
                ForEach(EasingChoice.allCases) { choice in
                    ChoiceChip(title: choice.title, isOn: track.keyframes.indices.contains(picked) && track.keyframes[picked].easing == choice.easing) {
                        guard var base = stored, base.keyframes.indices.contains(picked) else { return }
                        var keys = base.keyframes
                        keys[picked].easing = choice.easing
                        base.setKeys(keys)
                        editor.replaceTrack(base, label: "Easing")
                    }
                }
            }
        }
    }

    private func commit() {
        if let draft, draft != stored { editor.replaceTrack(draft, label: "Edit curve") }
        draft = nil
    }

    static func color(_ index: Int, of count: Int) -> Color {
        guard count > 1 else { return Color(red: 1, green: 0.72, blue: 0.28) }
        return [Color(red: 1, green: 0.38, blue: 0.36), Color(red: 0.38, green: 0.86, blue: 0.48), Color(red: 0.36, green: 0.62, blue: 1)][index % 3]
    }
}

/// Time and value ranges of the graph, fitted to the visible curves and the picked segment's handles.
private struct GraphFrame {
    var times: ClosedRange<Double>
    var values: ClosedRange<Double>
    var size: CGSize
    var components: [Int]
    let inset: CGFloat = 22

    init(track: Track, components: [Int], size: CGSize) {
        self.size = size
        self.components = components
        let first = track.keyframes.first?.time ?? 0
        let last = max(track.keyframes.last?.time ?? 1, first + 0.1)
        let pad = (last - first) * 0.06
        times = (first - pad) ... (last + pad)
        var low = Double.infinity
        var high = -Double.infinity
        for component in components {
            for sample in GraphCurves.curve(track, component: component, from: first, to: last, count: 80) {
                low = min(low, sample.value)
                high = max(high, sample.value)
            }
        }
        if !low.isFinite { (low, high) = (0, 1) }
        if high - low < 1e-6 { (low, high) = (low - 1, high + 1) }
        let margin = (high - low) * 0.15
        values = (low - margin) ... (high + margin)
    }

    func point(time: Double, value: Double) -> CGPoint {
        let x = inset + CGFloat((time - times.lowerBound) / (times.upperBound - times.lowerBound)) * (size.width - inset * 2)
        let y = size.height - inset - CGFloat((value - values.lowerBound) / (values.upperBound - values.lowerBound)) * (size.height - inset * 2)
        return CGPoint(x: x, y: y)
    }

    func timeValue(at point: CGPoint) -> (time: Double, value: Double) {
        let time = times.lowerBound + Double((point.x - inset) / max(size.width - inset * 2, 1)) * (times.upperBound - times.lowerBound)
        let value = values.lowerBound + Double((size.height - inset - point.y) / max(size.height - inset * 2, 1)) * (values.upperBound - values.lowerBound)
        return (time, value)
    }
}
