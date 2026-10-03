import HmmDesign
import LoweyCore
import SwiftUI
import UIKit

/// The rows under the ruler, with one gesture layer over them: tap a key (or empty time), drag selected keys,
/// box-select (Select mode, or touch and hold then drag), scroll sideways through time, up and down through rows.
struct TimelineLanes: View {
    let editor: EditorModel
    let layout: TimelineLayout
    let width: CGFloat
    let height: CGFloat
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 1) {
                if layout.showsCutRow { CutRow(editor: editor, layout: layout, width: width) }
                ForEach(layout.rows, id: \.self) { row in
                    TimelineRowView(editor: editor, layout: layout, row: row, width: width)
                }
                if layout.rows.isEmpty {
                    Text(emptyHint).font(.hmm(.footnote)).foregroundStyle(theme.text2).frame(maxWidth: .infinity, minHeight: 60)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .overlay(alignment: .topLeading) { marquee }
            .overlay(alignment: .topLeading) { lassoPath }
            .offset(y: -layout.scrollOffset)
        }
        .frame(width: width + TimelineLayout.labelWidth, height: height, alignment: .topLeading)
        .clipped()
        .contentShape(Rectangle())
        .coordinateSpace(name: TimelineLayout.lanesSpace)
        .simultaneousGesture(laneTap, including: editor.timelineMode == .compose ? .subviews : .all)
        .simultaneousGesture(laneDrag)
        .simultaneousGesture(marqueePress, including: editor.timelineMode == .compose ? .subviews : .all)
        .gesture(PencilLasso { point, state in pencilLasso(point, state: state) }, including: editor.timelineMode == .compose ? .subviews : .all)
        .overlay(alignment: .topTrailing) { scrollIndicator }
        .onAppear { layout.viewportHeight = height }
        .onChange(of: height) { _, value in layout.viewportHeight = value }
    }

    private var emptyHint: String {
        switch editor.timelineMode {
        case .perform: "Select something, press Record, and move it while the timeline plays."
        case .keyframe: "Select something and move it: each change becomes a key at the playhead. Or tap a Motion preset."
        case .compose: "Animated things appear here as bars you can slide in time."
        }
    }

    @ViewBuilder private var marquee: some View {
        if let rect = layout.marquee {
            Rectangle()
                .fill(theme.accent.opacity(0.12))
                .overlay(Rectangle().stroke(theme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder private var lassoPath: some View {
        if layout.lasso.count > 1 {
            Path { path in
                path.addLines(layout.lasso)
                path.closeSubpath()
            }
            .fill(theme.accent.opacity(0.1))
            .overlay(Path { $0.addLines(layout.lasso) }.stroke(theme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            .allowsHitTesting(false)
        }
    }

    /// The Pencil draws a loop over the lanes: the keys inside it are picked (added to the pick in Select mode).
    private func pencilLasso(_ point: CGPoint, state: UIGestureRecognizer.State) {
        switch state {
        case .began:
            layout.momentum.stop()
            layout.lasso = [layout.toContent(point)]
        case .changed:
            layout.lasso.append(layout.toContent(point))
        case .ended:
            editor.selectKeys(layout.keys(inside: layout.lasso), additive: editor.keyBoxSelect)
            layout.lasso = []
        default:
            layout.lasso = []
        }
    }

    @ViewBuilder private var scrollIndicator: some View {
        if layout.maxScroll > 0.5, layout.viewportHeight > 20 {
            let bar = max(layout.viewportHeight * layout.viewportHeight / max(layout.contentHeight, 1), 24)
            Capsule()
                .fill(theme.text.opacity(0.35))
                .frame(width: 3, height: bar)
                .offset(x: -3, y: (layout.viewportHeight - bar) * layout.scrollOffset / layout.maxScroll)
                .allowsHitTesting(false)
        }
    }

    // MARK: Gestures

    private var laneTap: some Gesture {
        SpatialTapGesture(coordinateSpace: .named(TimelineLayout.lanesSpace)).onEnded { tap in
            let location = layout.toContent(tap.location)
            guard location.x >= TimelineLayout.labelWidth, !layout.isOwnGestureRow(at: location.y) else { return }
            if editor.timelineMode != .compose, layout.key(at: location) == nil, let clip = layout.clip(at: location) {
                editor.pickClip(clip.id, additive: editor.keyBoxSelect || !editor.selectedClips.isEmpty)
                return
            }
            if let hit = layout.key(at: location) {
                if editor.keyBoxSelect {
                    editor.selectedKeys.formSymmetricDifference([hit])
                } else {
                    editor.selectedKeys = [hit]
                }
                editor.setTime(hit.time)
            } else {
                if !editor.keyBoxSelect { editor.selectedKeys = [] }
                editor.setTime(max(0, layout.time(at: location.x - TimelineLayout.labelWidth)))
            }
        }
    }

    private var laneDrag: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(TimelineLayout.lanesSpace))
            .onChanged { value in
                if layout.laneDrag == nil {
                    layout.momentum.stop()
                    layout.rowMomentum.stop()
                    layout.laneDrag = beginDrag(at: layout.toContent(value.startLocation), translation: value.translation)
                }
                continueDrag(value)
            }
            .onEnded { value in
                endDrag(value)
                layout.keyDrag = nil
                layout.laneDrag = nil
            }
    }

    /// Touch and hold, then drag: a selection box even outside Select mode.
    private var marqueePress: some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(TimelineLayout.lanesSpace)))
            .onChanged { value in
                guard case let .second(true, drag) = value else { return }
                if !layout.marqueeArmed, layout.laneDrag == nil {
                    layout.marqueeArmed = true
                    HmmHaptics.play(.selection)
                }
                if layout.marqueeArmed, let drag { updateMarquee(from: layout.toContent(drag.startLocation), to: layout.toContent(drag.location)) }
            }
            .onEnded { _ in
                if layout.marqueeArmed { commitMarquee() }
                layout.marqueeArmed = false
            }
    }

    private func beginDrag(at start: CGPoint, translation: CGSize) -> TimelineLayout.LaneDrag {
        if layout.marqueeArmed { return .ignore }
        let vertical = abs(translation.height) > abs(translation.width)
        guard start.x >= TimelineLayout.labelWidth, !layout.isOwnGestureRow(at: start.y) else {
            return vertical ? .scrollRows(start: layout.scrollOffset) : .ignore
        }
        if !layout.lasso.isEmpty { return .ignore }
        if editor.timelineMode != .compose {
            if let hit = layout.key(at: start), editor.selectedKeys.contains(hit) {
                layout.keyDrag = 0
                return .moveKeys
            }
            if let clip = layout.clip(at: start), editor.selectedClips.contains(clip.id) {
                layout.keyDrag = 0
                return .moveClips
            }
            if editor.keyBoxSelect { return .marquee(origin: start) }
        } else if startsOnSelectedBar(start) {
            return .ignore
        }
        return vertical ? .scrollRows(start: layout.scrollOffset) : .pan(start: layout.visibleStart)
    }

    private func continueDrag(_ value: DragGesture.Value) {
        switch layout.laneDrag {
        case .moveKeys:
            let earliest = editor.selectedKeys.map(\.time).min() ?? 0
            layout.keyDrag = max(Double(value.translation.width) / layout.pps, -earliest)
        case .moveClips:
            layout.keyDrag = Double(value.translation.width) / layout.pps
        case let .pan(start):
            editor.timelineStart = max(0, start - Double(value.translation.width) / layout.pps)
        case let .scrollRows(start):
            layout.rowScroll = min(max(start - value.translation.height, 0), layout.maxScroll)
        case let .marquee(origin):
            updateMarquee(from: origin, to: layout.toContent(value.location))
        case .ignore, nil:
            break
        }
    }

    private func endDrag(_ value: DragGesture.Value) {
        switch layout.laneDrag {
        case .moveKeys:
            if let delta = layout.keyDrag { editor.moveSelectedKeys(by: delta) }
        case .moveClips:
            if let delta = layout.keyDrag { editor.shiftPickedClips(by: delta) }
        case .marquee:
            commitMarquee()
        case .pan:
            let editor = editor
            layout.momentum.start(velocity: -Double(value.velocity.width) / layout.pps, pointsPerSecond: layout.pps) { delta in
                let next = max(0, editor.timelineStart + delta)
                let moved = next != editor.timelineStart
                editor.timelineStart = next
                return moved
            }
        case .scrollRows:
            let layout = layout
            layout.rowMomentum.start(velocity: -Double(value.velocity.height), pointsPerSecond: 1) { delta in
                let next = min(max(layout.rowScroll + CGFloat(delta), 0), layout.maxScroll)
                let moved = next != layout.rowScroll
                layout.rowScroll = next
                return moved
            }
        default:
            break
        }
    }

    private func startsOnSelectedBar(_ point: CGPoint) -> Bool {
        guard case let .object(id)? = layout.row(at: point.y), editor.selection.contains(id) else { return false }
        let ids = layout.members(of: id)
        let times = editor.timeline.tracks.filter { ids.contains($0.target) }.flatMap { $0.keyframes.map(\.time) }
        guard let start = times.min(), let end = times.max() else { return false }
        let local = point.x - TimelineLayout.labelWidth
        return local >= layout.x(start) - 6 && local <= layout.x(start) + max(CGFloat((end - start) * layout.pps), 10) + 6
    }

    private func updateMarquee(from origin: CGPoint, to location: CGPoint) {
        let rect = CGRect(x: min(origin.x, location.x), y: min(origin.y, location.y), width: abs(location.x - origin.x), height: abs(location.y - origin.y))
        layout.marquee = rect
        let start = layout.time(at: max(rect.minX, TimelineLayout.labelWidth) - TimelineLayout.labelWidth)
        let end = layout.time(at: max(rect.maxX, TimelineLayout.labelWidth) - TimelineLayout.labelWidth)
        var tracks = Set<TrackID>()
        for slot in layout.slots {
            guard let row = slot.row, slot.minY + slot.height >= rect.minY, slot.minY <= rect.maxY else { continue }
            tracks.formUnion(layout.trackIDs(for: row))
        }
        layout.marqueeKeys = tracks.isEmpty ? [] : KeySelection.keys(in: TimeRange(start: start, end: end), tracks: tracks, timeline: editor.timeline)
    }

    private func commitMarquee() {
        if layout.marquee != nil { editor.selectKeys(layout.marqueeKeys, additive: editor.keyBoxSelect) }
        layout.marquee = nil
        layout.marqueeKeys = []
    }
}
